import AppKit
import CoreGraphics
import IOKit.hid
import IOKit.hidsystem
import MiVibeCore

/// 按设备重映射探针：HID 独占的替代方案（方案 A）的 go/no-go 闸门。
///
/// 背景：遥控器是键盘类设备，普通进程 seize 会被 IOHIDFamily 以
/// kIOReturnNotPrivileged（0xE00002C1）拒绝。替代思路是**只对这支遥控器**设置
/// `UserKeyMapping`，把它的键映射成"死键"让系统不再响应，MiVibe 仍以非独占方式
/// 从 IOHIDManager 读原始键值、自己合成快捷键。需要逐条实测：
///
/// 1. 非 root 能否写入该服务的 `UserKeyMapping`（写入返回值 + 读回比对）。
/// 2. 重映射后系统（CGEvent 层）是否真的收不到这些键——死键目标选得对不对。
/// 3. 非独占 IOHIDManager 读到的是否仍是**映射前**的原始 usage（否则路由层失明）。
/// 4. 恢复原映射后系统行为是否复原。
///
/// 安全：探针开始前保存原值，正常结束、Ctrl-C、SIGTERM 都会写回。
/// 万一进程被强杀，遥控器断开重连（或 `hidutil property --matching
/// '{"VendorID":0x2717,"ProductID":0x32B8}' --set '{"UserKeyMapping":[]}'`）即可复原。
enum RemapProbe {
    private static let vendorID = 0x2717
    private static let productID = 0x32B8
    private static var mappingKey: CFString { kIOHIDUserKeyUsageMapKey as CFString }
    private static let srcKey = kIOHIDKeyboardModifierMappingSrcKey
    private static let dstKey = kIOHIDKeyboardModifierMappingDstKey
    /// 键盘 usage page 在映射值里的高位前缀：0x7_0000_00xx。
    private static let keyboardPagePrefix: UInt64 = 0x7_0000_0000

    /// 默认死键：键盘页 usage 0（"Reserved / no event indicated"）。可用 `--dst` 换候选。
    private static let defaultDestination: UInt64 = 0x7_0000_0000

    /// 参与重映射的键：除电源键外全部（电源键系统本就无响应，SPEC §3 不接管）。
    private static var remappedButtons: [RemoteButton] { RemoteButton.allCases.filter { $0 != .power } }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [String] = []
        private var _lastHIDKey: RemoteButton?
        var events: [String] {
            lock.lock(); defer { lock.unlock() }
            return _events
        }
        /// 最近一次 HID 按下的键。HID 回调先于系统事件到达（实测），
        /// 据此把系统事件归因到具体按键。
        var lastHIDKey: RemoteButton? {
            lock.lock(); defer { lock.unlock() }
            return _lastHIDKey
        }
        func noteHIDKey(_ key: RemoteButton?) {
            lock.lock(); defer { lock.unlock() }
            _lastHIDKey = key
        }
        /// 最近按下的键若未参与重映射（电源），返回给系统事件的归因标注。
        /// 放在这里而不是 C 回调里直接读静态属性：后者会让 Swift 6.x 编译器崩溃。
        var unremappedTag: String {
            guard let key = lastHIDKey, key == .power else { return "" }
            return "（来自未重映射的\(key.displayName)键）"
        }
        func add(_ line: String) {
            lock.lock(); defer { lock.unlock() }
            _events.append(line)
        }
    }

    /// 需要在信号处理里恢复的现场。单线程（主队列）访问。
    nonisolated(unsafe) private static var restoreServices: [(IOHIDServiceClient, CFTypeRef?)] = []

    // MARK: - 入口

    static func run(arguments: [String]) {
        print("═══ MiVibe 按设备重映射探针（方案 A）═══")
        print("设备：VID 0x\(String(vendorID, radix: 16)) PID 0x\(String(productID, radix: 16))")
        print("")

        let destination = parseDestination(arguments) ?? defaultDestination
        print("死键目标：0x\(String(destination, radix: 16))（可用 --dst 0x... 换候选）")
        reportAccess()

        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let services = matchingServices(client)
        print("匹配到 HID 事件服务：\(services.count) 个")
        guard !services.isEmpty else {
            print("❌ 没找到遥控器的事件服务。确认遥控器已连接（系统设置 → 蓝牙）后重跑。")
            return
        }
        for service in services {
            print("   registryID=\(registryID(service)) 当前 UserKeyMapping=\(describe(IOHIDServiceClientCopyProperty(service, mappingKey)))")
        }
        print("")

        restoreServices = services.map { ($0, IOHIDServiceClientCopyProperty($0, mappingKey)) }
        installRestoreOnSignal()

        let state = State()
        let tap = installListenOnlyTap(into: state)
        if tap == nil {
            print("⚠️  无法建立系统事件监听（缺辅助功能 / 输入监控）。第 2 项将无法判定。")
            print("")
        }
        let hid = makeListenManager(state: state)
        let hidStatus = IOHIDManagerOpen(hid, 0)
        print("IOHIDManagerOpen(非独占) → 0x\(String(format: "%08X", UInt32(bitPattern: hidStatus)))")
        print("")

        // ── A 阶段：基线 ──
        print("── A 阶段：重映射前基线（20 秒）──")
        print("请按：上 下 左 右 确认 返回 主页 菜单 TV 音量+ 音量-（语音键可按一下）")
        countdown(20)
        let baseline = state.events
        printEvents("A 阶段", baseline)

        // ── B 阶段：重映射 ──
        print("── B 阶段：写入重映射 ──")
        let mapping = buildMapping(destination: destination)
        var writeOK = true
        var readbackOK = true
        for service in services {
            let ok = IOHIDServiceClientSetProperty(service, mappingKey, mapping as CFArray)
            let readback = IOHIDServiceClientCopyProperty(service, mappingKey)
            let matches = readbackMatches(readback, expectedCount: mapping.count, destination: destination)
            writeOK = writeOK && ok
            readbackOK = readbackOK && matches
            print("   registryID=\(registryID(service)) SetProperty → \(ok) 读回 \(matches ? "一致" : "不一致：\(describe(readback))")")
        }
        print("")
        print("请再按一遍同样的键（40 秒）。期望：系统事件为空或只有无害事件，HID 仍是原始 usage。")
        let markB = state.events.count
        countdown(40)
        let duringRemap = Array(state.events.dropFirst(markB))
        printEvents("B 阶段", duringRemap)

        // ── C 阶段：恢复 ──
        print("── C 阶段：恢复原映射 ──")
        let restored = restoreAll()
        print("恢复写入：\(restored ? "成功" : "失败 ← 请断开重连遥控器，或执行文件头注释里的 hidutil 命令")")
        print("请再按几个键（15 秒），确认系统恢复响应。")
        let markC = state.events.count
        countdown(15)
        let afterRestore = Array(state.events.dropFirst(markC))
        printEvents("C 阶段", afterRestore)

        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        IOHIDManagerClose(hid, 0)

        printConclusion(writeOK: writeOK, readbackOK: readbackOK, tapAvailable: tap != nil,
                        baseline: baseline, duringRemap: duringRemap, afterRestore: afterRestore,
                        restored: restored)
    }

    // MARK: - 结论

    private static func printConclusion(writeOK: Bool, readbackOK: Bool, tapAvailable: Bool,
                                        baseline: [String], duringRemap: [String],
                                        afterRestore: [String], restored: Bool) {
        let systemDuring = duringRemap.filter { $0.hasPrefix("系统") && !$0.contains("未重映射") }
        let hidDuring = duringRemap.filter { $0.hasPrefix("HID") }
        let hidUnknown = hidDuring.filter { $0.contains("未知") }
        let systemAfter = afterRestore.filter { $0.hasPrefix("系统") }

        print("")
        print("═══════ 结论 ═══════")
        print("1. 非 root 写入 UserKeyMapping：\(writeOK && readbackOK ? "✅ 成功" : "❌ 失败（写入=\(writeOK) 读回=\(readbackOK)）")")
        if tapAvailable {
            print("2. 重映射期间系统收到 \(systemDuring.count) 条事件：\(systemDuring.isEmpty ? "✅ 已抑制" : "⚠️  未完全抑制，逐条看 B 阶段清单判断是否无害")")
        } else {
            print("2. 系统事件抑制：无法判定（没有事件监听）")
        }
        if hidDuring.isEmpty {
            print("3. 重映射期间 HID 回调：❌ 一条都没收到（没按键，或非独占读取失明）")
        } else {
            print("3. 重映射期间 HID 回调 \(hidDuring.count) 条，未识别 usage \(hidUnknown.count) 条：\(hidUnknown.isEmpty ? "✅ 仍是原始 usage" : "❌ 读到的是映射后的值")")
        }
        print("4. 恢复：\(restored ? "写回成功" : "写回失败")；恢复后系统收到 \(systemAfter.count) 条事件\(systemAfter.isEmpty ? "（没按键，或未复原）" : "（已复原）")")
        print("   基线 A 阶段系统事件 \(baseline.filter { $0.hasPrefix("系统") }.count) 条，供对照。")
        print("")
        print("四项都通过 → 方案 A 可行；第 2 项有残留 → 换 --dst 候选重跑（如 0x7000000ff、0xff0000000001）。")
        print("另需单独确认：遥控器断开重连后映射是否丢失（丢失则 App 需在设备出现时重写）。")
    }

    // MARK: - 映射

    private static func buildMapping(destination: UInt64) -> [[String: UInt64]] {
        remappedButtons.map { button in
            [srcKey: keyboardPagePrefix | UInt64(button.rawValue), dstKey: destination]
        }
    }

    private static func readbackMatches(_ value: CFTypeRef?, expectedCount: Int, destination: UInt64) -> Bool {
        guard let entries = value as? [[String: Any]], entries.count == expectedCount else { return false }
        return entries.allSatisfy { entry in
            (entry[dstKey] as? NSNumber)?.uint64Value == destination
        }
    }

    @discardableResult
    private static func restoreAll() -> Bool {
        var ok = true
        for (service, original) in restoreServices {
            let value: CFTypeRef = original ?? ([] as CFArray)
            ok = IOHIDServiceClientSetProperty(service, mappingKey, value) && ok
        }
        return ok
    }

    private static func installRestoreOnSignal() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                print("\n收到信号 \(sig)，恢复原映射后退出…")
                print("恢复写入：\(restoreAll() ? "成功" : "失败 ← 请断开重连遥控器")")
                exit(130)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    nonisolated(unsafe) private static var signalSources: [DispatchSourceSignal] = []

    // MARK: - 服务与监听

    private static func matchingServices(_ client: IOHIDEventSystemClient) -> [IOHIDServiceClient] {
        guard let all = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        return all.filter { service in
            intProperty(service, kIOHIDVendorIDKey) == vendorID
                && intProperty(service, kIOHIDProductIDKey) == productID
        }
    }

    private static func intProperty(_ service: IOHIDServiceClient, _ key: String) -> Int? {
        (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.intValue
    }

    private static func registryID(_ service: IOHIDServiceClient) -> String {
        let id = IOHIDServiceClientGetRegistryID(service) as? NSNumber
        return id.map { String($0.uint64Value, radix: 16) } ?? "?"
    }

    private static func makeListenManager(state: State) -> IOHIDManager {
        let hid = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(hid, [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(state).toOpaque()
        IOHIDManagerRegisterInputValueCallback(hid, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            let state = Unmanaged<State>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == 0x07 else { return }
            let usage = IOHIDElementGetUsage(element)
            // 0x00–0x03 是键盘页的保留 / ErrorRollOver 等占位元素，每次按键前都会
            // 出现一条值为 0 的更新（实测重映射前后都有），不是实体按键。
            guard usage != 0xFFFF_FFFF, usage > 0x03 else { return }
            let isDown = IOHIDValueGetIntegerValue(value) != 0
            let key = RemoteButton(rawValue: usage)
            if isDown { state.noteHIDKey(key) }
            let name = key?.displayName ?? "未知"
            state.add("HID  \(name) usage=0x\(String(usage, radix: 16)) \(isDown ? "按下" : "抬起")")
        }, context)
        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        return hid
    }

    /// 只监听的系统事件监听：键盘事件 + systemDefined（音量等媒体键走这里）。
    private static func installListenOnlyTap(into state: State) -> CFMachPort? {
        let systemDefined: UInt64 = 14
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << systemDefined)
        let context = Unmanaged.passUnretained(state).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let state = Unmanaged<State>.fromOpaque(context).takeUnretainedValue()
                // 由未参与重映射的键（电源）引起的系统事件单独标注，不计入抑制判定。
                let tag = state.unremappedTag
                switch type {
                case .keyDown, .keyUp:
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let label = Shortcut.keyLabel(UInt16(clamping: keyCode))
                    state.add("系统 \(type == .keyDown ? "按下" : "抬起") 键码=\(keyCode)（\(label)）\(tag)")
                case .flagsChanged:
                    state.add("系统 修饰键变化 \(Shortcut.modifierSymbols(from: event.flags))\(tag)")
                default:
                    // systemDefined：subtype 8 是媒体键，data1 高 16 位为键码。
                    if let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 {
                        let code = (ns.data1 & 0xFFFF_0000) >> 16
                        let down = ((ns.data1 & 0xFF00) >> 8) == 0xA
                        state.add("系统 媒体键 code=\(code) \(down ? "按下" : "抬起")\(tag)")
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else { return nil }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return tap
    }

    // MARK: - 杂项

    private static func reportAccess() {
        let listen = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let label: String
        switch listen {
        case kIOHIDAccessTypeGranted: label = "已授权"
        case kIOHIDAccessTypeDenied: label = "已拒绝 ← HID 回调与事件监听可能收不到"
        default:
            label = "未决定，正在请求…"
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        print("▸ 输入监控（本进程的宿主，如终端）：\(label)")
        print("▸ 辅助功能：\(Permissions.hasAccessibility() ? "已授权" : "未授权")")
        print("")
    }

    private static func parseDestination(_ arguments: [String]) -> UInt64? {
        guard let index = arguments.firstIndex(of: "--dst"), index + 1 < arguments.count else { return nil }
        let raw = arguments[index + 1].lowercased().replacingOccurrences(of: "0x", with: "")
        return UInt64(raw, radix: 16)
    }

    private static func describe(_ value: CFTypeRef?) -> String {
        guard let value else { return "(null)" }
        guard let entries = value as? [[String: Any]] else { return "\(value)" }
        if entries.isEmpty { return "[]" }
        return entries.map { entry in
            let src = (entry[srcKey] as? NSNumber)?.uint64Value ?? 0
            let dst = (entry[dstKey] as? NSNumber)?.uint64Value ?? 0
            return "0x\(String(src, radix: 16))→0x\(String(dst, radix: 16))"
        }.joined(separator: ", ")
    }

    private static func printEvents(_ phase: String, _ events: [String]) {
        print("\(phase)收到 \(events.count) 条事件：")
        for line in events { print("   \(line)") }
        print("")
    }

    private static func countdown(_ seconds: Int) {
        var remaining = seconds
        while remaining > 0 {
            if remaining % 5 == 0 || remaining <= 3 {
                print("   剩余 \(remaining)s …（Ctrl-C 中止会自动恢复映射）")
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(1))
            remaining -= 1
        }
    }
}
