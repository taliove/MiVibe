import Foundation

/// 录音分诊：松手后先判断这段录音值不值得送去转写（纯逻辑，可脱离硬件测试）。
///
/// 误触语音键（一按即松）或按住没说话，都会产生一段"录音"。送去转写的代价是：
/// 浮条停在「正在转写」好几秒（本地大模型首次还要加载），结果为空或是幻听，
/// 空结果还会落成一条占位的待处理项。所以在转写前就把它们拦下，直接丢弃。
///
/// 门限刻意保守——宁可放一段静音进转写，也不能吞掉用户真说了的话：
/// - 时长不足 `minimumDuration` 视为误触；
/// - 任何一个 30ms 窗口的 RMS 达到 `speechFloorDB` 就算有声（不看平均值，
///   否则大段静音里的一句短话会被平均掉）。
public enum RecordingTriage {
    public enum Verdict: Equatable, Sendable {
        /// 值得送去转写。
        case speech
        /// 误触或静音：直接丢弃，不进转写。
        case empty
    }

    /// 16 kHz 单声道 s16le。
    public static let bytesPerSecond = 32_000
    /// 短于此时长视为误触（秒）。
    public static let minimumDuration = 0.3
    /// 有声门限（dBFS）。正常说话的窗口峰值远高于 -30；-45 以下只可能是底噪。
    public static let speechFloorDB = -45.0
    /// 分析窗口：480 样本 = 30ms。
    private static let windowSamples = 480

    public static func classify(pcm: Data) -> Verdict {
        let duration = Double(pcm.count) / Double(bytesPerSecond)
        guard duration >= minimumDuration else { return .empty }
        return peakWindowDB(pcm: pcm) >= speechFloorDB ? .speech : .empty
    }

    /// 最响 30ms 窗口的 RMS（dBFS）。全静音返回 -∞。日志用它校准门限。
    public static func peakWindowDB(pcm: Data) -> Double {
        let sampleCount = pcm.count / 2
        var peak = 0.0
        var sum = 0.0
        var inWindow = 0
        var index = pcm.startIndex
        for _ in 0..<sampleCount {
            let sample = Int16(bitPattern: UInt16(pcm[index + 1]) << 8 | UInt16(pcm[index]))
            let value = Double(sample) / 32768.0
            sum += value * value
            inWindow += 1
            index += 2
            if inWindow == windowSamples {
                peak = max(peak, (sum / Double(inWindow)).squareRoot())
                sum = 0
                inWindow = 0
            }
        }
        if inWindow > 0 { peak = max(peak, (sum / Double(inWindow)).squareRoot()) }
        return peak > 0 ? 20 * log10(peak) : -.infinity
    }

    /// 转写结果是否等于没说：空白或只有标点（whisper 对静音常输出一个句号）。
    public static func isEmptyTranscript(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
        }
    }

    /// 转写整体超时（秒）：30 秒起步，每秒录音加 1.5 秒，封顶 180 秒。
    /// 豆包只有逐帧 20 秒超时，本地引擎没有超时——兜底防止浮条永远停在「正在转写」。
    public static func transcribeTimeout(pcmBytes: Int) -> TimeInterval {
        let seconds = Double(pcmBytes) / Double(bytesPerSecond)
        return min(180, 30 + 1.5 * seconds)
    }
}
