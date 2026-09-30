import Foundation
import MiVibeCore

/// 浮条列表的簿记（SPEC §13）：持有纯模型 `FloatStack`，负责取时钟、到点刷新，
/// 并把此刻应显示的条目交给协调器发布。推导规则全部在 `FloatStack`（MiVibeCore，
/// 有测试）；这里只有副作用：单调时钟与一个到点刷新的定时器。
///
/// 调用约定：队列每次变化后调 `sync`；需要覆盖文案时在 `sync` 之后调 `setMessage`。
@MainActor
final class FloatBoard {
    private var stack = FloatStack()
    private var refreshTimer: Timer?

    /// 条目或晃动计数变化时回调（协调器据此更新 @Published 属性）。
    var onChange: (([FloatEntry], Int) -> Void)?

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    /// 按队列推导录音条。
    func sync(_ items: [InputQueue.Item]) {
        stack.sync(queue: items, now: now)
        publish()
    }

    /// 给某条录音的当前状态指定文案。
    func setMessage(_ message: String, for id: Int) {
        stack.setMessage(message, for: id)
        publish()
    }

    /// 改写开始 / 结束，并按队列刷新。
    func setPolishing(_ on: Bool, for id: Int, queue items: [InputQueue.Item]) {
        stack.setPolishing(on, for: id)
        sync(items)
    }

    /// 某条已写入并出队：先按队列推导，再把它标成已输入（1.6 s 后单独收起）。
    func inserted(id: Int, queue items: [InputQueue.Item]) {
        stack.sync(queue: items, now: now)
        stack.markInserted(id: id, now: now)
        publish()
    }

    /// 不属于任何录音的提示，替换现有提示条。
    func notice(_ message: String, attention: Bool = false) {
        stack.postNotice(message, attention: attention, now: now)
        publish()
    }

    /// 第三条录音被拒绝：已有浮条晃一次，不新增条目。
    func rejectQueueFull(queue items: [InputQueue.Item]) {
        stack.rejectQueueFull(now: now)
        sync(items)
    }

    private func publish() {
        let current = now
        onChange?(stack.entries(now: current), stack.shakeCount)
        scheduleRefresh(after: current)
    }

    /// 下一条到点收起时重新发布一次（只重算显示，不改模型）。
    private func scheduleRefresh(after current: Double) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard let deadline = stack.nextDeadline(after: current) else { return }
        // 多留 10 ms，保证到点时 `entries(now:)` 一定判为过期。
        let interval = max(0.01, deadline - current + 0.01)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.publish() }
        }
    }
}
