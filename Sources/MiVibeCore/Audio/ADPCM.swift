import Foundation

/// 遥控器 ATVV 音频帧的 4-bit ADPCM 解码器。
///
/// 这是 `audioop.adpcm2lin`（Intel/DVI 变体）的逐位移植：诊断阶段用 Python 的
/// `audioop` 解出过可听的真机录音（见 SPEC §2），所以这里必须与它**字节一致**，
/// 不能替换成别的"IMA ADPCM"实现——两者在步长更新时序上有差异。
///
/// 关键时序：`step` 取自更新**之前**的 index，index 更新用整个 nibble 查表。
///
/// 步长表**必须**照抄 CPython `Modules/audioop.c` 的 `stepsizeTable`，不要凭记忆写：
/// 索引 55 是 `1411`，而广为流传的 IMA ADPCM 表在该位置是 `1408`。这个 3 的差异
/// 只影响少数采样（差 1），肉眼听不出来，但会让金标准比对失败。
public enum ADPCM {
    private static let stepSizes: [Int32] = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
        19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
        50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
        130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
        337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
        876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
        2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
        5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
        15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
    ]

    private static let indexDeltas: [Int32] = [
        -1, -1, -1, -1, 2, 4, 6, 8,
        -1, -1, -1, -1, 2, 4, 6, 8,
    ]

    /// 解码器状态：跨帧延续，与 `audioop` 的 state 元组语义相同。
    public struct State: Equatable {
        public var predictor: Int32 = 0
        public var index: Int32 = 0

        public init(predictor: Int32 = 0, index: Int32 = 0) {
            self.predictor = predictor
            self.index = index
        }
    }

    /// 解码一段 ADPCM，返回 16-bit 小端 PCM 及延续状态。
    ///
    /// 每字节高 nibble 先解，低 nibble 后解，与 `audioop` 一致。
    public static func decode(_ input: Data, state: State) -> (pcm: Data, state: State) {
        var valpred = state.predictor
        var index = max(0, min(88, state.index))
        var pcm = Data(capacity: input.count * 4)

        for byte in input {
            for nibble in [Int32(byte >> 4) & 0x0F, Int32(byte) & 0x0F] {
                let step = stepSizes[Int(index)]

                index += indexDeltas[Int(nibble)]
                if index < 0 { index = 0 }
                if index > 88 { index = 88 }

                var diff = step >> 3
                if nibble & 4 != 0 { diff += step }
                if nibble & 2 != 0 { diff += step >> 1 }
                if nibble & 1 != 0 { diff += step >> 2 }

                if nibble & 8 != 0 {
                    valpred -= diff
                } else {
                    valpred += diff
                }
                if valpred > 32767 { valpred = 32767 }
                if valpred < -32768 { valpred = -32768 }

                let sample = Int16(truncatingIfNeeded: valpred)
                pcm.append(UInt8(truncatingIfNeeded: sample))
                pcm.append(UInt8(truncatingIfNeeded: sample >> 8))
            }
        }

        return (pcm, State(predictor: valpred, index: index))
    }
}
