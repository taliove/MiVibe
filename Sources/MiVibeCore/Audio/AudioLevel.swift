import Foundation

/// 实时音量电平：把 16 kHz 单声道 pcm_s16le 分块折算成 0…1 的读数。
///
/// 纯逻辑、无副作用：不碰 UI、不读时钟。块时长由调用方按采样数推进，
/// 因此同一段音频在同一台机器上结果稳定，可以写死断言。
///
/// 平滑是**非对称**的：起音快、释放慢。语音音量逐块跳变很剧烈，对称平滑要么抖
/// （快）要么钝（慢），非对称才既跟手又不抽。
public struct AudioLevelMeter {
    /// 静音门限（dBFS）：低于此值读作 0。
    public var floorDB: Double
    /// 满度（dBFS）：达到或超过此值读作 1。
    public var ceilingDB: Double
    /// 起音时间常数（秒）——声音变大时追赶有多快。
    public var attack: Double
    /// 释放时间常数（秒）——声音变小时回落有多慢。
    public var release: Double
    /// 采样率，仅用于把采样数换成块时长。
    public var sampleRate: Double

    /// 平滑后的当前电平 0…1。
    public private(set) var level: Double = 0

    public init(
        floorDB: Double = -50,
        ceilingDB: Double = -8,
        attack: Double = 0.07,
        release: Double = 0.22,
        sampleRate: Double = 16_000
    ) {
        self.floorDB = floorDB
        self.ceilingDB = ceilingDB
        self.attack = attack
        self.release = release
        self.sampleRate = sampleRate
    }

    /// 推入一块 PCM，返回平滑后的电平 0…1。
    public mutating func push(pcm: Data) -> Double {
        let target = Self.normalizedRMS(pcm: pcm, floorDB: floorDB, ceilingDB: ceilingDB)
        let seconds = Double(pcm.count / 2) / sampleRate
        let tau = target > level ? attack : release
        let alpha = tau > 0 ? 1 - exp(-seconds / tau) : 1
        level += (target - level) * alpha
        return level
    }

    /// 重新开始一段录音。
    public mutating func reset() {
        level = 0
    }

    /// 单块 RMS → dBFS → 0…1（未平滑）。
    ///
    /// 注意：传入的 `Data` 可能是切片（例如从某个大 buffer 里切出来的），其
    /// `startIndex` 不从 0 开始，必须按索引遍历而不是按 0…count 下标取。
    public static func normalizedRMS(pcm: Data, floorDB: Double = -50, ceilingDB: Double = -8) -> Double {
        let sampleCount = pcm.count / 2
        guard sampleCount > 0, ceilingDB > floorDB else { return 0 }

        var sum = 0.0
        var index = pcm.startIndex
        for _ in 0..<sampleCount {
            let lo = UInt16(pcm[index])
            let hi = UInt16(pcm[index + 1])
            let sample = Int16(bitPattern: hi << 8 | lo)
            let normalized = Double(sample) / 32768.0
            sum += normalized * normalized
            index += 2
        }

        let rms = (sum / Double(sampleCount)).squareRoot()
        guard rms > 0 else { return 0 }

        let db = 20 * log10(rms)
        let unit = (db - floorDB) / (ceilingDB - floorDB)
        return min(1, max(0, unit))
    }
}
