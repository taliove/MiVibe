import Foundation

/// 应用内动作：按键映射的一类目标，触发 MiVibe 自身功能，不发出键盘事件。
/// 与键盘快捷键在映射表中并列，用户可改绑到任意可映射按键（见 CONTEXT.md）。
public enum RemoteAction: String, Codable, Sendable, CaseIterable {
    /// 打开改写模式选单。
    case openModePicker

    public var displayName: String {
        switch self {
        case .openModePicker: return "改写模式选单"
        }
    }
}
