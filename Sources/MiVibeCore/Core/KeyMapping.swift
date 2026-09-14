import Foundation

/// 单个应用（或默认兜底）的按键映射表。
///
/// **未列出的按键 = 原样转发**。所以"没配过"和"配成什么都不做"是两件事，前者保留
/// 系统原生行为，后者由 `.none` 显式表达。
public struct AppMapping: Codable, Equatable, Sendable {
    /// 键是 `RemoteButton.id`（稳定的英文名），不是中文名，也不是 usage 数值。
    public var shortcuts: [String: Shortcut]

    public init(shortcuts: [String: Shortcut] = [:]) {
        self.shortcuts = shortcuts
    }

    /// 容错解码：缺 `shortcuts` 时退回空表，而不是让整个配置解码失败。
    /// 理由同 `Config` 头部的说明——**任何一个嵌套层级的解码失败，都会连带
    /// 抹掉用户已存的 API Key**。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shortcuts = try container.decodeIfPresent([String: Shortcut].self, forKey: .shortcuts) ?? [:]
    }

    private enum CodingKeys: String, CodingKey { case shortcuts }

    public subscript(button: RemoteButton) -> Shortcut? {
        get { shortcuts[button.id] }
        set {
            if let newValue {
                shortcuts[button.id] = newValue
            } else {
                shortcuts.removeValue(forKey: button.id)
            }
        }
    }

    /// 已配置的按键——设置页用它给遥控器图上的按键打高亮。
    public var mappedButtons: Set<RemoteButton> {
        Set(shortcuts.keys.compactMap(RemoteButton.from(id:)))
    }

    /// 丢弃已不存在的按键名（老配置里可能有被删掉的键）。
    public func pruned() -> AppMapping {
        AppMapping(shortcuts: shortcuts.filter { RemoteButton.from(id: $0.key) != nil })
    }
}

/// 每应用映射表 + 默认兜底。
///
/// 解析规则：**应用专用表整体替换默认表，不做字段级合并。**
///
/// 合并听起来更友好，但会让"我在默认表里配了上键，为什么在 X 应用里不生效"变成
/// 一个无法回答的问题。设置页在用户第一次为某个应用改动时，把默认表克隆进去，
/// 效果一样，行为却完全可预期。
public struct KeyMapTable: Codable, Equatable, Sendable {
    public var defaultMapping: AppMapping
    /// 键是 bundle identifier。
    public var perApp: [String: AppMapping]

    public init(defaultMapping: AppMapping = AppMapping(), perApp: [String: AppMapping] = [:]) {
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

    /// 查某个应用的映射。`bundleID` 为 nil（拿不到前台应用）时走默认表。
    public func mapping(forBundleID bundleID: String?) -> AppMapping {
        guard let bundleID, let app = perApp[bundleID] else { return defaultMapping }
        return app
    }

    /// 编辑入口：设置页改某个作用范围的映射时走这里。
    ///
    /// 应用专用表**整体替换**默认表（见类型头注释），所以首次编辑某应用时先把
    /// 默认表克隆进去再改——"继承"发生在编辑这一刻，之后两张表互不相干。
    /// `bundleID` 为 nil 时直接改默认表。
    public mutating func updateMapping(forBundleID bundleID: String?, _ transform: (inout AppMapping) -> Void) {
        if let bundleID {
            var mapping = perApp[bundleID] ?? defaultMapping
            transform(&mapping)
            perApp[bundleID] = mapping
        } else {
            transform(&defaultMapping)
        }
    }

    public mutating func setMapping(_ mapping: AppMapping, forBundleID bundleID: String) {
        perApp[bundleID] = mapping
    }

    public mutating func removeMapping(forBundleID bundleID: String) {
        perApp.removeValue(forKey: bundleID)
    }

    public func hasMapping(forBundleID bundleID: String) -> Bool {
        perApp[bundleID] != nil
    }

    /// 丢弃已不存在的按键名。
    public func pruned() -> KeyMapTable {
        KeyMapTable(
            defaultMapping: defaultMapping.pruned(),
            perApp: perApp.mapValues { $0.pruned() }
        )
    }
}
