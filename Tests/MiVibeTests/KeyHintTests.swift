import CoreGraphics
import Foundation
import MiVibeCore

/// 按键提示文案的验收（issue #2、SPEC §13）：文案取自该次路由的实际判定，
/// 每种判定、语音键、选单打开、未接管与连发都有断言。
enum KeyHintTests {
    static let cmdReturn = Shortcut(keyCode: 0x24, flags: .maskCommand)
    static let esc = Shortcut(keyCode: 0x35)

    static func hint(_ button: RemoteButton, _ disposition: KeyDisposition,
                     isDown: Bool = true, isRepeat: Bool = false, pickerOpen: Bool = false) -> KeyHint? {
        KeyHint.make(button: button, isDown: isDown, isRepeat: isRepeat,
                     route: .takenOver(disposition), pickerOpen: pickerOpen)
    }

    static func listen(_ button: RemoteButton, active: Bool = false,
                       isDown: Bool = true, isRepeat: Bool = false) -> KeyHint? {
        KeyHint.make(button: button, isDown: isDown, isRepeat: isRepeat,
                     route: .listenOnly(hasActiveItem: active), pickerOpen: false)
    }

    static func run() {
        takenOverDispositions()
        hiddenCases()
        listenOnly()
        repeats()
        realRouting()
        keyNamesAndTiming()
        legacyConfig()
    }

    static func takenOverDispositions() {
        Harness.suite("KeyHint 接管路径：每种判定的文案") {
            Harness.expectEqual(hint(.confirm, .synthesize(cmdReturn)),
                                KeyHint(title: "确认", detail: "⌘↩"), "快捷键显示其组合：确认 → ⌘↩")
            Harness.expectEqual(hint(.back, .synthesize(esc)),
                                KeyHint(title: "返回", detail: "Esc"), "返回键内置默认：返回 → Esc")
            Harness.expectEqual(hint(.menu, .performAction(.openModePicker)),
                                KeyHint(title: "菜单", detail: "模式选单"), "应用内动作显示动作名：菜单 → 模式选单")
            Harness.expectEqual(hint(.up, .passthrough),
                                KeyHint(title: "↑", detail: "原样转发"), "未映射：↑ → 原样转发")
            Harness.expectEqual(hint(.back, .cancelNewestActive),
                                KeyHint(title: "返回", detail: "取消录音"), "录音中返回：返回 → 取消录音")
            Harness.expectEqual(KeyHint.shortcutText(Shortcut(keyCode: 0x35, flags: .maskCommand)), "⌘Esc",
                                "带修饰键的 Esc 同样写成 Esc")
        }
    }

    static func hiddenCases() {
        Harness.suite("KeyHint 不显示的情形") {
            Harness.expect(hint(.tv, .swallow) == nil, "吞掉的事件不显示")
            Harness.expect(hint(.up, .pickerMove(-1)) == nil, "选单移动不显示")
            Harness.expect(hint(.confirm, .pickerConfirm) == nil, "选单确认不显示")
            Harness.expect(hint(.back, .pickerDismiss) == nil, "选单关闭不显示")
            Harness.expect(hint(.up, .passthrough, pickerOpen: true) == nil, "选单打开期间任何判定都不显示")
            Harness.expect(hint(.voice, .passthrough) == nil, "语音键不显示")
            Harness.expect(hint(.power, .passthrough) == nil, "电源键不显示")
            Harness.expect(listen(.voice) == nil, "仅监听时语音键也不显示")
            Harness.expect(hint(.up, .passthrough, isDown: false) == nil, "抬起不显示（转发抬起也不显示）")
            Harness.expect(listen(.back, active: true, isDown: false) == nil, "仅监听时抬起不显示")
        }
    }

    static func listenOnly() {
        Harness.suite("KeyHint 未接管（仅监听）") {
            Harness.expectEqual(listen(.confirm), KeyHint(title: "确认", detail: "原样转发（系统处理）"),
                                "未接管：原样转发（系统处理）")
            Harness.expectEqual(listen(.back), KeyHint(title: "返回", detail: "原样转发（系统处理）"),
                                "没有进行中的录音时返回键交给系统")
            Harness.expectEqual(listen(.back, active: true), KeyHint(title: "返回", detail: "取消录音"),
                                "有进行中的录音时返回键取消录音")
            Harness.expectEqual(listen(.back, active: true, isRepeat: true)?.detail, "原样转发（系统处理）",
                                "返回键连发不再取消，交给系统")
        }
    }

    static func repeats() {
        Harness.suite("KeyHint 连发") {
            Harness.expectEqual(hint(.down, .passthrough, isRepeat: true)?.detail, "原样转发",
                                "未映射键连发照常转发，提示原地更新")
            Harness.expect(hint(.confirm, .swallow, isRepeat: true) == nil, "映射键连发被吞，不出新提示")
            Harness.expectEqual(listen(.left, isRepeat: true)?.title, "←", "仅监听连发同样有提示")
        }
    }

    /// 与 `KeyRouter` 串起来：文案真的取自路由判定（含应用覆盖）。
    static func realRouting() {
        Harness.suite("KeyHint × KeyRouter 实际判定") {
            func routed(_ button: RemoteButton, mapping: AppMapping, active: Bool = false,
                        isRepeat: Bool = false) -> KeyHint? {
                let d = KeyRouter.disposition(for: button, isDown: true, isRepeat: isRepeat,
                                              mapping: mapping, hasActiveItem: active)
                return KeyHint.make(button: button, isDown: true, isRepeat: isRepeat,
                                    route: .takenOver(d), pickerOpen: false)
            }
            let table = KeyMapTable(
                defaultMapping: AppMapping(actions: [RemoteButton.menu.id: .openModePicker]),
                perApp: ["com.example.chat": AppMapping(shortcuts: [RemoteButton.confirm.id: cmdReturn])]
            )
            let defaults = table.mapping(forBundleID: nil)
            let chat = table.mapping(forBundleID: "com.example.chat")
            Harness.expectEqual(routed(.confirm, mapping: chat)?.detail, "⌘↩", "应用覆盖生效时显示覆盖的快捷键")
            Harness.expectEqual(routed(.confirm, mapping: defaults)?.detail, "原样转发", "默认表未映射确认：原样转发")
            Harness.expectEqual(routed(.menu, mapping: defaults)?.detail, "模式选单", "菜单默认打开模式选单")
            Harness.expectEqual(routed(.back, mapping: defaults)?.detail, "Esc", "返回键默认合成 Esc")
            Harness.expectEqual(routed(.back, mapping: defaults, active: true)?.detail, "取消录音",
                                "录音中返回优先取消")
            Harness.expect(routed(.confirm, mapping: chat, isRepeat: true) == nil, "按住已映射键不重复提示")
        }
    }

    static func keyNamesAndTiming() {
        Harness.suite("KeyHint 键名与时长") {
            Harness.expectEqual(RemoteButton.mappable.map(KeyHint.keyName(for:)),
                                ["↑", "↓", "←", "→", "确认", "返回", "音量+", "音量-", "主页", "菜单", "TV"],
                                "方向键用箭头，其余沿用中文名")
            Harness.expectEqual(MotionTiming.keyHintHideDelay, 0.8, "约 0.8 s 后淡出")
        }
    }

    static func legacyConfig() {
        Harness.suite("KeyHint 配置字段兼容") {
            let legacy = #"{"doubaoAPIKey":"sk-abcdef","enableNonstream":true,"keyTakeover":false}"#
            let decoded = legacy.data(using: .utf8)
                .flatMap { try? JSONDecoder().decode(Config.Data.self, from: $0) }
            Harness.expectEqual(decoded?.doubaoAPIKey, "sk-abcdef", "没有 keyHints 的老配置能解码，Key 存活")
            Harness.expect(decoded?.keyHints == nil, "缺失字段解码为 nil")
            Harness.expect(decoded?.effectiveKeyHints == true, "按键提示默认开启")

            var off = Config.Data()
            off.keyHints = false
            let roundTrip = (try? JSONEncoder().encode(off))
                .flatMap { try? JSONDecoder().decode(Config.Data.self, from: $0) }
            Harness.expect(roundTrip?.effectiveKeyHints == false, "关闭后写盘再读仍为关闭")
        }
    }
}
