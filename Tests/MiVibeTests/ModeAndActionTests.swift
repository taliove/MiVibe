import Foundation
import MiVibeCore

/// 应用内动作、模式选单按键捕获、改写模式解析的验收。
///
/// 选单捕获写错 = 用户和选单交互时按键漏进前台应用（方向键乱移光标）；
/// 模式解析写错 = 用户选了"转录整理"却注入原文。都钉成断言。
enum ModeAndActionTests {
    static func run() {
        actionMappingExclusivity()
        actionMappingCodable()
        routerActions()
        routerPickerCapture()
        rewriteModeResolution()
    }

    // MARK: - 映射表里的动作

    static func actionMappingExclusivity() {
        Harness.suite("应用内动作：与快捷键互斥") {
            var mapping = AppMapping()

            mapping[action: .menu] = .openModePicker
            Harness.expectEqual(mapping[action: .menu], .openModePicker, "动作写入后可读回")

            // 同键写快捷键，动作让位。
            mapping[.menu] = Shortcut(keyCode: 0x24)
            Harness.expectEqual(mapping[action: .menu], nil, "写入快捷键清除同键动作")
            Harness.expectEqual(mapping[.menu], Shortcut(keyCode: 0x24), "快捷键生效")

            // 反向也成立。
            mapping[action: .menu] = .openModePicker
            Harness.expectEqual(mapping[.menu], nil, "写入动作清除同键快捷键")
            Harness.expectEqual(mapping[action: .menu], .openModePicker, "动作生效")

            Harness.expect(mapping.mappedButtons.contains(.menu), "动作映射的按键计入已配置集合")
        }
    }

    static func actionMappingCodable() {
        Harness.suite("应用内动作：编解码与向后兼容") {
            // 老配置没有 actions 字段：解码不失败，动作表为空。
            let legacy = #"{"shortcuts":{"back":{"keyCode":53,"modifiers":0}}}"#.data(using: .utf8)!
            let decoded = try! JSONDecoder().decode(AppMapping.self, from: legacy)
            Harness.expectEqual(decoded.shortcuts.count, 1, "老配置快捷键保留")
            Harness.expectEqual(decoded.actions.count, 0, "老配置缺 actions 解码为空表")

            // 新配置往返一致。
            var mapping = AppMapping()
            mapping[action: .menu] = .openModePicker
            mapping[.back] = Shortcut(keyCode: 0x35)
            let data = try! JSONEncoder().encode(mapping)
            let roundTripped = try! JSONDecoder().decode(AppMapping.self, from: data)
            Harness.expectEqual(roundTripped, mapping, "动作与快捷键往返一致")
        }
    }

    // MARK: - 按键路由

    static func routerActions() {
        Harness.suite("按键路由：应用内动作") {
            var mapping = AppMapping()
            mapping[action: .menu] = .openModePicker

            Harness.expectEqual(
                KeyRouter.disposition(for: .menu, isDown: true, isRepeat: false, mapping: mapping, hasActiveItem: false),
                .performAction(.openModePicker),
                "按下派发动动作"
            )
            Harness.expectEqual(
                KeyRouter.disposition(for: .menu, isDown: true, isRepeat: true, mapping: mapping, hasActiveItem: false),
                .swallow,
                "连发只派一次"
            )
            Harness.expectEqual(
                KeyRouter.disposition(for: .menu, isDown: false, isRepeat: false, mapping: mapping, hasActiveItem: false),
                .swallow,
                "动作键的抬起被吞掉（不转发半截事件）"
            )
        }
    }

    static func routerPickerCapture() {
        Harness.suite("按键路由：选单打开期间的模态捕获") {
            var mapping = AppMapping()
            mapping[.up] = Shortcut(keyCode: 0x7E)   // 映射过的键同样被捕获
            let open = true

            Harness.expectEqual(
                KeyRouter.disposition(for: .up, isDown: true, isRepeat: false, mapping: mapping, hasActiveItem: false, modePickerOpen: open),
                .pickerMove(-1), "上键移动高亮（覆盖已有映射）"
            )
            Harness.expectEqual(
                KeyRouter.disposition(for: .down, isDown: true, isRepeat: false, mapping: mapping, hasActiveItem: false, modePickerOpen: open),
                .pickerMove(1), "下键移动高亮"
            )
            Harness.expectEqual(
                KeyRouter.disposition(for: .up, isDown: true, isRepeat: true, mapping: mapping, hasActiveItem: false, modePickerOpen: open),
                .pickerMove(-1), "方向键连发放行（选单滚动手感）"
            )
            Harness.expectEqual(
                KeyRouter.disposition(for: .confirm, isDown: true, isRepeat: false, mapping: mapping, hasActiveItem: false, modePickerOpen: open),
                .pickerConfirm, "确认键选定"
            )
            Harness.expectEqual(
                KeyRouter.disposition(for: .confirm, isDown: true, isRepeat: true, mapping: mapping, hasActiveItem: false, modePickerOpen: open),
                .swallow, "确认键连发只选一次"
            )
            Harness.expectEqual(
                KeyRouter.disposition(for: .back, isDown: true, isRepeat: false, mapping: mapping, hasActiveItem: true, modePickerOpen: open),
                .pickerDismiss, "选单中返回键关闭选单，优先于取消录音"
            )
            Harness.expectEqual(
                KeyRouter.disposition(for: .left, isDown: true, isRepeat: false, mapping: mapping, hasActiveItem: false, modePickerOpen: open),
                .swallow, "其它键吞掉，不漏进前台应用"
            )
            Harness.expectEqual(
                KeyRouter.disposition(for: .up, isDown: false, isRepeat: false, mapping: mapping, hasActiveItem: false, modePickerOpen: open),
                .swallow, "选单期间所有抬起都吞掉"
            )
        }
    }

    // MARK: - 改写模式解析

    static func rewriteModeResolution() {
        Harness.suite("改写模式解析：未知与空都回落原文直出") {
            let custom = [RewriteMode(id: "c1", name: "我的模式", prompt: "做点什么")]

            Harness.expectEqual(RewriteModes.resolve(activeID: nil, custom: custom), .raw, "nil 是原文直出")
            Harness.expectEqual(RewriteModes.resolve(activeID: "raw", custom: custom), .raw, "raw 是原文直出")
            Harness.expectEqual(RewriteModes.resolve(activeID: "已被删除的模式", custom: custom), .raw, "未知 id 回落原文直出")
            Harness.expectEqual(
                RewriteModes.resolve(activeID: "tidy", custom: custom),
                .llm(name: "转录整理", prompt: RewriteModes.builtins.first { $0.id == "tidy" }!.prompt),
                "内置 id 解析到内置模式"
            )
            Harness.expectEqual(
                RewriteModes.resolve(activeID: "c1", custom: custom),
                .llm(name: "我的模式", prompt: "做点什么"),
                "自定义 id 解析到自定义模式"
            )

            // 内置模式的 prompt 覆盖：覆盖优先，未覆盖的保持默认。
            Harness.expectEqual(
                RewriteModes.resolve(activeID: "tidy", custom: custom,
                                     overrides: ["tidy": "改成我自己的整理方式"]),
                .llm(name: "转录整理", prompt: "改成我自己的整理方式"),
                "内置模式的覆盖 prompt 生效"
            )
            Harness.expectEqual(
                RewriteModes.resolve(activeID: "formal", custom: custom,
                                     overrides: ["tidy": "改成我自己的整理方式"]),
                .llm(name: "正式书面", prompt: RewriteModes.builtins.first { $0.id == "formal" }!.prompt),
                "别的模式的覆盖不影响本模式"
            )
        }
    }
}
