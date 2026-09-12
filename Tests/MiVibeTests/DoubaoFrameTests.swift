import Foundation
import MiVibeCore

/// 用**真实豆包服务返回的帧**验证解析器（2026-09-09 实测采集，7 帧）。
/// 这些字节是"协议理解正确"的唯一硬证据，比手写用例可靠。
enum DoubaoFrameTests {
    struct Fixture: Decodable {
        let note: String
        let frames: [Frame]
        struct Frame: Decodable {
            let source: String
            let kind: String
            let hex: String
            let msgType: Int
            let flags: Int
            let hasSeq: Bool
            let isLastPackage: Bool
            let hasEventField: Bool
            let serialization: Int
            let compression: Int
            let sequence: Int32?
            let payloadSize: Int?
            let text: String?

            enum CodingKeys: String, CodingKey {
                case source, kind, hex, flags, sequence, text
                case msgType = "msg_type"
                case hasSeq = "has_seq"
                case isLastPackage = "is_last_package"
                case hasEventField = "has_event_field"
                case serialization, compression
                case payloadSize = "payload_size"
            }
        }
    }

    static func run() {
        Harness.suite("豆包帧解析（真实服务帧金标准）") {
            let data = try Harness.fixture("doubao-frames.json")
            let fixture = try JSONDecoder().decode(Fixture.self, from: data)
            Harness.expect(!fixture.frames.isEmpty, "真实帧已加载（\(fixture.frames.count) 帧）")

            for frame in fixture.frames {
                let raw = Harness.hexToData(frame.hex)
                let parsed = try DoubaoFrame.parse(raw)
                let tag = "\(frame.kind)/seq=\(frame.sequence.map(String.init) ?? "-")"

                Harness.expectEqual(Int(parsed.messageType.rawValue), frame.msgType, "\(tag)：消息类型")
                Harness.expectEqual(Int(parsed.flags.rawValue), frame.flags, "\(tag)：flags 位域")
                Harness.expectEqual(parsed.isLastPackage, frame.isLastPackage, "\(tag)：结束标志取自 flags 0x02")
                Harness.expectEqual(parsed.sequence, frame.sequence, "\(tag)：sequence")

                if let expectedText = frame.text {
                    let payload = try require(parsed.payload, "\(tag)：应有 payload")
                    let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
                    let result = json?["result"] as? [String: Any]
                    Harness.expect(result != nil, "\(tag)：result 是 object（不是 list）")
                    Harness.expectEqual(result?["text"] as? String, expectedText, "\(tag)：识别文本一致")
                }
            }
        }

        Harness.suite("豆包最终帧的关键实测事实") {
            let data = try Harness.fixture("doubao-frames.json")
            let fixture = try JSONDecoder().decode(Fixture.self, from: data)
            let finals = fixture.frames.filter { $0.kind == "final_frame" }
            Harness.expect(!finals.isEmpty, "存在最终帧（\(finals.count) 个）")

            for frame in finals {
                let parsed = try DoubaoFrame.parse(Harness.hexToData(frame.hex))
                // 这条正是文档与实测冲突之处：最终帧 sequence 为**正**。
                Harness.expect((parsed.sequence ?? 0) > 0,
                               "最终帧 sequence 为正（\(parsed.sequence ?? 0)）——故不可用符号判结束")
                Harness.expect(parsed.isLastPackage, "最终帧 flags 含 0x02")
                Harness.expect(!parsed.flags.contains(.hasEvent), "最终帧未出现 0x04 位（与 veadk 的 event 解读不同）")
            }
        }

        Harness.suite("上行帧构造") {
            let request = try DoubaoFrame.fullClientRequest(payload: Data(#"{"a":1}"#.utf8), sequence: 1)
            let bytes = [UInt8](request)
            Harness.expectEqual(bytes[0], 0x11, "首包：版本 1 + 头长 1")
            Harness.expectEqual(bytes[1], 0x11, "首包：类型 1 + flags 0x01（带 sequence）")
            Harness.expectEqual(bytes[2], 0x11, "首包：JSON + gzip")
            Harness.expectEqual(Array(bytes[4..<8]), [0, 0, 0, 1], "首包：大端正 sequence")

            let last = try DoubaoFrame.audioPacket(pcm: Data(), sequence: 7, isLast: true)
            let lastBytes = [UInt8](last)
            Harness.expectEqual(lastBytes[1], 0x23, "末包：类型 2 + flags 0b0011")
            let seq = Int32(bitPattern: UInt32(lastBytes[4]) << 24 | UInt32(lastBytes[5]) << 16
                | UInt32(lastBytes[6]) << 8 | UInt32(lastBytes[7]))
            Harness.expectEqual(seq, -7, "末包：sequence 取负（官方示例惯例）")

            let mid = try DoubaoFrame.audioPacket(pcm: Data(repeating: 0xAB, count: 64), sequence: 3, isLast: false)
            Harness.expectEqual([UInt8](mid)[1], 0x21, "音频包：类型 2 + flags 0x01")
        }

        Harness.suite("gzip 往返与容错") {
            for payload in [Data(), Data("你好 MiVibe".utf8), Data(repeating: 0x5A, count: 12_000)] {
                let round = try Gzip.decompress(try Gzip.compress(payload))
                Harness.expectEqualData(round, payload, "gzip 往返（\(payload.count) 字节）")
            }

            // 声明 gzip 但内容损坏：抛错而非崩溃
            var corrupt = DoubaoFrame.header(type: .serverResponse, flags: [], serialization: .json, compression: .gzip)
            corrupt.append(DoubaoFrame.bigEndian(UInt32(4)))
            corrupt.append(Data([0x61, 0x62, 0x63, 0x64]))
            do {
                _ = try DoubaoFrame.parse(corrupt)
                Harness.expect(false, "损坏的 gzip payload 应抛错")
            } catch {
                Harness.expect(true, "损坏的 gzip payload 抛错而非崩溃")
            }

            // 截断帧
            do {
                _ = try DoubaoFrame.parse(Data([0x11, 0x90]))
                Harness.expect(false, "截断帧应抛错")
            } catch {
                Harness.expect(true, "截断帧抛错而非崩溃")
            }
        }
    }
}

/// 小工具：取出可选值，失败时给出可读信息。
struct RequireFailed: Error { let message: String }

func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw RequireFailed(message: message) }
    return value
}
