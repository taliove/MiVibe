import Foundation

/// 待处理内容的一次性留存（退出保留 / 崩溃兜底）。
///
/// **明文存储，文件权限 0600。** 加密的是用户自己刚说过的话，不是别人的机密；
/// 挡同机其他用户，0600 就够了（用户明确否决了钥匙串方案）。
///
/// 生命周期是"一次性续命"：启动时读入队列，读完即删，不形成长期历史（SPEC §6）。
public struct PendingItem: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// 有识别文字，但没能写入目标输入框。
        case text
        /// 转写失败的录音——只有音频，没有文字。
        case failedAudio
    }

    public var kind: Kind
    public var text: String?
    /// 16 kHz 单声道 s16le 的原始 PCM，base64 存在 JSON 里（约 32 kB/秒）。
    public var pcm: Data?
    public var savedAt: Date

    public init(kind: Kind, text: String? = nil, pcm: Data? = nil, savedAt: Date = Date()) {
        self.kind = kind
        self.text = text
        self.pcm = pcm
        self.savedAt = savedAt
    }
}

public enum PendingStore {
    public static let fileName = "pending.json"

    /// 音频总量上限。超过就把音频丢掉、只留文字，并在退出对话框里说明。
    /// 6 秒语音约 190 kB，这个上限足够放下多段录音，又不至于让 JSON 无限长大。
    public static let audioBudgetBytes = 4 * 1024 * 1024

    public static func fileURL(in directory: URL = Config.configDir) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// 读取待处理内容。文件不存在或解不开都返回空——这里**不能**像 `Config` 那样
    /// 静默降级成"覆盖"，所以调用方读完必须显式 `clear()`。
    public static func load(in directory: URL = Config.configDir) -> [PendingItem] {
        let url = fileURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Foundation.Data(contentsOf: url)
            return try JSONDecoder().decode([PendingItem].self, from: data)
        } catch {
            print("待处理内容读取失败: \(error)")
            return []
        }
    }

    public static func save(_ items: [PendingItem], in directory: URL = Config.configDir) throws {
        let url = fileURL(in: directory)
        if items.isEmpty {
            clear(in: directory)
            return
        }
        var budgeted = items
        if totalAudioBytes(budgeted) > audioBudgetBytes {
            for index in budgeted.indices { budgeted[index].pcm = nil }
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(budgeted)
        try data.write(to: url, options: .atomic)
        try Config.restrictToOwner(url)
    }

    public static func clear(in directory: URL = Config.configDir) {
        try? FileManager.default.removeItem(at: fileURL(in: directory))
    }

    public static func totalAudioBytes(_ items: [PendingItem]) -> Int {
        items.reduce(0) { $0 + ($1.pcm?.count ?? 0) }
    }
}
