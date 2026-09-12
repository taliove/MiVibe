import Compression
import Foundation

/// gzip 压缩/解压。
///
/// 用 Apple 的 Compression 框架（`COMPRESSION_ZLIB` 是 raw deflate，所以 gzip 的
/// 头尾要自己处理）。豆包协议要求上行 payload 为 gzip。
public enum Gzip {
    public enum GzipError: Error {
        case compressFailed
        case decompressFailed
        case badHeader
    }

    public static func compress(_ data: Data) throws -> Data {
        // gzip 头：magic(1f 8b) + deflate(08) + 无 flag + 无时间戳 + 无额外 + 未知 OS
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        if !data.isEmpty {
            out.append(try transform(data, operation: COMPRESSION_STREAM_ENCODE))
        } else {
            // 空输入的 deflate 空块（末包用得到）
            out.append(Data([0x03, 0x00]))
        }
        out.append(DoubaoFrame.littleEndian(crc32(data)))
        out.append(DoubaoFrame.littleEndian(UInt32(truncatingIfNeeded: data.count)))
        return out
    }

    public static func decompress(_ data: Data) throws -> Data {
        guard data.count > 18, data[data.startIndex] == 0x1F, data[data.startIndex + 1] == 0x8B else {
            throw GzipError.badHeader
        }
        let flags = data[data.startIndex + 3]
        var offset = data.startIndex + 10

        if flags & 0x04 != 0 {  // FEXTRA
            let length = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + length
        }
        if flags & 0x08 != 0 {  // FNAME
            while offset < data.endIndex, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {  // FCOMMENT
            while offset < data.endIndex, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }  // FHCRC

        let deflate = data[offset..<(data.endIndex - 8)]
        guard !deflate.isEmpty else { return Data() }
        return try transform(Data(deflate), operation: COMPRESSION_STREAM_DECODE)
    }

    // MARK: - 私有

    private static func transform(_ source: Data, operation: compression_stream_operation) throws -> Data {
        let streamBox = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamBox.deallocate() }
        var stream = streamBox.pointee
        guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw operation == COMPRESSION_STREAM_ENCODE ? GzipError.compressFailed : GzipError.decompressFailed
        }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var output = Data()
        let result: Data? = source.withUnsafeBytes { raw -> Data? in
            stream.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress!
            stream.src_size = source.count
            repeat {
                stream.dst_ptr = buffer
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                if produced > 0 { output.append(buffer, count: produced) }
                switch status {
                case COMPRESSION_STATUS_END: return output
                case COMPRESSION_STATUS_OK: continue
                default: return nil
                }
            } while true
        }

        guard let result else {
            throw operation == COMPRESSION_STREAM_ENCODE ? GzipError.compressFailed : GzipError.decompressFailed
        }
        return result
    }

    static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1 != 0) ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

extension DoubaoFrame {
    static func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
