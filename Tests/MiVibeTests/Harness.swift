import Foundation

/// 极简断言辅助。
///
/// 本机只有 Command Line Tools，XCTest 与 swift-testing 的模块接口都不存在
/// （框架二进制在、`Modules/` 为空），所以 `swift test` 用不了。测试因此是一个
/// 普通可执行目标：`swift run MiVibeTests`，有失败则退出码非 0。
enum Harness {
    nonisolated(unsafe) private static var failures: [String] = []
    nonisolated(unsafe) private static var checks = 0
    nonisolated(unsafe) private static var currentSuite = ""

    static func suite(_ name: String, _ body: () throws -> Void) {
        currentSuite = name
        print("\n▸ \(name)")
        do {
            try body()
        } catch {
            record("抛出异常：\(error)")
        }
    }

    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if condition {
            print("  ✓ \(message)")
        } else {
            record(message)
        }
    }

    static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        checks += 1
        if actual == expected {
            print("  ✓ \(message)")
        } else {
            record("\(message)\n      实际：\(actual)\n      期望：\(expected)")
        }
    }

    /// Data 相等失败时打印首个不同的字节位置，而不是倾泻整段十六进制。
    static func expectEqualData(_ actual: Data, _ expected: Data, _ message: String) {
        checks += 1
        if actual == expected {
            print("  ✓ \(message)")
            return
        }
        var detail = "长度 实际 \(actual.count) / 期望 \(expected.count)"
        if let index = zip(actual, expected).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
            detail += "；首个不同字节在偏移 \(index)：实际 \(actual[index]) 期望 \(expected[index])"
        }
        record("\(message)\n      \(detail)")
    }

    private static func record(_ message: String) {
        let entry = "\(currentSuite)：\(message)"
        failures.append(entry)
        print("  ✗ \(message)")
    }

    static func finish() -> Never {
        print("\n" + String(repeating: "─", count: 52))
        if failures.isEmpty {
            print("全部通过：\(checks) 项断言")
            exit(0)
        }
        print("失败 \(failures.count) 项 / 共 \(checks) 项断言：")
        for failure in failures { print("  • \(failure)") }
        exit(1)
    }

    // MARK: - 工具

    static func hexToData(_ hex: String) -> Data {
        var out = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex, hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) != nil {
            let next = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<next], radix: 16) { out.append(byte) }
            index = next
        }
        return out
    }

    /// 读取测试固件。SwiftPM 的 Bundle.module 在可执行目标里可用；
    /// 直接跑二进制时回退到源码目录。
    static func fixture(_ name: String) throws -> Data {
        if let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil) {
            return try Data(contentsOf: url)
        }
        let fallback = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: fallback)
    }
}
