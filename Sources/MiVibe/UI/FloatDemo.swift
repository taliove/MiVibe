#if DEBUG
import Foundation
import MiVibeCore

/// 开发走查用的浮条脚本（MIVIBE_FLOAT_DEMO，仅 DEBUG）：不挂协调器、不连遥控器，
/// 直接驱动 `FloatPanelController`。
@MainActor
enum FloatDemo {
    /// 按相对间隔逐步排程：长延迟的 asyncAfter 会被系统合并定时器推迟，
    /// 按键按下 / 抬起之间 0.1 s 的真实节奏只能这样还原。
    static func runScript(_ script: [(Double, () -> Void)]) {
        func run(_ index: Int) {
            guard index < script.count else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + script[index].0) {
                MainActor.assumeIsolated { script[index].1() }
                run(index + 1)
            }
        }
        run(0)
    }

    /// 单条浮条轮播六态（MIVIBE_FLOAT_DEMO=1 / dark / light）。
    static func runCarousel(_ panel: FloatPanelController) {
        let steps: [(FloatState, String)] = [
            (.listening, ""), (.transcribing, ""), (.polishing, ""),
            (.inserted, ""), (.notice, "没有听到内容，已忽略"),
            (.attention, "焦点已改变，请选好输入框后点「输入到这里」"),
        ]
        let interval = Double(ProcessInfo.processInfo.environment["MIVIBE_FLOAT_DEMO_INTERVAL"] ?? "") ?? 2.5
        runScript(steps.enumerated().map { index, step in
            (index == 0 ? 0 : interval, {
                let kind: FloatEntry.Kind = step.0 == .notice ? .notice : .recording(1)
                panel.update(entries: [FloatEntry(kind: kind, state: step.0, message: step.1)])
                if step.0 == .listening { panel.setLevel(0.55) }
            })
        })
    }

    /// 复现「提示收起 → 打开选单 → 返回关闭 → 再次打开」（MIVIBE_FLOAT_DEMO=picker）。
    static func runPicker(_ panel: FloatPanelController) {
        let items = ["原文直出", "转录整理", "正式书面", "简洁"].enumerated().map {
            Coordinator.ModePickerState.Item(id: "m\($0.offset)", name: $0.element)
        }
        // 与真机同构：协调器每次变化（含遥控器按下 / 抬起）都先推浮条列表、再推选单。
        let notice = FloatEntry(kind: .notice, state: .notice, message: "已切换到：转录整理")
        var entries = [notice]
        var picker: Coordinator.ModePickerState?
        let refresh = {
            panel.update(entries: entries)
            panel.update(picker: picker)
        }
        runScript([
            (0.0, { refresh() }),
            (2.0, { entries = []; refresh() }),                                // 提示 2 s 到点收起
            (2.0, { picker = .init(items: items, highlight: 1); refresh() }),  // 菜单键按下
            (0.1, { picker = nil; refresh() }),                                // 几乎同时按下返回键
            (0.05, { refresh() }),                                             // 两键抬起（真机回归触发点）
            (0.05, { refresh() }),
            (3.0, { picker = .init(items: items, highlight: 0); refresh() }),  // 再按菜单键：必须可见
            (0.1, { refresh() }),
            (3.0, { picker = nil; refresh() }),
            (0.1, { refresh() }),
        ])
    }

    /// 两条录音交错（MIVIBE_FLOAT_DEMO=stack）：走真实的 `InputQueue` + `FloatBoard`，
    /// 收起计时与协调器完全同一条路径。
    static func runStack(_ panel: FloatPanelController) {
        var queue = InputQueue()
        let board = FloatBoard()
        board.onChange = { entries, shakes in
            panel.update(entries: entries)
            panel.update(shakeCount: shakes)
        }
        var ids: [Int] = []
        let start = {
            guard case .started(let id) = queue.startRecording() else {
                board.rejectQueueFull(queue: queue.items)   // 第三条：不加条，已有浮条晃一次
                return
            }
            ids.append(id)
            board.sync(queue.items)
            board.setMessage("豆包 · 转录整理", for: id)
            panel.setLevel(0.55)
        }
        runScript([
            (0.0, { start() }),                                                   // 第一句正在听
            (1.5, { queue.finishRecording(id: ids[0]); board.sync(queue.items); start() }),  // 第一句转写、第二句正在听
            (1.5, {
                queue.transcriptionSucceeded(id: ids[0], text: "一")
                board.setPolishing(true, for: ids[0], queue: queue.items)         // 第一句改写中
            }),
            (1.5, {
                board.setPolishing(false, for: ids[0], queue: queue.items)
                queue.injected(id: ids[0])
                board.inserted(id: ids[0], queue: queue.items)                    // 第一句已输入，1.6 s 后单独收起
            }),
            (0.6, { queue.finishRecording(id: ids[1]); board.sync(queue.items) }),  // 第二句转写，第一句仍停留
            (1.6, { board.notice("已切换到：简洁"); start() }),                    // 提示条 + 第三句正在听
            (1.2, { start() }),                                                   // 第四句：队列满被拒绝 → 晃动
            (1.2, {
                queue.finishRecording(id: ids[2])
                queue.transcriptionSucceeded(id: ids[1], text: "二")
                queue.targetLost(id: ids[1])
                board.sync(queue.items)                                           // 第二句需处理，第三句转写中
            }),
            (2.0, { start() }),                                                   // 再被拒绝一次 → 再晃
            (2.0, {
                queue.transcriptionSucceeded(id: ids[2], text: "三")
                queue.discard(id: ids[1])
                queue.injected(id: ids[2])
                board.inserted(id: ids[2], queue: queue.items)                    // 最后一条已输入，收起后整体退场
            }),
        ])
    }
}
#endif
