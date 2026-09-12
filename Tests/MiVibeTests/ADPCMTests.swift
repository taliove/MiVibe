import Foundation
import MiVibeCore

/// ADPCM 解码器必须与 Python `audioop.adpcm2lin` 字节一致——诊断阶段正是用它解出了
/// 可听的真机录音（SPEC §2），那是"这个解码是对的"的唯一证据。
/// 金标准由 audioop 生成，输入为合成数据，不含真实语音。
enum ADPCMTests {
    struct GoldenCase: Decodable {
        let name: String
        let adpcm: String
        let pcm: String
        let inPredictor: Int32?
        let inIndex: Int32?
        let outPredictor: Int32
        let outIndex: Int32

        enum CodingKeys: String, CodingKey {
            case name, adpcm, pcm
            case inPredictor = "in_predictor"
            case inIndex = "in_index"
            case outPredictor = "out_predictor"
            case outIndex = "out_index"
        }
    }

    static func run() {
        Harness.suite("ADPCM 金标准（对齐 audioop）") {
            let data = try Harness.fixture("adpcm-golden.json")
            let cases = try JSONDecoder().decode([GoldenCase].self, from: data)
            Harness.expect(!cases.isEmpty, "金标准用例已加载（\(cases.count) 组）")

            for golden in cases {
                let input = Harness.hexToData(golden.adpcm)
                let expected = Harness.hexToData(golden.pcm)
                let initial = ADPCM.State(
                    predictor: golden.inPredictor ?? 0,
                    index: golden.inIndex ?? 0
                )

                let (pcm, state) = ADPCM.decode(input, state: initial)

                Harness.expectEqualData(pcm, expected, "\(golden.name)：PCM 逐字节一致")
                Harness.expectEqual(state.predictor, golden.outPredictor, "\(golden.name)：出口 predictor")
                Harness.expectEqual(state.index, golden.outIndex, "\(golden.name)：出口 index")
            }
        }

        Harness.suite("ADPCM 基本性质") {
            let (pcm, _) = ADPCM.decode(Data(repeating: 0x5A, count: 120), state: .init())
            Harness.expectEqual(pcm.count, 120 * 4, "每字节产出两个 16-bit 采样（120 字节真机帧 → 480 字节 PCM）")

            let (empty, state) = ADPCM.decode(Data(), state: .init(predictor: 7, index: 3))
            Harness.expectEqual(empty.count, 0, "空输入产出空 PCM")
            Harness.expectEqual(state, ADPCM.State(predictor: 7, index: 3), "空输入不改变状态")

            let (clamped, wild) = ADPCM.decode(Data([0x01]), state: .init(predictor: 0, index: 999))
            Harness.expectEqual(clamped.count, 4, "越界 index 不崩溃")
            Harness.expect(wild.index <= 88, "越界 index 被夹到合法范围（实际 \(wild.index)）")
        }

        Harness.suite("ADPCM 分帧解码（真机按 120 字节帧到达）") {
            let data = try Harness.fixture("adpcm-golden.json")
            let cases = try JSONDecoder().decode([GoldenCase].self, from: data)
            guard let golden = cases.first(where: { $0.name == "two_frames" }) else {
                Harness.expect(false, "缺少 two_frames 用例")
                return
            }
            let input = Harness.hexToData(golden.adpcm)
            let (whole, wholeState) = ADPCM.decode(input, state: .init())

            var chunked = Data()
            var state = ADPCM.State()
            for start in stride(from: 0, to: input.count, by: 120) {
                let end = min(start + 120, input.count)
                let (pcm, next) = ADPCM.decode(Data(input[start..<end]), state: state)
                chunked.append(pcm)
                state = next
            }

            Harness.expectEqualData(chunked, whole, "逐帧解码与整段解码等价（状态接力正确）")
            Harness.expectEqual(state, wholeState, "逐帧解码的出口状态一致")
        }
    }
}
