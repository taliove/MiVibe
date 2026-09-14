import Foundation

/// 豆包流式 ASR 客户端（SPEC §4）。
///
/// 认证与参数全部按实测合同：三头认证 + 2.0 小时版资源 + 16 kHz mono pcm_s16le
/// 200ms 分包。二遍识别默认开（尾延迟 0.767s 换更准分句）。
public actor DoubaoClient {
    public static let endpoint = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!
    public static let resourceID = "volc.seedasr.sauc.duration"   // 2.0 小时版
    public static let segmentBytes = 6400                          // 200ms @ 16k/16bit/mono

    public enum ClientError: Error, LocalizedError {
        case noAPIKey
        case connectionFailed(String)
        case serverError(code: Int32?, message: String?)
        case noResult

        public var errorDescription: String? {
            switch self {
            case .noAPIKey: return "尚未配置 API Key"
            case .connectionFailed(let detail): return "连接失败：\(detail)"
            case .serverError(let code, let message):
                return "服务返回错误\(code.map { "（\($0)）" } ?? "")：\(message ?? "未知")"
            case .noResult: return "没有识别结果"
            }
        }
    }

    public struct Options: Sendable {
        public init() {}
        public var enableNonstream = true   // 二遍识别，SPEC §4 默认开
        public var enablePunctuation = true
        public var enableITN = true
        public var enableDDC = true
    }

    public init() {}

    private var task: URLSessionWebSocketTask?
    private var sequence: Int32 = 1
    /// 诊断用：打印每个下行帧的帧头。
    public var verbose = false

    public func setVerbose(_ on: Bool) { verbose = on }

    /// 一次性转写：给定完整 PCM，返回最终文本。
    ///
    /// 松手后才调用（按住说话场景不需要边说边显示中间结果——中间结果只用于状态提示，
    /// 而输入只发生一次）。
    public func transcribe(pcm: Data, options: Options = Options()) async throws -> String {
        let key = try apiKey()
        try await open(apiKey: key)
        defer { close() }

        try await sendFullRequest(options: options)
        try await sendAudio(pcm: pcm)
        return try await receiveFinalText()
    }

    // MARK: - 连接

    private func apiKey() throws -> String {
        guard let key = Config.load().doubaoAPIKey, !key.isEmpty else {
            throw ClientError.noAPIKey
        }
        return key
    }

    private func open(apiKey: String) async throws {
        var request = URLRequest(url: Self.endpoint)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(Self.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")

        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: request)
        socket.resume()
        task = socket
        sequence = 1
    }

    private func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // MARK: - 上行

    private func sendFullRequest(options: Options) async throws {
        let payload: [String: Any] = [
            "user": ["uid": "mivibe"],
            "audio": [
                "format": "pcm", "codec": "raw",
                "rate": 16000, "bits": 16, "channel": 1,
            ],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": options.enableITN,
                "enable_punc": options.enablePunctuation,
                "enable_ddc": options.enableDDC,
                "show_utterances": true,
                "result_type": "full",
                "enable_nonstream": options.enableNonstream,
            ],
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let frame = try DoubaoFrame.fullClientRequest(payload: json, sequence: sequence)
        sequence += 1
        try await send(frame)
    }

    private func sendAudio(pcm: Data) async throws {
        // 注意：传进来的 Data 可能是切片（例如去掉 WAV 头后的 dropFirst 结果），
        // 其索引**不从 0 开始**。必须按 startIndex 定位，不能假设零基下标。
        var offset = pcm.startIndex
        while offset < pcm.endIndex {
            let end = min(offset + Self.segmentBytes, pcm.endIndex)
            let chunk = pcm[offset..<end]
            let frame = try DoubaoFrame.audioPacket(pcm: Data(chunk), sequence: sequence, isLast: false)
            sequence += 1
            try await send(frame)
            offset = end
        }
        // 末包：空 payload + flags 0b0011 + 负 sequence
        let last = try DoubaoFrame.audioPacket(pcm: Data(), sequence: sequence, isLast: true)
        try await send(last)
    }

    private func send(_ frame: Data) async throws {
        guard let task else { throw ClientError.connectionFailed("连接已关闭") }
        do {
            try await task.send(.data(frame))
        } catch {
            throw ClientError.connectionFailed(error.localizedDescription)
        }
    }

    // MARK: - 下行

    /// 收到 flags 0x02（末包）为止，返回最后一次全量文本。
    private func receiveFinalText() async throws -> String {
        guard let task else { throw ClientError.connectionFailed("连接已关闭") }
        var latest: String?

        while true {
            // 超时必须能打断**挂起中**的 receive()，否则等不到帧就永远卡住，
            // 所以用竞速任务，而不是循环顶部检查时间。
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
                    group.addTask { try await task.receive() }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 20_000_000_000)
                        throw ClientError.connectionFailed("等待下一帧超时（20s）")
                    }
                    let first = try await group.next()!
                    group.cancelAll()
                    return first
                }
            } catch let error as ClientError {
                throw error
            } catch {
                throw ClientError.connectionFailed(error.localizedDescription)
            }
            guard case .data(let raw) = message else { continue }

            let response = try DoubaoFrame.parse(raw)
            if verbose {
                let head = raw.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
                print("[帧] \(head) type=\(response.messageType.rawValue) flags=\(response.flags.rawValue) last=\(response.isLastPackage) payload=\(response.payload?.count ?? 0)B")
            }

            if response.messageType == .serverError {
                throw ClientError.serverError(
                    code: response.errorCode,
                    message: response.payload.flatMap { String(data: $0, encoding: .utf8) }
                )
            }

            if let text = Self.extractText(response.payload) { latest = text }
            if response.isLastPackage { break }   // 只看 flags 0x02
        }

        guard let latest, !latest.isEmpty else { throw ClientError.noResult }
        return latest
    }

    /// `result` 是 object（实测；文档写的 list 不实）。
    public static func extractText(_ payload: Data?) -> String? {
        guard let payload,
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let text = result["text"] as? String,
              !text.isEmpty
        else { return nil }
        return text
    }
}
