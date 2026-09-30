import Foundation
import MiVibeCore

/// 待处理列表阶段 → 色点令牌映射的验收（spec C，epic #1 子任务 #4）。
///
/// 守的契约：进行中（听/转写）= accent（随主题），待输入 = success，
/// 任意需处理（转写失败/失焦/注入失败，不论带不带文字）= attention。
/// 直接测 `QueueDotColor.phase`（MiVibeCore），不再在测试里镜像一份规则。
enum QueueDotColorTests {
    static func run() {
        inProgress()
        ready()
        needsAttention()
    }

    static func inProgress() {
        Harness.suite("阶段色点：进行中 = accent") {
            Harness.expect(QueueDotColor.phase(.listening) == .accent, "正在听 → accent")
            Harness.expect(QueueDotColor.phase(.transcribing) == .accent, "正在转写 → accent")
        }
    }

    static func ready() {
        Harness.suite("阶段色点：待输入 = success") {
            Harness.expect(QueueDotColor.phase(.ready("你好")) == .success, "待输入 → success")
            Harness.expect(QueueDotColor.phase(.ready("")) == .success, "空文字待输入 → success")
        }
    }

    static func needsAttention() {
        Harness.suite("阶段色点：需处理 = attention") {
            Harness.expect(
                QueueDotColor.phase(.needsAttention(.transcriptionFailed)) == .attention,
                "转写失败 → attention")
            Harness.expect(
                QueueDotColor.phase(.needsAttention(.targetLost(text: "你好"))) == .attention,
                "目标已变（带文字）→ attention")
            Harness.expect(
                QueueDotColor.phase(.needsAttention(.targetLost(text: ""))) == .attention,
                "目标已变（空文字）→ attention")
            Harness.expect(
                QueueDotColor.phase(.needsAttention(.injectionFailed(text: "你好"))) == .attention,
                "注入失败 → attention")
        }
    }
}
