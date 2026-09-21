import CWhisper
import Foundation

/// 本地识别引擎：whisper.cpp。模型文件（ggml）由 ModelStore 下载管理，
/// 本类只负责加载与转写。离线运行，失败绝不回退云端（隐私语义，见 CONTEXT.md）。
///
/// 输入约定与豆包链路一致：16kHz mono pcm_s16le（遥控器 ADPCM 解码后的格式）。
/// 线程安全由一把锁保证：锁同时串行化转写调用（一次一个，正是我们想要的）。
public final class LocalWhisperProvider: ASRProvider, @unchecked Sendable {
    public enum WhisperError: Error, LocalizedError {
        case modelMissing(String)
        case initFailed(String)
        case transcribeFailed(Int32)

        public var errorDescription: String? {
            switch self {
            case .modelMissing(let path):
                return "模型文件不存在：\(path)。请在设置中下载模型。"
            case .initFailed(let path):
                return "模型加载失败：\(path)。文件可能损坏，请删除后重新下载。"
            case .transcribeFailed(let code):
                return "本地识别失败（错误码 \(code)）"
            }
        }
    }

    private let modelPath: String
    private let lock = NSLock()
    private var ctx: OpaquePointer?

    /// 词汇提示（whisper initial_prompt）：关键词纠正表的正确写法词表，
    /// 降低专有名词第一遍误听率。转写参数构建时取用。
    private var vocabularyHint: String?

    public init(modelURL: URL) {
        self.modelPath = modelURL.path
    }

    /// 更新词汇提示（关键词表变化时调用）。
    public func setVocabularyHint(_ hint: String?) {
        lock.lock()
        vocabularyHint = hint
        lock.unlock()
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }

    /// 懒加载模型（首次转写时）。大模型加载要数秒，懒加载让引擎切换不卡启动。
    /// 调用方须已持锁。
    private func ensureContextLocked() throws -> OpaquePointer {
        if let ctx { return ctx }
        guard FileManager.default.isReadableFile(atPath: modelPath) else {
            throw WhisperError.modelMissing(modelPath)
        }
        var params = whisper_context_default_params()
        params.use_gpu = true   // Metal；不可用时 ggml 自动回落 CPU
        guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperError.initFailed(modelPath)
        }
        self.ctx = ctx
        Log.chain.notice("whisper context ready: \(self.modelPath, privacy: .public)")
        return ctx
    }

    public func transcribe(pcm: Data) async throws -> String {
        // whisper_full 是阻塞式 C 调用（小模型几百毫秒，大模型数秒），
        // 放到后台线程，别占着协作线程池。
        try await Task.detached(priority: .userInitiated) { [self] in
            try transcribeBlocking(pcm: pcm)
        }.value
    }

    private func transcribeBlocking(pcm: Data) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        let ctx = try ensureContextLocked()
        let hint = vocabularyHint

        // s16le → float32 [-1, 1]
        let sampleCount = pcm.count / 2
        var samples = [Float](repeating: 0, count: sampleCount)
        pcm.withUnsafeBytes { raw in
            let ints = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples[i] = Float(ints[i]) / 32768.0
            }
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true          // 单段口述，不让前一段文本污染后一段
        params.single_segment = false
        params.suppress_nst = true        // 抑制 whisper 著名的幻听（"谢谢观看"之类）
        params.language = UnsafePointer(strdup("auto"))
        defer { free(UnsafeMutablePointer(mutating: params.language)) }
        if let hint {
            params.initial_prompt = UnsafePointer(strdup(hint))
            defer { free(UnsafeMutablePointer(mutating: params.initial_prompt)) }
        }
        params.n_threads = Int32(min(4, ProcessInfo.processInfo.processorCount))

        let rc = samples.withUnsafeMutableBufferPointer { buf in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        guard rc == 0 else { throw WhisperError.transcribeFailed(rc) }

        var text = ""
        let n = whisper_full_n_segments(ctx)
        for i in 0..<n {
            if let seg = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: seg)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
