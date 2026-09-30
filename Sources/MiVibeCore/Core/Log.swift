import OSLog

/// 诊断日志。菜单栏应用没有控制台可看，链路问题（录音→转写→注入）不靠猜，
/// 用 `log show --predicate 'subsystem == "io.github.taliove.mivibe"' --last 10m --info` 读。
///
/// 只记状态与长度，**不记识别文字内容**——那是用户刚说过的话。
public enum Log {
    public static let chain = Logger(subsystem: "io.github.taliove.mivibe", category: "chain")
    /// 动效诊断（epic #1 子任务 F）：浮条视图更新计数等，仅 DEBUG 使用。
    public static let motion = Logger(subsystem: "io.github.taliove.mivibe", category: "motion")
}
