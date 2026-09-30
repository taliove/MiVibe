import Foundation
import MiVibeCore

/// 录音分诊与转写超时的验收。
///
/// 真机日志的两次卡死都从这里开始：一次 0 字节、一次 75ms 的误触录音被送去转写，
/// 空结果最终落成一条无法恢复的空「待处理」，把队列（容量 2）占住。
enum RecordingTriageTests {
    static func run() {
        triage()
        emptyTranscript()
        timeout()
    }

    /// 16 kHz 单声道 s16le 方波。
    private static func pcm(amplitude: Int16, seconds: Double) -> Data {
        let samples = Int(seconds * 16_000)
        var data = Data(capacity: samples * 2)
        for index in 0..<samples {
            let bits = UInt16(bitPattern: index % 2 == 0 ? amplitude : -amplitude)
            data.append(UInt8(bits & 0xFF))
            data.append(UInt8(bits >> 8))
        }
        return data
    }

    private static func triage() {
        Harness.suite("RecordingTriage 录音分诊") {
            Harness.expectEqual(RecordingTriage.classify(pcm: Data()), .empty, "0 字节 → 空")
            Harness.expectEqual(RecordingTriage.classify(pcm: pcm(amplitude: 8_000, seconds: 0.075)), .empty,
                                "75ms 误触（真机日志 2400B）→ 空")
            Harness.expectEqual(RecordingTriage.classify(pcm: pcm(amplitude: 0, seconds: 2)), .empty,
                                "按住 2 秒不说话（全静音）→ 空")
            Harness.expectEqual(RecordingTriage.classify(pcm: pcm(amplitude: 60, seconds: 3)), .empty,
                                "底噪级（约 -55 dBFS）→ 空")
            Harness.expectEqual(RecordingTriage.classify(pcm: pcm(amplitude: 3_000, seconds: 1)), .speech,
                                "正常音量 1 秒 → 送转写")

            // 大段静音里只有一小段说话：只要有一块够响就算有声，不能因为平均值低就丢掉。
            var mixed = pcm(amplitude: 0, seconds: 2)
            mixed.append(pcm(amplitude: 3_000, seconds: 0.3))
            mixed.append(pcm(amplitude: 0, seconds: 2))
            Harness.expectEqual(RecordingTriage.classify(pcm: mixed), .speech, "静音中夹一句短话 → 送转写")

            // 切片起点不为 0 时也要按索引遍历（与 AudioLevelMeter 同一陷阱）。
            let padded = Data([0, 0]) + pcm(amplitude: 3_000, seconds: 1)
            Harness.expectEqual(RecordingTriage.classify(pcm: padded.dropFirst(2)), .speech, "Data 切片正确处理")
        }
    }

    private static func emptyTranscript() {
        Harness.suite("RecordingTriage 空转写") {
            Harness.expect(RecordingTriage.isEmptyTranscript(""), "空串")
            Harness.expect(RecordingTriage.isEmptyTranscript("  \n\t"), "纯空白")
            Harness.expect(RecordingTriage.isEmptyTranscript("。"), "只有标点（whisper 对静音常出一个句号）")
            Harness.expect(!RecordingTriage.isEmptyTranscript("好"), "单字是内容")
            Harness.expect(!RecordingTriage.isEmptyTranscript("OK."), "带标点的英文是内容")
        }
    }

    private static func timeout() {
        Harness.suite("RecordingTriage 转写超时") {
            Harness.expectEqual(RecordingTriage.transcribeTimeout(pcmBytes: 0), 30, "下限 30 秒")
            Harness.expectEqual(RecordingTriage.transcribeTimeout(pcmBytes: 32_000 * 40), 90,
                                "40 秒录音 → 30 + 1.5×40 = 90 秒")
            Harness.expectEqual(RecordingTriage.transcribeTimeout(pcmBytes: 32_000 * 600), 180, "上限 180 秒")
        }
    }
}
