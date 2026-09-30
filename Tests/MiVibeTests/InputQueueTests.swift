import Foundation
import MiVibeCore

/// 把交互原型的四个引导场景逐个变成测试——用户正是照那四个场景点完后确认的行为，
/// 所以它们是队列状态机的验收标准（07 票）。
enum InputQueueTests {
    static func run() {
        scenarioTwoSentences()
        scenarioTargetLost()
        scenarioFailureBlocks()
        scenarioCancelAndFull()
        boundaryRules()
    }

    /// 场景一「连续两句」：第一句转写时开始第二句；即使第二句先完成，
    /// 也要等第一句按顺序输入。
    static func scenarioTwoSentences() {
        Harness.suite("场景一：连续两句按说话顺序输入") {
            var q = InputQueue()
            guard case .started(let first) = q.startRecording() else {
                Harness.expect(false, "第一句应可开始"); return
            }
            q.finishRecording(id: first)
            guard case .started(let second) = q.startRecording() else {
                Harness.expect(false, "第一句转写中应允许开始第二句"); return
            }
            q.finishRecording(id: second)
            Harness.expectEqual(q.items.count, 2, "两句并存")

            // 第二句先完成，但队首仍是第一句 → 不得抢先输入
            q.transcriptionSucceeded(id: second, text: "第二句")
            Harness.expect(q.injectable == nil, "第二句先转写完也不能抢先输入")

            q.transcriptionSucceeded(id: first, text: "第一句")
            Harness.expectEqual(q.injectable?.text, "第一句", "队首可输入的是第一句")

            q.injected(id: first)
            Harness.expectEqual(q.injectable?.text, "第二句", "第一句输入后轮到第二句")
            q.injected(id: second)
            Harness.expect(q.items.isEmpty, "两句都输入后队列清空")
        }
    }

    /// 场景二「失焦恢复」：识别文字暂存，只有显式「输入到这里」才恢复。
    static func scenarioTargetLost() {
        Harness.suite("场景二：失焦暂存与显式恢复") {
            var q = InputQueue()
            guard case .started(let id) = q.startRecording() else { return }
            q.finishRecording(id: id)
            q.targetLost(id: id)                      // 转写途中切了目标
            q.transcriptionSucceeded(id: id, text: "落空的文字")

            Harness.expect(q.injectable == nil, "失焦后不自动输入")
            Harness.expect(q.hasBlocker, "失焦项构成阻塞，自动输入暂停")

            // 转写在失焦之后才回来：文字要能带进待处理项
            var q2 = InputQueue()
            guard case .started(let id2) = q2.startRecording() else { return }
            q2.finishRecording(id: id2)
            q2.transcriptionSucceeded(id: id2, text: "已有文字")
            q2.targetLost(id: id2)
            Harness.expectEqual(q2.pendingTexts, ["已有文字"], "待处理内容含暂存文字")

            q2.resume(id: id2)
            Harness.expectEqual(q2.injectable?.text, "已有文字", "「输入到这里」后可输入")
            q2.injected(id: id2)
            Harness.expect(q2.items.isEmpty, "恢复输入后出队")
        }
    }

    /// 场景三「失败阻塞」：第一句失败保留录音并阻塞顺序；重试成功后队列继续。
    static func scenarioFailureBlocks() {
        Harness.suite("场景三：失败阻塞与重试恢复") {
            var q = InputQueue()
            guard case .started(let first) = q.startRecording() else { return }
            q.finishRecording(id: first)
            q.transcriptionFailed(id: first)
            Harness.expect(q.hasBlocker, "第一句失败即阻塞")
            Harness.expectEqual(q.pendingTexts, [], "转写失败时只有录音，没有文字")

            guard case .started(let second) = q.startRecording() else {
                Harness.expect(false, "失败后仍可继续录音"); return
            }
            q.finishRecording(id: second)
            q.transcriptionSucceeded(id: second, text: "第二句")
            Harness.expect(q.injectable == nil, "前句未解决，第二句不得输入")

            q.retry(id: first)
            q.transcriptionSucceeded(id: first, text: "第一句")
            Harness.expect(!q.hasBlocker, "重试成功后阻塞解除")
            Harness.expectEqual(q.injectable?.text, "第一句", "按序先输入第一句")
            q.injected(id: first)
            Harness.expectEqual(q.injectable?.text, "第二句", "随后是第二句")
        }
    }

    /// 场景四「取消与队列满」：两条未完成时第三次录音被拒；
    /// 返回键取消最新活动项，不删除较早内容。
    static func scenarioCancelAndFull() {
        Harness.suite("场景四：队列满拒绝与返回键取消") {
            var q = InputQueue()
            guard case .started(let first) = q.startRecording() else { return }
            q.finishRecording(id: first)
            guard case .started(let second) = q.startRecording() else { return }

            Harness.expectEqual(q.startRecording(), .rejectedQueueFull, "第三句被拒（容量 2）")

            let cancelled = q.cancelNewestActive()
            Harness.expectEqual(cancelled, second, "返回键取消的是最新活动项")
            Harness.expectEqual(q.items.count, 1, "较早项未被删除")
            Harness.expectEqual(q.items.first?.id, first, "留下的是第一句")

            guard case .started = q.startRecording() else {
                Harness.expect(false, "取消后应能再次开始"); return
            }
            Harness.expect(true, "取消腾出容量后可再录")
        }
    }

    /// 原型未直接展示但已确认的边界：返回键不得误删待处理内容、退出显式取舍。
    static func boundaryRules() {
        Harness.suite("边界：返回键不碰待处理内容 / 退出显式取舍") {
            var q = InputQueue()
            guard case .started(let id) = q.startRecording() else { return }
            q.finishRecording(id: id)
            q.transcriptionSucceeded(id: id, text: "已转写待输入")
            q.targetLost(id: id)

            Harness.expect(q.newestActiveID == nil, "待处理项不是活动项")
            Harness.expectEqual(q.cancelNewestActive(), nil, "无活动项时返回键什么都不做")
            Harness.expectEqual(q.pendingTexts, ["已转写待输入"], "待处理文字仍在（未被返回键误删）")

            q.discardAll()
            Harness.expect(q.items.isEmpty, "退出选择丢弃后清空")

            // 注入失败保留文字
            var q2 = InputQueue()
            guard case .started(let id2) = q2.startRecording() else { return }
            q2.finishRecording(id: id2)
            q2.transcriptionSucceeded(id: id2, text: "注入失败的文字")
            q2.injectionFailed(id: id2, text: "注入失败的文字")
            Harness.expectEqual(q2.pendingTexts, ["注入失败的文字"], "注入失败保留文字")
            q2.resume(id: id2)
            Harness.expectEqual(q2.injectable?.text, "注入失败的文字", "可显式重新输入")
        }
    }
}

/// 空结果与卡死修复：空转写不得变成占位的「待处理」。
enum InputQueueEmptyResultTests {
    static func run() {
        Harness.suite("空转写直接出队，不阻塞后续") {
            var q = InputQueue()
            guard case .started(let first) = q.startRecording() else {
                Harness.expect(false, "应可开始"); return
            }
            q.finishRecording(id: first)
            q.transcriptionEmpty(id: first)
            Harness.expect(q.items.isEmpty, "空转写出队")
            Harness.expect(!q.hasBlocker, "不留阻塞项")

            guard case .started = q.startRecording(), case .started = q.startRecording() else {
                Harness.expect(false, "空转写不占容量：之后仍能连录两句"); return
            }
            Harness.expect(true, "空转写不占容量：之后仍能连录两句")
        }

        Harness.suite("空转写不越过前面的项") {
            var q = InputQueue()
            guard case .started(let first) = q.startRecording() else { return }
            q.finishRecording(id: first)
            guard case .started(let second) = q.startRecording() else { return }
            q.finishRecording(id: second)
            q.transcriptionEmpty(id: second)
            Harness.expectEqual(q.items.map(\.id), [first], "只移除空的那条，前一条原样保留")
            q.transcriptionEmpty(id: first)
            Harness.expect(q.items.isEmpty, "两条都空 → 队列清空")
        }

        Harness.suite("录音阶段也可直接判空") {
            var q = InputQueue()
            guard case .started(let id) = q.startRecording() else { return }
            q.transcriptionEmpty(id: id)
            Harness.expect(q.items.isEmpty, "按住未说话、松手即丢（不经转写）")
        }

        Harness.suite("已有文字的项不受判空影响") {
            var q = InputQueue()
            guard case .started(let id) = q.startRecording() else { return }
            q.finishRecording(id: id)
            q.transcriptionSucceeded(id: id, text: "你好")
            q.transcriptionEmpty(id: id)
            Harness.expectEqual(q.injectable?.text, "你好", "ready 项不会被误删")
        }

        Harness.suite("转写途中失焦：结果回来后补进占位项") {
            var q = InputQueue()
            guard case .started(let id) = q.startRecording() else { return }
            q.finishRecording(id: id)
            q.targetLost(id: id)
            q.transcriptionSucceeded(id: id, text: "迟到的文字")
            Harness.expectEqual(q.pendingTexts, ["迟到的文字"], "文字进入待处理，可「输入到这里」")
            q.resume(id: id)
            Harness.expectEqual(q.injectable?.text, "迟到的文字", "恢复后可输入")

            var q2 = InputQueue()
            guard case .started(let id2) = q2.startRecording() else { return }
            q2.finishRecording(id: id2)
            q2.targetLost(id: id2)
            q2.transcriptionEmpty(id: id2)
            Harness.expect(q2.items.isEmpty, "失焦占位 + 空转写 → 出队，不留无法恢复的阻塞")

            var q3 = InputQueue()
            guard case .started(let id3) = q3.startRecording() else { return }
            q3.finishRecording(id: id3)
            q3.targetLost(id: id3)
            q3.transcriptionFailed(id: id3)
            Harness.expectEqual(q3.items.first?.phase, .needsAttention(.transcriptionFailed),
                                "失焦占位 + 转写失败 → 转写失败（可重试）")
        }
    }
}
