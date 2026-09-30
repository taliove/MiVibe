import Foundation
import MiVibeCore

/// 按设备重映射（方案 A）的条目规则：写入只动自己的条目，撤销能在崩溃后无状态清理。
///
/// 接管不再依赖 HID 独占（键盘类设备普通进程 seize 必然 0xE00002C1），改为把遥控器的
/// 键在系统事件层映射成死键。条目算错的后果是真实的：漏一个键 = 系统和 MiVibe 各处理
/// 一次；撤销不干净 = 关掉接管后遥控器按键失灵。
enum RemoteKeyRemapTests {
    static func run() {
        coverage()
        applyAndRemove()
        preservesForeignEntries()
        detection()
    }

    private static func pair(_ usage: UInt64, _ dst: UInt64) -> KeyUsageMapping {
        KeyUsageMapping(src: RemoteKeyRemap.keyboardPage | usage, dst: dst)
    }

    private static func coverage() {
        Harness.suite("RemoteKeyRemap 覆盖范围") {
            let sources = Set(RemoteKeyRemap.entries.map(\.src))
            Harness.expectEqual(sources.count, RemoteButton.allCases.count - 1, "除电源键外每个键一条")
            Harness.expect(!sources.contains(RemoteKeyRemap.keyboardPage | 0x66), "电源键不重映射（SPEC §3）")
            Harness.expect(sources.contains(RemoteKeyRemap.keyboardPage | 0x3E), "语音键重映射：F5 不再漏给前台应用")
            Harness.expect(sources.contains(RemoteKeyRemap.keyboardPage | 0x80), "音量键同在键盘页，一并重映射")
            Harness.expect(RemoteKeyRemap.entries.allSatisfy { $0.dst == RemoteKeyRemap.deadUsage }, "目标全是死键")
        }
    }

    private static func applyAndRemove() {
        Harness.suite("RemoteKeyRemap 写入与撤销") {
            let applied = RemoteKeyRemap.applying(to: [])
            Harness.expectEqual(applied, RemoteKeyRemap.entries, "空映射上写入 = 全部条目")
            Harness.expectEqual(RemoteKeyRemap.applying(to: applied), applied, "重复写入幂等（设备每次出现都会重写）")
            Harness.expectEqual(RemoteKeyRemap.removing(from: applied), [], "撤销后回到空映射")
            Harness.expectEqual(RemoteKeyRemap.removing(from: []), [], "没有残留时撤销是 no-op")
        }
    }

    private static func preservesForeignEntries() {
        Harness.suite("RemoteKeyRemap 保留他人条目") {
            let foreign = pair(0x04, RemoteKeyRemap.keyboardPage | 0x05)   // 用户自己的 A→B
            let applied = RemoteKeyRemap.applying(to: [foreign])
            Harness.expect(applied.contains(foreign), "写入保留无关条目")
            Harness.expectEqual(RemoteKeyRemap.removing(from: applied), [foreign], "撤销只剥离自己的条目")

            let userUp = pair(0x52, RemoteKeyRemap.keyboardPage | 0x04)    // 用户把「上」映射成了 A
            let removed = RemoteKeyRemap.removing(from: [userUp])
            Harness.expectEqual(removed, [userUp], "同源不同目标的条目不是我们写的，撤销不碰")
        }
    }

    private static func detection() {
        Harness.suite("RemoteKeyRemap 生效判定") {
            Harness.expect(RemoteKeyRemap.isApplied(RemoteKeyRemap.applying(to: [])), "全部条目在位 = 已生效")
            Harness.expect(!RemoteKeyRemap.isApplied([]), "空映射 = 未生效")
            let partial = Array(RemoteKeyRemap.entries.dropFirst())
            Harness.expect(!RemoteKeyRemap.isApplied(partial), "缺一条 = 未生效（漏的键会被系统和 MiVibe 各处理一次）")
        }
    }
}
