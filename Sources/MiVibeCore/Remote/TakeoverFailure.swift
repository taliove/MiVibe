import Foundation

/// 按键接管失败的分类（纯逻辑，可脱离硬件测试）。
///
/// 接管由两步组成：非独占打开 HID 监听，再对遥控器写入按设备重映射。原因决定了
/// 用户能做什么：
/// - `notPermitted`（0xE00002E2）：TCC 输入监控未放行，监听打不开。授权后重试可解决。
///   这时**不能**写重映射——系统不响应、MiVibe 又收不到，遥控器就彻底失灵了。
/// - `remapRejected`：事件系统拒绝写入 `UserKeyMapping`，或读回不一致。
/// - `notPrivileged`（0xE00002C1）：IOHIDFamily 对键盘类设备 seize 的硬规则（非 root
///   不许独占）。接管已改用重映射、不再 seize，保留此分类只为准确描述遗留错误码。
/// - `exclusiveAccess`（0xE00002C5）：已被其他进程独占，对方释放后可重试。
public enum TakeoverFailure: Equatable, Sendable {
    case notPrivileged
    case notPermitted
    case exclusiveAccess
    case remapRejected
    case other(Int32)

    /// 按 IOReturn 分类 HID 打开失败。
    public init(status: Int32) {
        switch UInt32(bitPattern: status) {
        case 0xE000_02C1: self = .notPrivileged
        case 0xE000_02E2: self = .notPermitted
        case 0xE000_02C5: self = .exclusiveAccess
        default: self = .other(status)
        }
    }

    /// 对应的 IOReturn；重映射被拒不是 IOReturn，返回 nil。
    public var status: Int32? {
        switch self {
        case .notPrivileged: Int32(bitPattern: 0xE000_02C1)
        case .notPermitted: Int32(bitPattern: 0xE000_02E2)
        case .exclusiveAccess: Int32(bitPattern: 0xE000_02C5)
        case .remapRejected: nil
        case .other(let status): status
        }
    }

    /// 重试是否可能改变结果。false 时不该自动重试，也不该引导用户反复授权。
    public var isRetryable: Bool { self != .notPrivileged }

    /// 是否应引导用户去「输入监控」授权。
    public var needsInputMonitoring: Bool { self == .notPermitted }

    /// 给人看的原因，附十六进制错误码便于排障。IOReturn 是有符号 Int32，
    /// 按位解释为 UInt32 才是文档里的 0xE00002C1 写法。
    public var reason: String {
        let code = status.map { String(format: "0x%08X", UInt32(bitPattern: $0)) } ?? ""
        switch self {
        case .notPrivileged: return "系统不允许普通应用独占键盘类设备（\(code)）"
        case .notPermitted: return "缺少「输入监控」权限（\(code)）"
        case .exclusiveAccess: return "设备已被其他程序独占（\(code)）"
        case .remapRejected: return "系统拒绝写入遥控器按键重映射"
        case .other: return "HID 打开失败（\(code)）"
        }
    }
}
