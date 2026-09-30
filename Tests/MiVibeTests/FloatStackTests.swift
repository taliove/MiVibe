import Foundation
import MiVibeCore

/// 多条浮条的推导规则（SPEC §13，issue #3）：一条录音一条浮条，最多两条，新句在下；
/// 提示条单独一条、新的替换旧的；第三条被拒绝只晃不加。
enum FloatStackTests {
    static func run() {
        interleavings()
        insertedCollapse()
        attentionAndRetry()
        cancelAndDropEmpty()
        noticeRules()
        queueFull()
        capAndOrdering()
    }

    private typealias Entry = FloatEntry

    /// 列表摘要：[(种类, 状态)]，便于一行断言。
    private static func summary(_ entries: [Entry]) -> [String] {
        entries.map { entry in
            switch entry.kind {
            case .recording(let id): return "#\(id):\(entry.state.rawValue)"
            case .notice: return "notice:\(entry.state.rawValue)"
            }
        }
    }

    private static func start(_ q: inout InputQueue) -> Int {
        guard case .started(let id) = q.startRecording() else { return -1 }
        return id
    }

    static func interleavings() {
        Harness.suite("浮条：两条录音交错") {
            var q = InputQueue()
            var s = FloatStack()
            let first = start(&q)
            s.sync(queue: q.items, now: 0)
            Harness.expectEqual(summary(s.entries(now: 0)), ["#\(first):listening"], "第一句正在听")

            q.finishRecording(id: first)
            let second = start(&q)
            s.sync(queue: q.items, now: 1)
            Harness.expectEqual(summary(s.entries(now: 1)),
                                ["#\(first):transcribing", "#\(second):listening"],
                                "第一句转写中、第二句正在听：两条，新句在下")

            q.finishRecording(id: second)
            q.transcriptionSucceeded(id: second, text: "二")
            s.sync(queue: q.items, now: 2)
            let entries = s.entries(now: 2)
            Harness.expectEqual(summary(entries),
                                ["#\(first):transcribing", "#\(second):transcribing"],
                                "第二句先转写完仍显示进行中（等前一句）")
            Harness.expect(entries.last?.message.isEmpty == false, "等待中的后句带「等前一句」文案")

            q.transcriptionSucceeded(id: first, text: "一")
            s.setPolishing(true, for: first)
            s.sync(queue: q.items, now: 3)
            Harness.expectEqual(summary(s.entries(now: 3)),
                                ["#\(first):polishing", "#\(second):transcribing"],
                                "第一句改写中只影响第一条")

            s.setPolishing(false, for: first)
            q.injected(id: first)
            s.sync(queue: q.items, now: 4)
            s.markInserted(id: first, now: 4)
            Harness.expectEqual(summary(s.entries(now: 4)),
                                ["#\(first):inserted", "#\(second):transcribing"],
                                "第一句已输入、第二句转写中")
        }
    }

    static func insertedCollapse() {
        Harness.suite("浮条：已输入单独收起，另一条原位保留") {
            var q = InputQueue()
            var s = FloatStack()
            let first = start(&q)
            q.finishRecording(id: first)
            let second = start(&q)
            s.sync(queue: q.items, now: 0)
            s.setMessage("豆包 · 原文直出", for: second)

            q.transcriptionSucceeded(id: first, text: "一")
            q.injected(id: first)
            s.sync(queue: q.items, now: 10)
            s.markInserted(id: first, now: 10)

            let delay = MotionTiming.insertedHideDelay
            Harness.expectEqual(s.nextDeadline(after: 10), 10 + delay, "下一次刷新在 1.6 s 后")
            Harness.expectEqual(summary(s.entries(now: 10 + delay - 0.01)),
                                ["#\(first):inserted", "#\(second):listening"],
                                "1.6 s 内已输入与正在听并存")
            let after = s.entries(now: 10 + delay)
            Harness.expectEqual(summary(after), ["#\(second):listening"], "到点只收已输入那条")
            Harness.expectEqual(after.first?.message, "豆包 · 原文直出", "另一条文案不变")

            // 期间队列再变化（第二句松手）：已输入那条仍保留到点，不被提前移除。
            q.finishRecording(id: second)
            s.sync(queue: q.items, now: 11)
            Harness.expectEqual(summary(s.entries(now: 11)),
                                ["#\(first):inserted", "#\(second):transcribing"],
                                "队列变化不影响已输入条的停留")
            Harness.expect(s.entries(now: 11).last?.message.isEmpty == true,
                           "换状态后回到默认文案（听音文案不带进转写）")
            s.sync(queue: q.items, now: 12)
            Harness.expectEqual(summary(s.entries(now: 12)), ["#\(second):transcribing"],
                                "到点后的 sync 清掉已输入条")
            Harness.expectEqual(s.nextDeadline(after: 12), nil, "只剩进行中的条，无需定时刷新")
        }
    }

    static func attentionAndRetry() {
        Harness.suite("浮条：需处理与重试") {
            var q = InputQueue()
            var s = FloatStack()
            let first = start(&q)
            q.finishRecording(id: first)
            let second = start(&q)
            q.finishRecording(id: second)
            q.transcriptionFailed(id: first)
            s.sync(queue: q.items, now: 0)
            s.setMessage("转写超时（10 秒），可在菜单里重试", for: first)
            let entries = s.entries(now: 0)
            Harness.expectEqual(summary(entries),
                                ["#\(first):attention", "#\(second):transcribing"],
                                "第一句需处理、第二句转写中")
            Harness.expectEqual(entries.first?.message, "转写超时（10 秒），可在菜单里重试", "需处理带具体原因")

            // 第一句需处理，第二句已输入（例如用户先恢复了第二句）：各自独立。
            q.transcriptionSucceeded(id: second, text: "二")
            q.injected(id: second)
            s.sync(queue: q.items, now: 1)
            s.markInserted(id: second, now: 1)
            Harness.expectEqual(summary(s.entries(now: 1)),
                                ["#\(first):attention", "#\(second):inserted"],
                                "第一句需处理、第二句已输入")

            // 需处理 30 s 后收起，但内容还在队列里。
            let hide = MotionTiming.attentionHideDelay
            Harness.expectEqual(summary(s.entries(now: hide)), [], "需处理超时收起")
            s.sync(queue: q.items, now: hide + 1)
            Harness.expectEqual(summary(s.entries(now: hide + 1)), [], "状态未变的 sync 不会让它重新弹出")

            // 重试：回到转写中，重新可见。
            q.retry(id: first)
            s.sync(queue: q.items, now: hide + 2)
            let retried = s.entries(now: hide + 2)
            Harness.expectEqual(summary(retried), ["#\(first):transcribing"], "重试后回到转写中")
            Harness.expect(retried.first?.message.isEmpty == true, "重试后不再显示失败原因")
        }
    }

    static func cancelAndDropEmpty() {
        Harness.suite("浮条：取消最新与空录音") {
            var q = InputQueue()
            var s = FloatStack()
            let first = start(&q)
            q.finishRecording(id: first)
            let second = start(&q)
            s.sync(queue: q.items, now: 0)
            q.cancelNewestActive()
            s.sync(queue: q.items, now: 1)
            Harness.expectEqual(summary(s.entries(now: 1)), ["#\(first):transcribing"],
                                "返回键取消最新：只移除第二条")
            _ = second

            q.transcriptionEmpty(id: first)
            s.sync(queue: q.items, now: 2)
            s.postNotice("没有听到内容，已忽略", now: 2)
            let entries = s.entries(now: 2)
            Harness.expectEqual(summary(entries), ["notice:notice"], "空录音出队 → 录音条消失，只剩提示条")
            Harness.expectEqual(entries.first?.message, "没有听到内容，已忽略", "提示文案")
        }
    }

    static func noticeRules() {
        Harness.suite("浮条：提示条") {
            var q = InputQueue()
            var s = FloatStack()
            let first = start(&q)
            s.sync(queue: q.items, now: 0)
            s.postNotice("已切换到：转录整理", now: 0)
            Harness.expectEqual(summary(s.entries(now: 0)), ["notice:notice", "#\(first):listening"],
                                "提示条不挤占录音条，排在最上")
            s.postNotice("按键接管失败：缺少输入监控，已退回仅监听", attention: true, now: 1)
            let replaced = s.entries(now: 1)
            Harness.expectEqual(summary(replaced), ["notice:attention", "#\(first):listening"],
                                "新提示替换旧提示，至多一条")
            Harness.expectEqual(replaced.first?.message, "按键接管失败：缺少输入监控，已退回仅监听", "替换后文案")

            s.postNotice("已切换到：简洁", now: 2)
            let noticeHide = MotionTiming.noticeHideDelay
            Harness.expectEqual(s.nextDeadline(after: 2), 2 + noticeHide, "提示 2 s 后刷新")
            Harness.expectEqual(summary(s.entries(now: 2 + noticeHide)), ["#\(first):listening"],
                                "提示到点收起，录音条保留")
            s.sync(queue: q.items, now: 2 + noticeHide)
            Harness.expectEqual(s.nextDeadline(after: 2 + noticeHide), nil, "收起后的提示不再排刷新")
        }
    }

    static func queueFull() {
        Harness.suite("浮条：第三条录音被拒绝") {
            var q = InputQueue()
            var s = FloatStack()
            let first = start(&q)
            q.finishRecording(id: first)
            q.transcriptionFailed(id: first)
            let second = start(&q)
            q.finishRecording(id: second)
            s.sync(queue: q.items, now: 0)
            Harness.expectEqual(q.startRecording(), .rejectedQueueFull, "队列已满")
            let before = s.shakeCount
            s.rejectQueueFull(now: 1)
            s.sync(queue: q.items, now: 1)
            Harness.expectEqual(s.shakeCount, before + 1, "拒绝一次 → 晃一次")
            Harness.expectEqual(summary(s.entries(now: 1)),
                                ["#\(first):attention", "#\(second):transcribing"],
                                "不新增浮条")

            // 需处理已超时收起时被拒绝：重新露出来，让用户看到是什么占着队列。
            let late = MotionTiming.attentionHideDelay + 5
            Harness.expectEqual(summary(s.entries(now: late)), ["#\(second):transcribing"], "需处理已收起")
            s.rejectQueueFull(now: late)
            Harness.expectEqual(summary(s.entries(now: late)),
                                ["#\(first):attention", "#\(second):transcribing"],
                                "拒绝时收起的需处理条重新出现")
        }
    }

    static func capAndOrdering() {
        Harness.suite("浮条：上限与顺序") {
            var q = InputQueue()
            var s = FloatStack()
            let first = start(&q)
            q.finishRecording(id: first)
            q.transcriptionSucceeded(id: first, text: "一")
            q.injected(id: first)
            s.sync(queue: q.items, now: 0)
            s.markInserted(id: first, now: 0)
            // 第一句已输入还没收起，又连说两句：录音条仍至多两条，先让出已输入条。
            let second = start(&q)
            q.finishRecording(id: second)
            let third = start(&q)
            s.sync(queue: q.items, now: 0.5)
            s.postNotice("已切换到：简洁", now: 0.5)
            let entries = s.entries(now: 0.5)
            Harness.expectEqual(summary(entries),
                                ["notice:notice", "#\(second):transcribing", "#\(third):listening"],
                                "录音条上限 2，按录制先后，新句在下")
            Harness.expectEqual(entries.filter { $0.kind != .notice }.count, FloatStack.maxRecordingBars,
                                "上限与队列容量一致")
            Harness.expectEqual(Set(entries.map(\.id)).count, entries.count, "条目 id 唯一")
            Harness.expectEqual(FloatEntry(kind: .recording(7), state: .listening, message: "").id,
                                "recording-7", "录音条 id 随队列项稳定")
        }
    }
}
