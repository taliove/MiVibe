import Foundation

/// 识别引擎：把一段录音（16kHz mono pcm_s16le）变成文字的服务提供方。
///
/// 实现方：豆包语音（云端）与本地识别（whisper.cpp）。任一时刻只有一个生效，
/// 由 Coordinator 按配置选择。协议签名刻意保持与既有豆包调用一致的最小集——
/// 引擎特有选项（如二遍识别）由实现方各自持有，不进协议。
public protocol ASRProvider: Sendable {
    func transcribe(pcm: Data) async throws -> String
}

/// 引擎标识，持久化到 config.json 的 `asrProvider` 字段。
public enum ASREngine: String, Codable, Sendable, CaseIterable {
    case doubao
    case local

    public var displayName: String {
        switch self {
        case .doubao: return "豆包语音（云端）"
        case .local: return "本地识别（离线）"
        }
    }
}

extension DoubaoClient: ASRProvider {
    /// 协议入口：选项由调用方预先配置（`providerOptions`）。
    public func transcribe(pcm: Data) async throws -> String {
        try await transcribe(pcm: pcm, options: providerOptions)
    }
}
