import Foundation
import MiVibeCore

/// 设置分页顺序与快捷键映射的验收（spec D，epic #1 子任务 #5）。
///
/// 守的契约：
/// - `SettingsPane.allCases` 的顺序即侧栏顺序：识别 / 改写 / 按键映射 / 遥控器 / 外观 / 关于，
///   「外观」在「关于」之前（rawValue 是持久化键，不得改名，只能新增 case）。
/// - ⌘1–⌘6 按下标映射到分页，`pane(forShortcutDigit:)` 是纯函数，越界返回 nil。
enum SettingsPaneTests {
    static func run() {
        order()
        shortcutMapping()
    }

    static func order() {
        Harness.suite("设置分页：顺序") {
            Harness.expectEqual(SettingsPane.allCases.map(\.rawValue),
                                ["recognition", "rewrite", "keyMapping", "remote", "appearance", "about"],
                                "外观在关于之前")
            Harness.expectEqual(SettingsPane.appearance.title, "外观", "外观页标题")
            Harness.expectEqual(SettingsPane.appearance.icon, "paintpalette", "外观页图标")
            Harness.expectEqual(SettingsPane.about.title, "关于", "关于页标题")
        }
    }

    static func shortcutMapping() {
        Harness.suite("设置分页：⌘数字映射") {
            Harness.expectEqual(SettingsPane.pane(forShortcutDigit: 1), .recognition, "⌘1 识别")
            Harness.expectEqual(SettingsPane.pane(forShortcutDigit: 2), .rewrite, "⌘2 改写")
            Harness.expectEqual(SettingsPane.pane(forShortcutDigit: 3), .keyMapping, "⌘3 按键映射")
            Harness.expectEqual(SettingsPane.pane(forShortcutDigit: 4), .remote, "⌘4 遥控器")
            Harness.expectEqual(SettingsPane.pane(forShortcutDigit: 5), .appearance, "⌘5 外观")
            Harness.expectEqual(SettingsPane.pane(forShortcutDigit: 6), .about, "⌘6 关于")
            Harness.expect(SettingsPane.pane(forShortcutDigit: 0) == nil, "⌘0 无映射")
            Harness.expect(SettingsPane.pane(forShortcutDigit: 7) == nil, "⌘7 无映射")
            Harness.expect(SettingsPane.pane(forShortcutDigit: -1) == nil, "负数无映射")
        }
    }
}
