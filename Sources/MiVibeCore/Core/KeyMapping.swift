import Foundation

/// 某键在某作用范围里的绑定来源（设置页标记用）。
///
/// 默认作用范围里只可能出现 `own` / `unbound`；应用作用范围里
/// `inherited` = 跟随默认表，`overridden` = 该应用的覆盖表里有自己的绑定。
public enum KeyBindingSource: Equatable, Sendable {
    case unbound, own, inherited, overridden
}

/// 单个应用（或默认兜底）的按键映射表。
///
/// **未列出的按键 = 原样转发**。所以「没配过」就是保留系统原生行为；
/// 一个键的状态只有「配了快捷键」「配了应用内动作」「未配置」三种，互相独立，
/// 不存在第四种「显式什么都不做」的取值（详见 `KeyMapTable` 头部的取舍说明）。
public struct AppMapping: Codable, Equatable, Sendable {
    /// 键是 `RemoteButton.id`（稳定的英文名），不是中文名，也不是 usage 数值。
    public var shortcuts: [String: Shortcut]
    /// 应用内动作映射（与快捷键并列；同一按键同时存在时动作优先）。
    /// Optional 序列化语义由自定义解码保证：老配置没有这层，缺省即空表。
    public var actions: [String: RemoteAction]

    public init(shortcuts: [String: Shortcut] = [:], actions: [String: RemoteAction] = [:]) {
        self.shortcuts = shortcuts
        self.actions = actions
    }

    /// 容错解码：缺 `shortcuts`/`actions` 时退回空表，而不是让整个配置解码失败。
    /// 理由同 `Config` 头部的说明——**任何一个嵌套层级的解码失败，都会连带
    /// 抹掉用户已存的 API Key**。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shortcuts = try container.decodeIfPresent([String: Shortcut].self, forKey: .shortcuts) ?? [:]
        actions = try container.decodeIfPresent([String: RemoteAction].self, forKey: .actions) ?? [:]
    }

    private enum CodingKeys: String, CodingKey { case shortcuts, actions }

    public subscript(button: RemoteButton) -> Shortcut? {
        get { shortcuts[button.id] }
        set {
            if let newValue {
                shortcuts[button.id] = newValue
                actions.removeValue(forKey: button.id)   // 快捷键与动作互斥，后者让位
            } else {
                shortcuts.removeValue(forKey: button.id)
            }
        }
    }

    /// 应用内动作读写口；设置动作时清掉同键快捷键（互斥）。
    public subscript(action button: RemoteButton) -> RemoteAction? {
        get { actions[button.id] }
        set {
            if let newValue {
                actions[button.id] = newValue
                shortcuts.removeValue(forKey: button.id)
            } else {
                actions.removeValue(forKey: button.id)
            }
        }
    }

    /// 已配置的按键——设置页用它给遥控器图上的按键打高亮。
    public var mappedButtons: Set<RemoteButton> {
        Set(shortcuts.keys.compactMap(RemoteButton.from(id:)))
            .union(actions.keys.compactMap(RemoteButton.from(id:)))
    }

    /// 丢弃已不存在的按键名（老配置里可能有被删掉的键）。
    public func pruned() -> AppMapping {
        AppMapping(
            shortcuts: shortcuts.filter { RemoteButton.from(id: $0.key) != nil },
            actions: actions.filter { RemoteButton.from(id: $0.key) != nil }
        )
    }
}

/// 每应用覆盖表 + 默认兜底。
///
/// 解析规则：**应用专用表只记录与默认表不同的键（覆盖），其余按键逐键继承默认表。**
///
/// 历史上曾是「专用表整体替换默认表」：首次编辑把默认表克隆进去，之后互不相干。
/// 实测下来它的困惑更大——用户改了默认表，已配过的应用却不跟着变，界面上也看不出
/// 为什么。继承模型下「为什么这个键在 X 应用里不一样」有确定答案：它被覆盖了；
/// 按键映射页的作用范围栏直接显示每个应用覆盖了几个键。代价是
/// 「把默认绑定在某应用里显式清空、恢复系统原生」表达不了（清除覆盖 = 回到继承），
/// 与常见 overlay 模型（Karabiner、MiRemote）一致，接受这个取舍。
///
/// 老配置迁移：旧版存的是整表克隆，`normalized()` 在启动时把与默认表一致的条目
/// 收回继承（生效行为不变），真改过的保留为覆盖。
public struct KeyMapTable: Codable, Equatable, Sendable {
    public var defaultMapping: AppMapping
    /// 键是 bundle identifier；值是**覆盖表**（只存与默认表不同的键）。
    public var perApp: [String: AppMapping]

    public init(defaultMapping: AppMapping = AppMapping(actions: ["menu": .openModePicker]), perApp: [String: AppMapping] = [:]) {
        self.defaultMapping = defaultMapping
        self.perApp = perApp
    }

    /// 容错解码：任何字段缺失都退回默认，不让整个配置解码失败。理由同 `AppMapping`。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultMapping = try container.decodeIfPresent(AppMapping.self, forKey: .defaultMapping) ?? AppMapping()
        perApp = try container.decodeIfPresent([String: AppMapping].self, forKey: .perApp) ?? [:]
    }

    private enum CodingKeys: String, CodingKey { case defaultMapping, perApp }

    /// 查某个应用的生效映射：默认表打底，覆盖表逐键压上去（快捷键与动作保持互斥）。
    /// `bundleID` 为 nil（拿不到前台应用）时走默认表。
    public func mapping(forBundleID bundleID: String?) -> AppMapping {
        guard let bundleID, let overrides = perApp[bundleID] else { return defaultMapping }
        var merged = defaultMapping
        for (key, value) in overrides.shortcuts {
            merged.shortcuts[key] = value
            merged.actions.removeValue(forKey: key)
        }
        for (key, value) in overrides.actions {
            merged.actions[key] = value
            merged.shortcuts.removeValue(forKey: key)
        }
        return merged
    }

    /// 查某键在某作用范围里的绑定来源。
    ///
    /// `bundleID` 为 nil（编辑默认映射）：默认表有绑定（快捷键或动作）为 `own`，
    /// 否则 `unbound`。`bundleID` 为某应用：该应用覆盖表里有该键为 `overridden`；
    /// 否则默认表有绑定为 `inherited`，都没有为 `unbound`。覆盖表不存在时等价于
    /// 空覆盖表——全部继承或完全未绑定。
    public func bindingSource(of button: RemoteButton, forBundleID bundleID: String?) -> KeyBindingSource {
        let hasDefault = defaultMapping[button] != nil || defaultMapping[action: button] != nil
        guard let bundleID else { return hasDefault ? .own : .unbound }
        let overrides = perApp[bundleID] ?? AppMapping()
        if overrides[button] != nil || overrides[action: button] != nil { return .overridden }
        return hasDefault ? .inherited : .unbound
    }

    /// 编辑入口：设置页改某个作用范围的映射时走这里。
    /// 应用范围只写**覆盖**：改动直接落进该应用的覆盖表，不克隆默认表；写入后把
    /// 与默认表一致的条目收回继承（覆盖数因此永远等于"真的不一样"的键数）。
    /// 清除一个键 = 删除覆盖 → 回到继承。`bundleID` 为 nil 时直接改默认表。
    public mutating func updateMapping(forBundleID bundleID: String?, _ transform: (inout AppMapping) -> Void) {
        if let bundleID {
            var overrides = perApp[bundleID] ?? AppMapping()
            transform(&overrides)
            perApp[bundleID] = overrides
            collapseRedundantOverrides(forBundleID: bundleID)
        } else {
            transform(&defaultMapping)
        }
    }

    public mutating func setMapping(_ mapping: AppMapping, forBundleID bundleID: String) {
        perApp[bundleID] = mapping
        collapseRedundantOverrides(forBundleID: bundleID)
    }

    public mutating func removeMapping(forBundleID bundleID: String) {
        perApp.removeValue(forKey: bundleID)
    }

    public func hasMapping(forBundleID bundleID: String) -> Bool {
        perApp[bundleID] != nil
    }

    /// 该应用真覆盖的键数（设置页作用范围栏的「覆盖 N 键」）。
    public func overrideCount(forBundleID bundleID: String) -> Int {
        guard let overrides = perApp[bundleID] else { return 0 }
        return Set(overrides.shortcuts.keys).union(overrides.actions.keys).count
    }

    /// 把与默认表一致的覆盖条目收回继承。逐键比对，不影响生效行为。
    public mutating func collapseRedundantOverrides(forBundleID bundleID: String) {
        guard var overrides = perApp[bundleID] else { return }
        overrides.shortcuts = overrides.shortcuts.filter { defaultMapping.shortcuts[$0.key] != $0.value }
        overrides.actions = overrides.actions.filter { defaultMapping.actions[$0.key] != $0.value }
        perApp[bundleID] = overrides
    }

    /// 丢弃已不存在的按键名。
    public func pruned() -> KeyMapTable {
        KeyMapTable(
            defaultMapping: defaultMapping.pruned(),
            perApp: perApp.mapValues { $0.pruned() }
        )
    }

    /// 启动整理：清死键 + 把旧版整表克隆里与默认表一致的条目收回继承（配置迁移，
    /// 生效行为不变）。每次启动都跑一遍是幂等的。
    public func normalized() -> KeyMapTable {
        var table = pruned()
        for bundleID in table.perApp.keys {
            table.collapseRedundantOverrides(forBundleID: bundleID)
        }
        return table
    }

    /// 套用预设到指定作用范围，返回套用前该范围的原始表（供撤销；应用范围没有
    /// 覆盖表时返回 nil，撤销即移除整个配置）。
    ///
    /// `onlyFillEmpty` = true 时只写**生效表**里没有绑定的键——继承来的绑定也算
    /// 占用，不会被预设顶掉。
    @discardableResult
    public mutating func applying(_ preset: KeyMapPreset, forBundleID bundleID: String?, onlyFillEmpty: Bool) -> AppMapping? {
        let previous = bundleID.map { perApp[$0] } ?? defaultMapping
        let effective = mapping(forBundleID: bundleID)
        updateMapping(forBundleID: bundleID) { mapping in
            for (key, value) in preset.shortcuts {
                if onlyFillEmpty, let button = RemoteButton.from(id: key),
                   effective[button] != nil || effective[action: button] != nil { continue }
                mapping.shortcuts[key] = value
                mapping.actions.removeValue(forKey: key)   // 快捷键与动作互斥
            }
        }
        return previous
    }
}
