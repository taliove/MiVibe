import Foundation

/// 本地配置文件：不用钥匙串，直接存 JSON（明文，权限 0600）。
///
/// ## 加字段的规矩（重要）
///
/// **新增的持久化字段一律必须是 `Optional`**，嵌套层级里也一样。
///
/// 原因：`load()` 会吞掉任何解码错误并返回默认值。合成的 `Codable` 对 `Optional`
/// 属性用 `decodeIfPresent`（缺键 → nil，安全），对非 `Optional` 属性用 `decode`
/// （缺键 → **整个结构解码失败**）。而失败一旦发生，`load()` 返回的是空配置——
/// **连同已经存好的 API Key 一起被抹掉**。下一次任何 `save()` 就会把这个空配置
/// 写回磁盘，用户的 Key 就真的没了。
///
/// 所以：默认值由 `effective*` 这类访问器提供，不靠字段本身的非 Optional 声明。
public enum Config {
    public static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/mivibe")
    public static let configFile = configDir.appendingPathComponent("config.json")

    public struct Data: Codable {
        public var doubaoAPIKey: String?
        /// 既有字段，历史文件里一直有，保持非 Optional 安全。
        public var enableNonstream: Bool

        // ↓ 之后新增的字段一律 Optional，理由见类型头注释。
        /// 是否接管遥控器的 HID 按键。见按键映射的设计。
        public var keyTakeover: Bool?
        /// 每应用按键映射表。
        public var keyMap: KeyMapTable?
        /// 识别引擎选择（ASREngine rawValue）。nil = 豆包（老用户升级后行为不变）。
        public var asrProvider: String?
        /// 本地识别当前选用的模型 id（须已下载）。
        public var localModel: String?
        /// 改写配置（模式 + LLM 服务商）。
        public var rewrite: RewriteConfig?
        /// 关键词纠正对照表（识别与改写共用）。
        public var keywords: [KeywordEntry]?
        /// 品牌主题（ThemeID rawValue）。nil = 潮汐青。
        public var theme: String?
        /// 外观模式（AppearanceMode rawValue）。nil = 跟随系统。
        public var appearance: String?
        /// 外观页是否已被打开过（nil/true 决定侧栏「新」胶囊是否显示）。
        public var appearancePaneSeen: Bool?

        public init(
            doubaoAPIKey: String? = nil,
            enableNonstream: Bool = true,
            keyTakeover: Bool? = nil,
            keyMap: KeyMapTable? = nil,
            asrProvider: String? = nil,
            localModel: String? = nil,
            rewrite: RewriteConfig? = nil,
            keywords: [KeywordEntry]? = nil,
            theme: String? = nil,
            appearance: String? = nil,
            appearancePaneSeen: Bool? = nil
        ) {
            self.doubaoAPIKey = doubaoAPIKey
            self.enableNonstream = enableNonstream
            self.keyTakeover = keyTakeover
            self.keyMap = keyMap
            self.asrProvider = asrProvider
            self.localModel = localModel
            self.rewrite = rewrite
            self.keywords = keywords
            self.theme = theme
            self.appearance = appearance
            self.appearancePaneSeen = appearancePaneSeen
        }

        public var effectiveKeyTakeover: Bool { keyTakeover ?? true }
        public var effectiveKeyMap: KeyMapTable { keyMap ?? KeyMapTable() }
        public var effectiveASRProvider: ASREngine { ASREngine(rawValue: asrProvider ?? "") ?? .doubao }
        public var effectiveRewrite: RewriteConfig { rewrite ?? RewriteConfig() }
        public var effectiveKeywords: [KeywordEntry] { keywords ?? [] }
        /// 未知字符串回落默认主题，绝不让一个坏值毁掉整份配置。
        public var effectiveTheme: ThemeID { ThemeID(rawValue: theme ?? "") ?? .tide }
        public var effectiveAppearance: AppearanceMode { AppearanceMode(rawValue: appearance ?? "") ?? .system }
    }

    /// 读取配置（不存在时返回默认值）。
    public static func load() -> Data {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            return Data()
        }
        do {
            let json = try Foundation.Data(contentsOf: configFile)
            return try JSONDecoder().decode(Data.self, from: json)
        } catch {
            // 注意：这里返回默认值意味着丢弃了文件里的一切。别让不该失败的解码失败——
            // 新增字段务必是 Optional（见类型头注释）。
            print("配置文件读取失败: \(error)")
            return Data()
        }
    }

    /// 保存配置。文件权限 0600——里面有明文 API Key，同机其他用户不该读得到。
    public static func save(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: configDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let json = try JSONEncoder().encode(data)
        try json.write(to: configFile, options: .atomic)
        try restrictToOwner(configFile)
        // 目录必须是 0700 而不是 0600：目录的执行位才是"可进入"位，
        // 0600 的目录连所有者都进不去，里面的 config.json / signing-password 全部失联。
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: configDir.path)
    }

    /// 把**文件**权限收紧到「仅所有者」（0600）。`Data.write(.atomic)` 落盘用的是进程
    /// umask，默认会得到 0644——对明文凭据来说太宽了。目录不要走这里，见 `save()`。
    public static func restrictToOwner(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// 检查 API Key 是否已配置。
    public static var isConfigured: Bool {
        guard let key = load().doubaoAPIKey, !key.isEmpty else { return false }
        return true
    }
}
