import AppKit
import Foundation
import MiVibeCore

/// 按键映射的验收。
///
/// 这些不是"顺手测一下"：映射表直接决定用户按一下遥控器会发生什么，配错了就是
/// 往编辑器里打进一个错误的快捷键。所以解析规则、保留按键、转发覆盖度都钉成断言。
enum KeyMappingTests {
    static func run() {
        remoteButtonIdentity()
        shortcutDisplay()
        shortcutFlagConversion()
        mappingResolution()
        bindingSource()
        updateMappingOverrides()
        mergeMutex()
        startupNormalization()
        presetApplying()
        codableRoundTrip()
        presetShape()
        passthroughCoverage()
        routerVoiceAndPower()
        routerBackPriority()
        routerMappedButtons()
        routerUnmappedButtons()
    }

    // MARK: - 按键身份

    static func remoteButtonIdentity() {
        Harness.suite("按键身份：id 稳定、语音与电源不可映射") {
            // id 是配置文件的键，改名等于静默丢弃用户配过的所有按键。
            Harness.expectEqual(RemoteButton.confirm.id, "confirm", "确认键 id 为 confirm")
            Harness.expectEqual(RemoteButton.back.id, "back", "返回键 id 为 back")
            Harness.expectEqual(RemoteButton.volumeUp.id, "volumeUp", "音量+ id 为 volumeUp")

            // 每个 id 都能反查回来（往返一致）。
            for button in RemoteButton.allCases {
                Harness.expectEqual(
                    RemoteButton.from(id: button.id),
                    button,
                    "\(button.displayName) 的 id 能反查"
                )
            }
            Harness.expectEqual(RemoteButton.from(id: "不存在的键"), nil, "未知 id 返回 nil")

            Harness.expect(!RemoteButton.voice.isMappable, "语音键不可映射（保留按住说话）")
            Harness.expect(!RemoteButton.power.isMappable, "电源键不可映射（系统无响应）")
            Harness.expectEqual(RemoteButton.mappable.count, 11, "可映射按键共 11 个")
            Harness.expect(
                !RemoteButton.mappable.contains(.voice) && !RemoteButton.mappable.contains(.power),
                "可映射列表里不含语音与电源"
            )
        }
    }

    // MARK: - Shortcut

    static func shortcutDisplay() {
        Harness.suite("快捷键显示串") {
            let cmdShiftP = Shortcut(
                keyCode: 0x23,   // kVK_ANSI_P
                flags: Shortcut.flags(from: [.command, .shift])
            )
            Harness.expectEqual(cmdShiftP.display, "⇧⌘P", "修饰键按 ⇧⌘ 规范顺序书写")

            let allMods = Shortcut(
                keyCode: 0x23,
                flags: Shortcut.flags(from: [.command, .shift, .option, .control])
            )
            Harness.expectEqual(allMods.display, "⌃⌥⇧⌘P", "四个修饰键顺序为 ⌃⌥⇧⌘")

            Harness.expectEqual(Shortcut(keyCode: 0x24).display, "↩", "Return 显示为 ↩")
            Harness.expectEqual(Shortcut(keyCode: 0x35).display, "⎋", "Escape 显示为 ⎋")
            Harness.expectEqual(Shortcut(keyCode: 0x74).display, "⇞", "PageUp 显示为 ⇞")
            Harness.expectEqual(Shortcut(keyCode: 0x7E).display, "↑", "方向键显示为箭头")
        }
    }

    static func shortcutFlagConversion() {
        Harness.suite("NSEvent 修饰键 → CGEvent 修饰键") {
            let converted = Shortcut.flags(from: [.command, .option])
            Harness.expect(converted.contains(.maskCommand), "command → maskCommand")
            Harness.expect(converted.contains(.maskAlternate), "option → maskAlternate")
            Harness.expect(!converted.contains(.maskShift), "未按下的 shift 不出现")
            Harness.expect(!converted.contains(.maskControl), "未按下的 control 不出现")

            Harness.expect(
                Shortcut.flags(from: [.control]).contains(.maskControl),
                "control → maskControl"
            )

            // 显式换算的真正价值在这里：过滤掉 NSEvent 独有、CGEvent 里没有对应含义的位。
            // capsLock 的 rawValue 是 0x10000，正好撞上 CGEventFlags.maskAlphaShift——
            // 强转就会把"大写锁定"当成一个修饰键带进合成事件里。
            let withExtras = Shortcut.flags(from: [.command, .capsLock, .numericPad, .function])
            Harness.expect(withExtras.contains(.maskCommand), "command 仍在")
            Harness.expect(!withExtras.contains(.maskAlphaShift), "capsLock 被过滤掉")
            Harness.expectEqual(
                withExtras.rawValue,
                CGEventFlags.maskCommand.rawValue,
                "只剩 command 一位，其余 NSEvent 独有的位都被过滤"
            )
        }
    }

    // MARK: - 映射解析

    static func mappingResolution() {
        Harness.suite("映射解析：应用专用表按键覆盖，其余继承默认表") {
            var table = KeyMapTable()
            table.defaultMapping[.confirm] = Shortcut(keyCode: 0x24)
            table.defaultMapping[.up] = Shortcut(keyCode: 0x7E)

            var overrides = AppMapping()
            overrides[.confirm] = Shortcut(keyCode: 0x4C)   // 该应用里改成小键盘回车
            table.setMapping(overrides, forBundleID: "com.example.editor")

            // 应用专用表命中：覆盖的键用自己的，没覆盖的继承默认表。
            let inApp = table.mapping(forBundleID: "com.example.editor")
            Harness.expectEqual(inApp[.confirm]?.keyCode, 0x4C, "覆盖的键用应用自己的绑定")
            Harness.expectEqual(inApp[.up]?.keyCode, 0x7E, "未覆盖的键继承默认表")

            // 未列出的应用走默认表。
            let other = table.mapping(forBundleID: "com.example.other")
            Harness.expectEqual(other[.confirm]?.keyCode, 0x24, "未列出的应用走默认表")
            Harness.expectEqual(other[.up]?.keyCode, 0x7E, "默认表的其它键也在")

            // 拿不到前台应用时也走默认表。
            Harness.expectEqual(
                table.mapping(forBundleID: nil)[.confirm]?.keyCode,
                0x24,
                "bundleID 为 nil 时走默认表"
            )

            Harness.expect(table.hasMapping(forBundleID: "com.example.editor"), "查得到已配的应用")
            Harness.expectEqual(
                table.overrideCount(forBundleID: "com.example.editor"), 1,
                "覆盖数只算真覆盖的键"
            )
            table.removeMapping(forBundleID: "com.example.editor")
            Harness.expect(
                !table.hasMapping(forBundleID: "com.example.editor"),
                "删除后不再有专用映射"
            )
            Harness.expectEqual(
                table.mapping(forBundleID: "com.example.editor")[.confirm]?.keyCode,
                0x24,
                "删除专用映射后回落到默认表"
            )
        }
    }

    /// `bindingSource` 是设置页给遥控器按键打标记的来源查询：四种取值（未绑定 /
    /// 本范围自有 / 继承默认 / 应用覆盖）× 快捷键与动作两种目标都要钉死。
    static func bindingSource() {
        Harness.suite("绑定来源：own / inherited / overridden / unbound") {
            // 默认作用范围（bundleID = nil）只可能出现 own / unbound。
            var table = KeyMapTable()
            table.defaultMapping[.confirm] = Shortcut(keyCode: 0x24)
            table.defaultMapping[action: .back] = .openModePicker
            Harness.expectEqual(
                table.bindingSource(of: .confirm, forBundleID: nil), .own,
                "默认表有快捷键 → own"
            )
            Harness.expectEqual(
                table.bindingSource(of: .back, forBundleID: nil), .own,
                "默认表有动作 → own"
            )
            Harness.expectEqual(
                table.bindingSource(of: .up, forBundleID: nil), .unbound,
                "默认表没有的键 → unbound"
            )

            // 应用有覆盖表：覆盖的键（快捷键与动作都算）为 overridden，其余继承。
            table.updateMapping(forBundleID: "com.example.app") { mapping in
                mapping[.confirm] = Shortcut(keyCode: 0x4C)
            }
            Harness.expectEqual(
                table.bindingSource(of: .confirm, forBundleID: "com.example.app"), .overridden,
                "覆盖表里有快捷键 → overridden"
            )
            Harness.expectEqual(
                table.bindingSource(of: .back, forBundleID: "com.example.app"), .inherited,
                "覆盖表没有、默认表有 → inherited"
            )
            Harness.expectEqual(
                table.bindingSource(of: .up, forBundleID: "com.example.app"), .unbound,
                "两边都没有 → unbound"
            )

            // 覆盖目标是动作时同样算 overridden。
            table.updateMapping(forBundleID: "com.example.app") { mapping in
                mapping[action: .up] = .openModePicker
            }
            Harness.expectEqual(
                table.bindingSource(of: .up, forBundleID: "com.example.app"), .overridden,
                "覆盖表里有动作 → overridden"
            )

            // 应用没有覆盖表时等价于空覆盖表：全继承或完全未绑定。
            Harness.expectEqual(
                table.bindingSource(of: .back, forBundleID: "com.example.other"), .inherited,
                "无覆盖表的应用 → inherited"
            )
            Harness.expectEqual(
                table.bindingSource(of: .left, forBundleID: "com.example.other"), .unbound,
                "无覆盖表且默认表也没有 → unbound"
            )
        }
    }

    /// `updateMapping` 是设置页的编辑入口：应用范围只写覆盖（不克隆默认表），
    /// 默认表之后的改动对未覆盖的键照常生效。
    static func updateMappingOverrides() {
        Harness.suite("编辑入口：应用范围只写覆盖，跟随默认表") {
            var table = KeyMapTable()
            table.defaultMapping[.confirm] = Shortcut(keyCode: 0x24)

            // 首次编辑应用：只把这条改动写进覆盖表，不克隆默认表。
            table.updateMapping(forBundleID: "com.example.app") { mapping in
                mapping[.back] = Shortcut(keyCode: 0x35)
            }
            let app = table.mapping(forBundleID: "com.example.app")
            Harness.expectEqual(app[.back]?.keyCode, 0x35, "新配的覆盖键在")
            Harness.expectEqual(app[.confirm]?.keyCode, 0x24, "默认表的键自动继承")
            Harness.expect(table.hasMapping(forBundleID: "com.example.app"), "产生了专用表")
            Harness.expectEqual(
                table.perApp["com.example.app"]?.shortcuts.count, 1,
                "覆盖表只存真覆盖的那一条"
            )

            // 默认表没被连带改动。
            Harness.expectEqual(table.defaultMapping[.back], nil, "默认表不受影响")

            // 之后再改默认表，未覆盖的键跟着生效。
            table.updateMapping(forBundleID: nil) { mapping in
                mapping[.down] = Shortcut(keyCode: 0x79)
            }
            Harness.expectEqual(table.defaultMapping[.down]?.keyCode, 0x79, "默认表改成功")
            Harness.expectEqual(
                table.mapping(forBundleID: "com.example.app")[.down]?.keyCode, 0x79,
                "默认表的改动对未覆盖键生效"
            )

            // 覆盖优先于继承。
            table.updateMapping(forBundleID: "com.example.app") { mapping in
                mapping[.down] = Shortcut(keyCode: 0x74)
            }
            Harness.expectEqual(
                table.mapping(forBundleID: "com.example.app")[.down]?.keyCode, 0x74,
                "覆盖键用自己的绑定"
            )

            // 清除覆盖 = 回到继承，且覆盖表里的冗余条目被收走。
            table.updateMapping(forBundleID: "com.example.app") { mapping in
                mapping[.down] = nil
            }
            Harness.expectEqual(
                table.mapping(forBundleID: "com.example.app")[.down]?.keyCode, 0x79,
                "清除覆盖后回落到默认表"
            )
            Harness.expectEqual(
                table.perApp["com.example.app"]?[.down], nil,
                "覆盖表不再持有该键"
            )

            // 写入与默认表一致的绑定属于冗余，立即收回继承（覆盖数因此永远准确）。
            table.updateMapping(forBundleID: "com.example.app") { mapping in
                mapping[.confirm] = Shortcut(keyCode: 0x24)
            }
            Harness.expectEqual(
                table.perApp["com.example.app"]?[.confirm], nil,
                "与默认表一致的写入不形成覆盖"
            )
        }
    }

    /// 合并时快捷键与应用内动作互斥：覆盖侧是什么，生效侧就是什么。
    static func mergeMutex() {
        Harness.suite("合并互斥：覆盖动作顶掉默认快捷键") {
            var table = KeyMapTable()
            table.defaultMapping[.menu] = Shortcut(keyCode: 0x24)
            table.updateMapping(forBundleID: "com.example.app") { mapping in
                mapping[action: .menu] = .openModePicker
            }
            let merged = table.mapping(forBundleID: "com.example.app")
            Harness.expectEqual(merged[.menu], nil, "默认快捷键被覆盖动作顶掉")
            Harness.expectEqual(merged[action: .menu], .openModePicker, "覆盖动作生效")
        }
    }

    /// 老版本的应用专用表是默认表的整表克隆。启动整理（`normalized`）逐条比对：
    /// 与默认表一致的收回继承，真改过的保留为覆盖——生效行为不变，但配置变成继承语义。
    static func startupNormalization() {
        Harness.suite("启动整理：旧克隆配置迁移为覆盖") {
            var table = KeyMapTable()
            table.defaultMapping[.confirm] = Shortcut(keyCode: 0x24)
            table.defaultMapping[.up] = Shortcut(keyCode: 0x7E)
            var legacy = AppMapping()
            legacy[.confirm] = Shortcut(keyCode: 0x24)   // 与默认一致（克隆残留）
            legacy[.up] = Shortcut(keyCode: 0x74)        // 用户真改过
            table.setMapping(legacy, forBundleID: "com.example.app")

            let normalized = table.normalized()
            Harness.expectEqual(
                normalized.perApp["com.example.app"]?[.confirm], nil,
                "与默认一致的条目被收回继承"
            )
            Harness.expectEqual(
                normalized.perApp["com.example.app"]?[.up]?.keyCode, 0x74,
                "真覆盖保留"
            )
            Harness.expectEqual(
                normalized.overrideCount(forBundleID: "com.example.app"), 1,
                "迁移后覆盖数只剩真覆盖"
            )
            Harness.expectEqual(
                normalized.mapping(forBundleID: "com.example.app")[.confirm]?.keyCode, 0x24,
                "整理不改变生效行为（继承回默认）"
            )
            Harness.expectEqual(
                normalized.mapping(forBundleID: "com.example.app")[.up]?.keyCode, 0x74,
                "整理不改变生效行为（覆盖仍生效）"
            )
            Harness.expect(
                normalized.hasMapping(forBundleID: "com.example.app"),
                "应用配置仍在场景配置列表里"
            )

            // 死键照例被清掉。
            var dirty = table
            dirty.perApp["com.example.app"]?.shortcuts["不存在的键"] = Shortcut(keyCode: 0x24)
            Harness.expectEqual(
                dirty.normalized().perApp["com.example.app"]?.shortcuts["不存在的键"], nil,
                "已删除的按键名被清理"
            )
        }
    }

    /// `applying` 是预设套用的纯逻辑：覆盖模式整键替换，填空位模式跳过已有绑定
    /// （继承来的也算占用），并返回套用前的表供撤销。
    static func presetApplying() {
        Harness.suite("预设套用：填空位 / 覆盖 / 撤销快照") {
            // 覆盖模式：整键替换。
            var table = KeyMapTable()
            table.defaultMapping[.confirm] = Shortcut(keyCode: 0x4C)
            let previous = table.applying(.codingAssistant, forBundleID: nil, onlyFillEmpty: false)
            Harness.expectEqual(table.defaultMapping[.confirm]?.keyCode, 0x24, "覆盖模式替换已有绑定")
            Harness.expectEqual(previous?[.confirm]?.keyCode, 0x4C, "返回套用前的表供撤销")

            // 填空位：已有绑定不动，空位填上。
            var fill = KeyMapTable()
            fill.defaultMapping[.confirm] = Shortcut(keyCode: 0x4C)
            _ = fill.applying(.codingAssistant, forBundleID: nil, onlyFillEmpty: true)
            Harness.expectEqual(fill.defaultMapping[.confirm]?.keyCode, 0x4C, "填空位不动已有绑定")
            Harness.expectEqual(fill.defaultMapping[.back]?.keyCode, 0x35, "空位被填上")

            // 填空位在应用范围：继承来的绑定也算占用，不写进覆盖表。
            var inherited = KeyMapTable()
            inherited.defaultMapping[.confirm] = Shortcut(keyCode: 0x4C)
            let appPrevious = inherited.applying(.codingAssistant, forBundleID: "com.example.app", onlyFillEmpty: true)
            Harness.expectEqual(appPrevious, nil, "套用前该应用没有覆盖表（撤销 = 移除整个配置）")
            Harness.expectEqual(
                inherited.perApp["com.example.app"]?[.confirm], nil,
                "继承的绑定算占用，不形成覆盖"
            )
            Harness.expectEqual(
                inherited.perApp["com.example.app"]?[.back]?.keyCode, 0x35,
                "真空位写进覆盖表"
            )

            // 套用快捷键会顶掉同键的应用内动作（互斥）。
            var mutex = KeyMapTable()
            mutex.defaultMapping[action: .back] = .openModePicker
            _ = mutex.applying(.codingAssistant, forBundleID: nil, onlyFillEmpty: false)
            Harness.expectEqual(mutex.defaultMapping[action: .back], nil, "套用快捷键顶掉同键动作")
            Harness.expectEqual(mutex.defaultMapping[.back]?.keyCode, 0x35, "快捷键就位")
        }
    }

    static func codableRoundTrip() {
        Harness.suite("映射表 JSON 往返") {
            var table = KeyMapTable()
            table.defaultMapping[.back] = Shortcut(keyCode: 0x35)
            table.defaultMapping[.confirm] = Shortcut(
                keyCode: 0x24,
                flags: Shortcut.flags(from: [.command])
            )
            var appMapping = AppMapping()
            appMapping[.up] = Shortcut(keyCode: 0x74)
            table.setMapping(appMapping, forBundleID: "com.openai.codex")

            guard let encoded = try? JSONEncoder().encode(table),
                  let decoded = try? JSONDecoder().decode(KeyMapTable.self, from: encoded)
            else {
                Harness.expect(false, "映射表应能编码再解码")
                return
            }
            Harness.expectEqual(decoded, table, "往返后完全相等")
            Harness.expectEqual(
                decoded.mapping(forBundleID: "com.openai.codex")[.up]?.keyCode,
                0x74,
                "往返后应用专用表仍可解析"
            )
        }
    }

    static func presetShape() {
        Harness.suite("内置预设") {
            let preset = KeyMapPreset.codingAssistant
            Harness.expectEqual(preset.mapping[.confirm]?.keyCode, 0x24, "预设里确认键 = Return（发送）")
            Harness.expectEqual(preset.mapping[.back]?.keyCode, 0x35, "预设里返回键 = Esc")
            Harness.expectEqual(preset.mapping[.up]?.keyCode, 0x74, "预设里上键 = PageUp")
            Harness.expectEqual(preset.mapping[.down]?.keyCode, 0x79, "预设里下键 = PageDown")

            // 预设不得包含保留键——否则套用之后语音键就不能按住说话了。
            for button in preset.mapping.mappedButtons {
                Harness.expect(button.isMappable, "预设不含保留键（检查 \(button.displayName)）")
            }

            // 套用后仍是普通映射表，可继续编辑（"套用后可改"）。
            var table = KeyMapTable()
            table.setMapping(preset.mapping, forBundleID: "com.openai.codex")
            var edited = table.mapping(forBundleID: "com.openai.codex")
            edited[.confirm] = Shortcut(keyCode: 0x4C)
            table.setMapping(edited, forBundleID: "com.openai.codex")
            Harness.expectEqual(
                table.mapping(forBundleID: "com.openai.codex")[.confirm]?.keyCode,
                0x4C,
                "套用预设后可以改"
            )
        }
    }

    static func passthroughCoverage() {
        Harness.suite("转发覆盖度：每个可映射按键都有明确去处") {
            // 有原生等价的按键必须能查到转发键码，否则接管会让遥控器变难用。
            let withNative: [RemoteButton] = [.up, .down, .left, .right, .confirm, .home, .menu, .tv]
            for button in withNative {
                Harness.expect(
                    HIDKeyCode.keyCode(forUsage: button.rawValue) != nil,
                    "\(button.displayName) 有转发键码"
                )
            }

            Harness.expectEqual(
                HIDKeyCode.keyCode(forUsage: RemoteButton.confirm.rawValue), 0x24,
                "确认键转发为 kVK_Return"
            )
            Harness.expectEqual(
                HIDKeyCode.keyCode(forUsage: RemoteButton.up.rawValue), 0x7E,
                "上键转发为 kVK_UpArrow"
            )

            // 返回键没有原生等价键——这正是它按下去什么都不发生的原因。
            Harness.expectEqual(
                HIDKeyCode.keyCode(forUsage: RemoteButton.back.rawValue), nil,
                "返回键在 HID 键盘页里没有标准等价键"
            )

            Harness.expect(HIDKeyCode.isMediaKey(.volumeUp), "音量+ 走媒体键通道")
            Harness.expect(HIDKeyCode.isMediaKey(.volumeDown), "音量- 走媒体键通道")
            Harness.expect(!HIDKeyCode.isMediaKey(.confirm), "确认键不走媒体键通道")
        }
    }

    // MARK: - 路由规则

    static func routerVoiceAndPower() {
        Harness.suite("路由：语音键与电源键被吞掉") {
            let empty = AppMapping()
            for button in [RemoteButton.voice, .power] {
                for isDown in [true, false] {
                    Harness.expectEqual(
                        KeyRouter.disposition(
                            for: button, isDown: isDown, isRepeat: false,
                            mapping: empty, hasActiveItem: false
                        ),
                        .swallow,
                        "\(button.displayName)（\(isDown ? "按下" : "抬起")）被吞掉"
                    )
                }
            }
        }
    }

    static func routerBackPriority() {
        Harness.suite("路由：返回键在录音中优先取消，空闲时执行映射") {
            var mapping = AppMapping()
            mapping[.back] = Shortcut(keyCode: 0x23)   // 假定用户配成 ⌘P

            // 有活动项：取消优先，绝不合成用户的快捷键。
            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .back, isDown: true, isRepeat: false,
                    mapping: mapping, hasActiveItem: true
                ),
                .cancelNewestActive,
                "录音中按下返回键 → 取消"
            )
            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .back, isDown: false, isRepeat: false,
                    mapping: mapping, hasActiveItem: true
                ),
                .swallow,
                "录音中抬起返回键被吞（不往目标应用漏一个 Esc）"
            )
            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .back, isDown: true, isRepeat: true,
                    mapping: mapping, hasActiveItem: true
                ),
                .swallow,
                "录音中重复的返回键不再取消"
            )

            // 空闲：走映射。
            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .back, isDown: true, isRepeat: false,
                    mapping: mapping, hasActiveItem: false
                ),
                .synthesize(Shortcut(keyCode: 0x23)),
                "空闲时按下返回键 → 合成用户配的快捷键"
            )
        }
    }

    static func routerMappedButtons() {
        Harness.suite("路由：映射过的按键合成一次，抬起与重复被吞") {
            var mapping = AppMapping()
            mapping[.confirm] = Shortcut(keyCode: 0x24)

            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .confirm, isDown: true, isRepeat: false,
                    mapping: mapping, hasActiveItem: false
                ),
                .synthesize(Shortcut(keyCode: 0x24)),
                "按下合成"
            )
            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .confirm, isDown: false, isRepeat: false,
                    mapping: mapping, hasActiveItem: false
                ),
                .swallow,
                "抬起被吞（否则目标应用收到半截事件）"
            )
            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .confirm, isDown: true, isRepeat: true,
                    mapping: mapping, hasActiveItem: false
                ),
                .swallow,
                "重复被吞（按住不放不该让快捷键刷屏）"
            )
        }
    }

    static func routerUnmappedButtons() {
        Harness.suite("路由：未映射的按键原样转发") {
            let empty = AppMapping()

            // 有原生等价的：按下与抬起都转发，保持原生手感。
            for button in [RemoteButton.up, .down, .confirm, .home, .menu] {
                Harness.expectEqual(
                    KeyRouter.disposition(
                        for: button, isDown: true, isRepeat: false,
                        mapping: empty, hasActiveItem: false
                    ),
                    .passthrough,
                    "未映射的\(button.displayName)按下时转发"
                )
                Harness.expectEqual(
                    KeyRouter.disposition(
                        for: button, isDown: false, isRepeat: false,
                        mapping: empty, hasActiveItem: false
                    ),
                    .passthrough,
                    "未映射的\(button.displayName)抬起时也转发"
                )
            }

            // 重复照常转发：按住方向键本来就该连续移动。
            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .up, isDown: true, isRepeat: true,
                    mapping: empty, hasActiveItem: false
                ),
                .passthrough,
                "未映射的方向键重复时照样转发"
            )

            // 没有原生等价键的：返回给 Esc。
            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .back, isDown: true, isRepeat: false,
                    mapping: empty, hasActiveItem: false
                ),
                .synthesize(Shortcut(keyCode: 0x35)),
                "未映射的返回键空闲时发 Esc"
            )
            // 但抬起必须吞掉：Esc 的 down+up 在按下时已发完，
            // 抬起再合成一次就是按一次出两个 Esc。
            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .back, isDown: false, isRepeat: false,
                    mapping: empty, hasActiveItem: false
                ),
                .swallow,
                "未映射的返回键抬起被吞（不重复发 Esc）"
            )
            // TV 键在 HID 里就是 `~`（grave），有原生等价 → 照常转发，接管不改变它的手感。
            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .tv, isDown: true, isRepeat: false,
                    mapping: empty, hasActiveItem: false
                ),
                .passthrough,
                "未映射的 TV 键原样转发"
            )
            // 音量键走媒体通道，同样原样转发。
            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .volumeUp, isDown: true, isRepeat: false,
                    mapping: empty, hasActiveItem: false
                ),
                .passthrough,
                "未映射的音量键原样转发"
            )
            // 媒体键的抬起也要转：系统音量靠 up 事件收口。
            Harness.expectEqual(
                KeyRouter.disposition(
                    for: .volumeUp, isDown: false, isRepeat: false,
                    mapping: empty, hasActiveItem: false
                ),
                .passthrough,
                "未映射的音量键抬起也转发"
            )
        }
    }
}
