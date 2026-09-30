import Foundation

/// 按键提示（CONTEXT.md「按键提示」、SPEC §13）：实体按键按下时在屏幕中央短暂显示的
/// 「键名 → 实际结果」。
///
/// 纯值 + 纯函数：文案只由该次按键路由的**实际判定**推出，不读配置、不碰界面，
/// 因此每一种判定都能写成测试。提示只反映已经发生的事，不改变按键行为。
public struct KeyHint: Equatable, Sendable {
    /// 按下的键（大字）。
    public let title: String
    /// 这一次实际执行的结果（小字，界面在前面加「→」）。
    public let detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    /// 这次按键走的是哪条路由。
    public enum Route: Equatable, Sendable {
        /// 接管生效：`KeyRouter` 给出的判定（已含应用覆盖与连发规则）。
        case takenOver(KeyDisposition)
        /// 未接管（仅监听）：原生按键由系统处理，只有返回键可能取消录音。
        case listenOnly(hasActiveItem: Bool)
    }

    // MARK: - 文案

    public static let passthroughText = "原样转发"
    public static let systemHandledText = "原样转发（系统处理）"
    public static let cancelText = "取消录音"

    /// 由一次按键事件推出提示；返回 nil 表示这次不显示。
    ///
    /// 不显示的情形：抬起（只有按下出提示）、语音 / 电源键（不可映射）、模式选单打开
    /// 期间（选单本身就是反馈）、以及判定为吞掉的事件（例如映射键的连发——什么也没发生，
    /// 就不假装发生了什么）。
    ///
    /// - Parameters:
    ///   - isRepeat: 自动重复。接管路径下连发规则已体现在判定里；仅监听路径用它区分
    ///     返回键的首次按下（取消录音）与连发（交给系统）。
    ///   - pickerOpen: 按键**发生前**模式选单是否打开。打开选单的那次按键发生前选单
    ///     尚未打开，照常显示「菜单 → 模式选单」。
    public static func make(
        button: RemoteButton,
        isDown: Bool,
        isRepeat: Bool,
        route: Route,
        pickerOpen: Bool
    ) -> KeyHint? {
        guard isDown, button.isMappable, !pickerOpen else { return nil }
        guard let detail = detail(button: button, isRepeat: isRepeat, route: route) else { return nil }
        return KeyHint(title: keyName(for: button), detail: detail)
    }

    private static func detail(button: RemoteButton, isRepeat: Bool, route: Route) -> String? {
        switch route {
        case .listenOnly(let hasActiveItem):
            // 与 Coordinator 仅监听分支一致：返回键首次按下且有进行中的录音才取消。
            if button == .back, hasActiveItem, !isRepeat { return cancelText }
            return systemHandledText
        case .takenOver(let disposition):
            switch disposition {
            case .synthesize(let shortcut): return shortcutText(shortcut)
            case .performAction(let action): return action.hintName
            case .passthrough: return passthroughText
            case .cancelNewestActive: return cancelText
            case .pickerMove, .pickerConfirm, .pickerDismiss, .swallow: return nil
            }
        }
    }

    /// 提示里的键名：方向键用箭头（与设置页键徽标、SPEC 示例「↑ → 原样转发」一致），
    /// 其余用中文名。
    public static func keyName(for button: RemoteButton) -> String {
        switch button {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        default: return button.displayName
        }
    }

    /// 快捷键的提示文案：沿用 `Shortcut.display`，只把 Esc 的符号「⎋」写成「Esc」——
    /// 屏幕中央一闪而过，文字比冷门符号更易认（SPEC 示例「返回 → Esc」）。
    public static func shortcutText(_ shortcut: Shortcut) -> String {
        shortcut.display.replacingOccurrences(of: "⎋", with: "Esc")
    }
}
