import ApplicationServices
import AppKit

/// 跨应用文本注入（SPEC §5，由 inject-probe 实测得出）。
///
/// 策略：运行时探测焦点元素 → `AXSelectedText` 可写就定点直写；否则剪贴板快照
/// + 定向 Cmd+V + 恢复。安全输入框拒绝。**不做 AX 失败后自动改粘贴的双写**，
/// 避免重复输入。
public enum TextInjector {
    public enum Target: Equatable {
        case ax(pid: pid_t)
        case paste(pid: pid_t)
        case refusedSecureField
        case noFocus
        case noPermission
    }

    public enum InjectError: Error, LocalizedError {
        case noPermission
        case noFocusedElement
        case secureField
        case axWriteFailed(AXError)
        case pasteboardBusy
        case eventPostFailed

        public var errorDescription: String? {
            switch self {
            case .noPermission: return "缺少辅助功能或事件投递权限"
            case .noFocusedElement: return "找不到输入焦点"
            case .secureField: return "目标是密码框，已拒绝输入"
            case .axWriteFailed(let error): return "直接写入失败（AXError \(error.rawValue)）"
            case .pasteboardBusy: return "剪贴板被其他程序占用"
            case .eventPostFailed: return "粘贴按键投递失败"
            }
        }
    }

    /// 当前焦点的注入能力，供按下语音键时抓取快照。
    public struct Snapshot: Equatable {
        public let pid: pid_t
        public let element: AXUIElement
        public let selectedTextSettable: Bool
        public let isSecure: Bool

        public static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
            lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
        }
    }

    // MARK: - 探测

    /// 抓取当前前台应用的焦点元素。按下语音键时调用，松手写入前**再抓一次**比对。
    public static func snapshotFocus() -> Snapshot? {
        guard Permissions.hasAccessibility(),
              let front = NSWorkspace.shared.frontmostApplication
        else { return nil }

        let pid = front.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }

        let app = AXUIElementCreateApplication(pid)
        enableFullAccessibilityIfNeeded(app: app)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused as! AXUIElement?
        else { return nil }

        guard !isRefusedSystemTarget(pid: pid) else { return nil }

        let subrole = stringAttribute(element, kAXSubroleAttribute) ?? ""
        return Snapshot(
            pid: pid,
            element: element,
            selectedTextSettable: isSettable(element, kAXSelectedTextAttribute),
            isSecure: subrole.contains("Secure")
        )
    }

    /// Chromium/Electron 系应用（飞书、Chrome、VS Code 等）默认只建残缺的 AX 树：
    /// 焦点元素声称 AXSelectedText 可写、set 也返回 success，但 DOM 纹丝不动。
    /// 设上 AXEnhancedUserInterface 后才建完整树、写入才真实生效——
    /// Vimac / Homerow 等工具的标准做法。对原生应用设这个属性是无害 no-op。
    ///
    /// 注意副作用：首次开启时 Chromium 会重建 AX 树，焦点元素的 identity 会变。
    /// 所以在取焦点**之前**开，保证按下/注入两次快照看到的是同一棵树。
    private static func enableFullAccessibilityIfNeeded(app: AXUIElement) {
        var value: CFTypeRef?
        let key = "AXEnhancedUserInterface" as CFString
        if AXUIElementCopyAttributeValue(app, key, &value) == .success,
           (value as? Bool) == true {
            return
        }
        AXUIElementSetAttributeValue(app, key, true as CFTypeRef)
    }

    // MARK: - 注入

    /// 把文字写入快照对应的目标。
    ///
    /// 调用前应确认焦点未变（由 Coordinator 负责比对，变了就暂存而不是强写）。
    @discardableResult
    public static func inject(_ text: String, into snapshot: Snapshot) throws -> Target {
        guard Permissions.hasAccessibility() else { throw InjectError.noPermission }
        guard !snapshot.isSecure else { throw InjectError.secureField }

        if snapshot.selectedTextSettable {
            let error = AXUIElementSetAttributeValue(
                snapshot.element,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            guard error == .success else { throw InjectError.axWriteFailed(error) }

            // Chromium 的假成功：set 返回 success 但 DOM 没变。读回验证——
            // SPEC §5 禁止的是"无验证的盲目双写"，验证失败才粘贴不会重复输入。
            if verifyInserted(text, in: snapshot.element) {
                return .ax(pid: snapshot.pid)
            }
            Log.chain.notice("AX write not reflected, falling back to paste")
            try paste(text, to: snapshot.pid)
            return .paste(pid: snapshot.pid)
        }

        try paste(text, to: snapshot.pid)
        return .paste(pid: snapshot.pid)
    }

    /// 读回验证：AX 写入的文字是否真的出现在元素内容里。
    /// Chromium 应用写入到 DOM 反射有一拍延迟，所以重试几次再判失败。
    private static func verifyInserted(_ text: String, in element: AXUIElement) -> Bool {
        for attempt in 0..<3 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.1) }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
                  let content = value as? String
            else { continue }
            if content.contains(text) { return true }
        }
        return false
    }

    /// 系统级 UI（锁屏、登录窗、Spotlight 等）不是有效的输入目标。
    /// 这些进程会"接受"事件却不落字，粘贴路径无法自证成功，只能靠拒绝进入。
    private static let refusedBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.ScreenSaver.Engine",
        "com.apple.Spotlight",
        "com.apple.systemuiserver",
    ]

    public static func isRefusedSystemTarget(pid: pid_t) -> Bool {
        guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        else { return false }
        return refusedBundleIDs.contains(bundleID)
    }

    // MARK: - 剪贴板路径

    /// 剪贴板快照 → 写入 → 定向 Cmd+V → 恢复。
    ///
    /// 恢复是**尽力而为**：期间若被第三方改动（changeCount 不符）就放弃恢复，
    /// 不覆盖别人的内容。惰性提供的数据本身无法完整恢复，这一点不做承诺。
    private static func paste(_ text: String, to pid: pid_t) throws {
        guard Permissions.hasEventPosting() else { throw InjectError.noPermission }

        let pasteboard = NSPasteboard.general
        let saved: [(NSPasteboard.PasteboardType, Data)] = (pasteboard.pasteboardItems ?? [])
            .flatMap { item in
                item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ours = pasteboard.changeCount

        try postCommandV(to: pid)

        // 给目标应用一点时间消费剪贴板；没有"粘贴完成"回调，这是启发式。
        Thread.sleep(forTimeInterval: 0.15)

        guard pasteboard.changeCount == ours else { return }  // 被别人改过，不恢复
        guard !saved.isEmpty else { return }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for (type, data) in saved { item.setData(data, forType: type) }
        pasteboard.writeObjects([item])
    }

    private static func postCommandV(to pid: pid_t) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw InjectError.eventPostFailed
        }
        let vKey: CGKeyCode = 0x09  // ANSI 'V'
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { throw InjectError.eventPostFailed }

        down.flags = .maskCommand
        up.flags = .maskCommand
        // 定向投递给目标进程，减少（但不消除）打错目标的竞争窗口。
        down.postToPid(pid)
        up.postToPid(pid)
    }

    // MARK: - AX 小工具

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }
}
