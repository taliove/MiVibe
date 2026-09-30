import Foundation

/// 一条系统按键重映射（`UserKeyMapping` 的一项）：高 32 位 usage page，低 32 位 usage。
public struct KeyUsageMapping: Equatable, Hashable, Sendable {
    public let src: UInt64
    public let dst: UInt64

    public init(src: UInt64, dst: UInt64) {
        self.src = src
        self.dst = dst
    }
}

/// 按键接管的重映射条目规则（纯逻辑，可脱离硬件测试）。
///
/// 为什么不用 HID 独占：遥控器是键盘类设备，IOHIDFamily 只许 root 或带 Apple 私有授权
/// 的进程 seize 键盘（普通进程恒得 0xE00002C1）。替代做法是只对这支遥控器的事件服务
/// 写 `UserKeyMapping`，把它的键映射成死键：系统不再响应，而 IOHIDManager 非独占读到的
/// 仍是映射前的原始 usage（`--probe-remap` 实测），路由与合成照旧。
///
/// 撤销是**无状态**的：只剥离"源是我们的键、目标是死键"的条目，不依赖事先保存的原值——
/// App 崩溃后下次启动仍能清理干净，用户自己写的其他条目也不受影响。
public enum RemoteKeyRemap {
    /// 键盘 usage page（0x07）在映射值里的前缀。
    public static let keyboardPage: UInt64 = 0x7_0000_0000
    /// 死键：键盘页 usage 0（Reserved，no event indicated）。实测映射到它后系统零事件。
    public static let deadUsage: UInt64 = keyboardPage

    /// 参与重映射的键：除电源键外全部。电源键系统本就无响应，SPEC §3 明确不接管。
    /// 语音键也在内：它在 HID 面是 F5，不压住会漏给前台应用；按住说话走 BLE，不受影响。
    public static var remappedButtons: [RemoteButton] {
        RemoteButton.allCases.filter { $0 != .power }
    }

    /// 接管需要写入的全部条目。
    public static var entries: [KeyUsageMapping] {
        remappedButtons.map { KeyUsageMapping(src: keyboardPage | UInt64($0.rawValue), dst: deadUsage) }
    }

    /// 在现有映射上写入接管条目：同源旧条目被替换，其他条目原样保留。幂等。
    public static func applying(to existing: [KeyUsageMapping]) -> [KeyUsageMapping] {
        let ours = Set(entries.map(\.src))
        return existing.filter { !ours.contains($0.src) } + entries
    }

    /// 剥离接管条目。只认"我们的源 + 死键目标"，同源但目标不同的条目不是我们写的，不碰。
    public static func removing(from existing: [KeyUsageMapping]) -> [KeyUsageMapping] {
        let ours = Set(entries)
        return existing.filter { !ours.contains($0) }
    }

    /// 接管条目是否全部在位。缺任何一条，那个键就会被系统和 MiVibe 各处理一次。
    public static func isApplied(_ existing: [KeyUsageMapping]) -> Bool {
        Set(entries).isSubset(of: Set(existing))
    }
}
