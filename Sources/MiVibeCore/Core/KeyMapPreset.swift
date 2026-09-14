import CoreGraphics
import Foundation

/// 内置的按键映射预设。
///
/// 预设是**数据**，不是一条特殊的代码路径：套用预设就是把 `mapping` 写进某个应用的
/// 映射表，之后它就是一张普通的、可继续编辑的 `AppMapping`。所以"套用后可改"是
/// 结构上成立的，不靠额外保证。
public struct KeyMapPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let shortcuts: [String: Shortcut]

    public var mapping: AppMapping { AppMapping(shortcuts: shortcuts) }

    public init(id: String, name: String, summary: String, shortcuts: [String: Shortcut]) {
        self.id = id
        self.name = name
        self.summary = summary
        self.shortcuts = shortcuts
    }

    /// 「编程助手」——SPEC §1 第一版的目标是 Codex。
    ///
    /// 键码取自 SDK 的 `HIToolbox/Events.h`：0x24 Return、0x35 Escape、
    /// 0x74 PageUp、0x79 PageDown。
    public static let codingAssistant = KeyMapPreset(
        id: "coding-assistant",
        name: "编程助手",
        summary: "确认=发送（↩）· 返回=Esc（打断）· 上/下=翻页",
        shortcuts: [
            RemoteButton.confirm.id: Shortcut(keyCode: 0x24),
            RemoteButton.back.id: Shortcut(keyCode: 0x35),
            RemoteButton.up.id: Shortcut(keyCode: 0x74),
            RemoteButton.down.id: Shortcut(keyCode: 0x79),
        ]
    )

    public static let all: [KeyMapPreset] = [codingAssistant]
}
