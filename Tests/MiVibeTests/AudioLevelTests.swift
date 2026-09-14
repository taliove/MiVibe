import Foundation
import MiVibeCore

/// 实时音量电平的验收：读数单调、切片不错位、起音快过释放。
///
/// 这些性质是浮条那颗球的全部依据——球的表现好不好看可以商量，但"大声读数更大"
/// 和"停顿不立刻归零"是它的语义，坏了就不是审美问题而是撒谎。
enum AudioLevelTests {
    static func run() {
        silenceAndFullScale()
        monotonic()
        sliceIndexing()
        attackFasterThanRelease()
        reset()
    }

    // MARK: - 工具

    /// 生成方波 PCM：`+amplitude / -amplitude` 交替，16 kHz 单声道 pcm_s16le。
    private static func pcm(amplitude: Int16, samples: Int) -> Data {
        var data = Data(capacity: samples * 2)
        for index in 0..<samples {
            let value = index % 2 == 0 ? amplitude : -amplitude
            let bits = UInt16(bitPattern: value)
            data.append(UInt8(bits & 0xFF))
            data.append(UInt8(bits >> 8))
        }
        return data
    }

    // MARK: - 用例

    static func silenceAndFullScale() {
        Harness.suite("静音为 0，满幅为 1") {
            let silence = pcm(amplitude: 0, samples: 240)
            Harness.expectEqual(AudioLevelMeter.normalizedRMS(pcm: silence), 0, "全零 PCM 读数为 0")

            // 满幅方波 RMS = 1.0 → 0 dBFS，高于 ceiling(-8)，钳到 1。
            let full = pcm(amplitude: 32767, samples: 240)
            Harness.expectEqual(AudioLevelMeter.normalizedRMS(pcm: full), 1, "满幅方波读数为 1")

            // -8 dBFS 恰好是 ceiling：振幅 0.398 的方波。
            let atCeiling = pcm(amplitude: 13_042, samples: 240)
            let reading = AudioLevelMeter.normalizedRMS(pcm: atCeiling)
            Harness.expect(abs(reading - 1) < 0.02, "幅度刚到 ceiling 读数贴近 1（实际 \(reading)）")
        }
    }

    static func monotonic() {
        Harness.suite("读数随振幅单调") {
            let quiet = AudioLevelMeter.normalizedRMS(pcm: pcm(amplitude: 1000, samples: 240))
            let medium = AudioLevelMeter.normalizedRMS(pcm: pcm(amplitude: 3000, samples: 240))
            let loud = AudioLevelMeter.normalizedRMS(pcm: pcm(amplitude: 9000, samples: 240))

            Harness.expect(quiet > 0 && quiet < 1, "中等偏小音量落在 0 与 1 之间（实际 \(quiet)）")
            Harness.expect(quiet < medium, "更响的读数更大（\(quiet) < \(medium)）")
            Harness.expect(medium < loud, "再响的读数更大（\(medium) < \(loud)）")
        }
    }

    static func sliceIndexing() {
        Harness.suite("Data 切片索引不从 0 开始时不得错位") {
            // DoubaoClient 就是这么干的：RTP 头 drop 掉之后直接切片上传。
            // 切片保留原 buffer 的下标，一旦代码假设零基就会读错位甚至越界。
            let full = pcm(amplitude: 2000, samples: 400)
            let slice = full.dropFirst(200)
            let copy = Data(slice)

            Harness.expectEqual(
                AudioLevelMeter.normalizedRMS(pcm: slice),
                AudioLevelMeter.normalizedRMS(pcm: copy),
                "切片与零基副本读数一致"
            )

            var meter = AudioLevelMeter()
            let fromSlice = meter.push(pcm: slice)
            var other = AudioLevelMeter()
            let fromCopy = other.push(pcm: copy)
            Harness.expectEqual(fromSlice, fromCopy, "平滑后仍一致")
        }
    }

    static func attackFasterThanRelease() {
        Harness.suite("起音快过释放") {
            var meter = AudioLevelMeter()
            // 一块真实尺寸：480 字节 = 240 采样 = 15ms。
            let loud = pcm(amplitude: 20000, samples: 240)

            let afterOneLoudChunk = meter.push(pcm: loud)
            // 时间常数 70ms、块长 15ms → 单块约抬起 19%。
            Harness.expect(afterOneLoudChunk > 0.15, "一块之内就明显抬起（实际 \(afterOneLoudChunk)）")

            for _ in 0..<40 { _ = meter.push(pcm: loud) }
            let settled = meter.level
            Harness.expect(settled > 0.98, "持续有声后逼近满值（实际 \(settled)）")

            let afterOneSilentChunk = meter.push(pcm: pcm(amplitude: 0, samples: 240))
            Harness.expect(afterOneSilentChunk > 0.85, "一块静音后几乎没掉（实际 \(afterOneSilentChunk)）")

            let attackStep = 1 - (1 - afterOneLoudChunk)
            let releaseStep = settled - afterOneSilentChunk
            Harness.expect(attackStep > releaseStep * 2, "起音步长明显大于释放步长（\(attackStep) vs \(releaseStep)）")
        }
    }

    static func reset() {
        Harness.suite("reset 归零") {
            var meter = AudioLevelMeter()
            for _ in 0..<40 { _ = meter.push(pcm: pcm(amplitude: 20000, samples: 240)) }
            Harness.expect(meter.level > 0.9, "先推到高电平")

            meter.reset()
            Harness.expectEqual(meter.level, 0, "reset 后读数为 0")
        }
    }
}
