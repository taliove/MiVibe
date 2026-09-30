import Foundation
import MiVibeCore

/// 接管失败分类的验收：错误码映射准确，只有真能靠授权/重试解决的才标为可重试。
///
/// 这是"接管状态为未生效"排障的依据——把 0xE00002C1 误报成缺输入监控，
/// 用户会反复去系统设置开关权限而永远等不到生效。
enum TakeoverFailureTests {
    static func run() {
        Harness.suite("TakeoverFailure 错误码分类") {
            Harness.expectEqual(TakeoverFailure(status: Int32(bitPattern: 0xE000_02C1)), .notPrivileged,
                                "0xE00002C1 → 系统不允许普通进程独占键盘")
            Harness.expectEqual(TakeoverFailure(status: Int32(bitPattern: 0xE000_02E2)), .notPermitted,
                                "0xE00002E2 → 缺输入监控授权")
            Harness.expectEqual(TakeoverFailure(status: Int32(bitPattern: 0xE000_02C5)), .exclusiveAccess,
                                "0xE00002C5 → 已被其他进程独占")
            Harness.expectEqual(TakeoverFailure(status: Int32(bitPattern: 0xE000_02BC)),
                                .other(Int32(bitPattern: 0xE000_02BC)), "未知错误码原样保留")
        }

        Harness.suite("TakeoverFailure 可重试性") {
            Harness.expect(!TakeoverFailure.notPrivileged.isRetryable, "系统限制：授权与重试都改变不了")
            Harness.expect(TakeoverFailure.notPermitted.isRetryable, "缺授权：授权后可重试")
            Harness.expect(TakeoverFailure.exclusiveAccess.isRetryable, "被占用：对方释放后可重试")
            Harness.expect(TakeoverFailure.remapRejected.isRetryable, "重映射被拒：保留重试入口")
            Harness.expect(TakeoverFailure.other(-1).isRetryable, "未知错误：保留重试入口")
            Harness.expect(TakeoverFailure.notPermitted.needsInputMonitoring, "只有缺授权才引导去输入监控")
            Harness.expect(!TakeoverFailure.remapRejected.needsInputMonitoring, "重映射被拒不引导授权")
        }

        Harness.suite("TakeoverFailure 描述") {
            Harness.expect(TakeoverFailure.notPrivileged.reason.contains("0xE00002C1"), "原因附带十六进制错误码")
            Harness.expect(!TakeoverFailure.notPrivileged.reason.contains("输入监控"), "系统限制不误导为缺权限")
            Harness.expect(TakeoverFailure.notPermitted.reason.contains("输入监控"), "缺授权时点名输入监控")
            Harness.expectEqual(TakeoverFailure.remapRejected.status, nil, "重映射被拒没有 IOReturn")
        }
    }
}
