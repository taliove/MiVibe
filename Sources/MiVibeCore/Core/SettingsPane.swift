import Foundation

/// 设置页分页（与设置窗口侧栏导航一一对应）。
///
/// 放在 MiVibeCore：分页顺序与 ⌘数字映射是纯数据，需要脱离 UI 目标测试
/// （MiVibeTests 只依赖 MiVibeCore）。rawValue 同时是调试入口
/// （MIVIBE_OPEN_SETTINGS=<pane>）的取值，不得改名，只能追加 case。
public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case recognition, rewrite, keyMapping, remote, appearance, about

    public var id: String { rawValue }

    /// 侧栏与窗口标题。
    public var title: String {
        switch self {
        case .recognition: return "识别"
        case .rewrite: return "改写"
        case .keyMapping: return "按键映射"
        case .remote: return "遥控器"
        case .appearance: return "外观"
        case .about: return "关于"
        }
    }

    /// 侧栏 SF Symbol 名。
    public var icon: String {
        switch self {
        case .recognition: return "waveform"
        case .rewrite: return "sparkles"
        case .keyMapping: return "keyboard"
        case .remote: return "av.remote"
        case .appearance: return "paintpalette"
        case .about: return "info.circle"
        }
    }

    /// ⌘数字键到分页的映射（⌘1 起按 allCases 顺序）。纯函数，越界返回 nil。
    public static func pane(forShortcutDigit digit: Int) -> SettingsPane? {
        let index = digit - 1
        guard allCases.indices.contains(index) else { return nil }
        return allCases[index]
    }
}
