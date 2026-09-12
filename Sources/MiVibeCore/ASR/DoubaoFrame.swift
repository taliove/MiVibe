import Foundation

/// 豆包双向流式 ASR 的二进制帧编解码（SPEC §4）。
///
/// 全部字段经真实服务实测确认（2026-09-09），几处与官方文档不一致的地方以实测为准：
/// - **结束判定只看帧头 flags 的 0x02 位**，不看 sequence 符号（实测最终帧 seq 为正，
///   文档却称最后一包应为负 sequence）。
/// - `is_last_package` 不是 JSON 字段，而是官方示例包装层由 flags 算出的布尔值。
/// - `result` 是 object（文档表格写的 list 不实）。
/// - 下行 payload 实测**不压缩**，上行全压缩 → 必须逐帧按帧头判断，不能全局假设。
public enum DoubaoFrame {
    // MARK: - 常量

    public static let protocolVersion: UInt8 = 0b0001

    public enum MessageType: UInt8 {
        case fullClientRequest = 0b0001
        case audioOnlyRequest = 0b0010
        case serverResponse = 0b1001
        case serverError = 0b1111
    }

    /// flags 是**位域**，不是枚举值：0x01 带 sequence，0x02 末包，0x04 带 event。
    public struct Flags: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let hasSequence = Flags(rawValue: 0x01)
        public static let lastPacket = Flags(rawValue: 0x02)
        public static let hasEvent = Flags(rawValue: 0x04)
    }

    public enum Serialization: UInt8 {
        case none = 0b0000
        case json = 0b0001
    }

    public enum Compression: UInt8 {
        case none = 0b0000
        case gzip = 0b0001
    }

    public enum ParseError: Error, Equatable {
        case tooShort(expected: Int, got: Int)
        case unknownMessageType(UInt8)
        case truncatedPayload(declared: Int, available: Int)
        case gzipFailed
        case notJSON
    }

    // MARK: - 帧头

    public static func header(
        type: MessageType,
        flags: Flags,
        serialization: Serialization,
        compression: Compression
    ) -> Data {
        Data([
            (protocolVersion << 4) | 0x01,  // 版本 | 头长（1 单位 = 4 字节）
            (type.rawValue << 4) | (flags.rawValue & 0x0F),
            (serialization.rawValue << 4) | (compression.rawValue & 0x0F),
            0x00,  // 保留
        ])
    }

    // MARK: - 上行

    /// 首包：完整客户端请求（JSON + gzip，带正 sequence）。
    public static func fullClientRequest(payload: Data, sequence: Int32 = 1) throws -> Data {
        let body = try Gzip.compress(payload)
        var frame = header(type: .fullClientRequest, flags: .hasSequence, serialization: .json, compression: .gzip)
        frame.append(bigEndian(sequence))
        frame.append(bigEndian(UInt32(body.count)))
        frame.append(body)
        return frame
    }

    /// 音频包。末包遵循官方示例惯例：flags = 0b0011（末包 + 带 sequence）、
    /// sequence 取负、payload 为 gzip 压缩的空字节。
    public static func audioPacket(pcm: Data, sequence: Int32, isLast: Bool) throws -> Data {
        let flags: Flags = isLast ? [.hasSequence, .lastPacket] : .hasSequence
        let body = try Gzip.compress(pcm)
        var frame = header(type: .audioOnlyRequest, flags: flags, serialization: .none, compression: .gzip)
        frame.append(bigEndian(isLast ? -sequence : sequence))
        frame.append(bigEndian(UInt32(body.count)))
        frame.append(body)
        return frame
    }

    // MARK: - 下行

    public struct Response: Equatable {
        public var messageType: MessageType
        public var flags: Flags
        public var sequence: Int32?
        public var event: Int32?
        public var errorCode: Int32?
        public var payload: Data?

        /// 结束标志：**只**由 flags 的 0x02 位决定。
        public var isLastPackage: Bool { flags.contains(.lastPacket) }
    }

    public static func parse(_ raw: Data) throws -> Response {
        guard raw.count >= 4 else { throw ParseError.tooShort(expected: 4, got: raw.count) }
        let bytes = [UInt8](raw)

        let headerWords = Int(bytes[0] & 0x0F)
        let typeRaw = bytes[1] >> 4
        let flags = Flags(rawValue: bytes[1] & 0x0F)
        let serialization = Serialization(rawValue: bytes[2] >> 4)
        let compression = Compression(rawValue: bytes[2] & 0x0F)

        guard let messageType = MessageType(rawValue: typeRaw) else {
            throw ParseError.unknownMessageType(typeRaw)
        }

        var cursor = max(4, headerWords * 4)
        func take(_ count: Int) throws -> [UInt8] {
            guard cursor + count <= bytes.count else {
                throw ParseError.tooShort(expected: cursor + count, got: bytes.count)
            }
            defer { cursor += count }
            return Array(bytes[cursor..<(cursor + count)])
        }

        var response = Response(
            messageType: messageType, flags: flags,
            sequence: nil, event: nil, errorCode: nil, payload: nil
        )

        if flags.contains(.hasSequence) { response.sequence = int32(try take(4)) }
        if flags.contains(.hasEvent) { response.event = int32(try take(4)) }
        if messageType == .serverError { response.errorCode = int32(try take(4)) }

        // 长度字段之后即 payload；没有长度字段时（部分控制帧）视为无 payload。
        guard cursor + 4 <= bytes.count else { return response }
        let declared = Int(uint32(try take(4)))
        guard declared > 0 else { return response }
        guard cursor + declared <= bytes.count else {
            throw ParseError.truncatedPayload(declared: declared, available: bytes.count - cursor)
        }

        var payload = Data(try take(declared))
        // 逐帧按帧头解压：实测下行不压缩，但不能据此写死。
        if compression == .gzip {
            do { payload = try Gzip.decompress(payload) } catch { throw ParseError.gzipFailed }
        }
        response.payload = payload
        _ = serialization
        return response
    }

    // MARK: - 字节序（协议整数为大端，与 PCM 的小端相反）

    public static func bigEndian(_ value: Int32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    public static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func int32(_ bytes: [UInt8]) -> Int32 {
        bytes.reduce(Int32(0)) { ($0 << 8) | Int32($1) }
    }

    private static func uint32(_ bytes: [UInt8]) -> UInt32 {
        bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
