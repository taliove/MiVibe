import AppKit
import Combine
import MiVibeCore
import SwiftUI

// MARK: - 模型
//
// 状态文案与音频电平分成两个 ObservableObject：电平每秒更新约 66 次，若和文字共用
// 一个模型，横条上的两段文字会跟着球一起重绘。分开之后高频更新只碰球。

/// 浮条列表与选单（低频，只在事件发生时变化）。
@MainActor
final class FloatPanelModel: ObservableObject {
    /// 正在显示的浮条（提示条在上，录音条按录制先后、新句在下）。收起途中保留最后
    /// 一组内容，淡出时不闪空白；orderOut 后才清空。
    @Published var entries: [FloatEntry] = []
    /// 非 nil 时浮条渲染改写模式选单（优先级高于浮条列表）。
    @Published var picker: Coordinator.ModePickerState?
    /// 横条宽度：默认 560，窄屏（含刘海两侧可用区变小）时收紧，不溢出屏幕。
    @Published var barWidth: CGFloat = 560
    /// 面板显隐过渡的相位（入场 / 出场由 SwiftUI 动画驱动，窗口本身固定尺寸）。
    @Published var phase: FloatBarPhase = .hidden
    /// 模式选单打开的代数：每打开一次 +1，用于重置条目交错入场动画。
    @Published var pickerGeneration: Int = 0
    /// 确认键按下时闪亮的那一行的选单 id（Coordinator 在确认后关掉选单，
    /// 这里由选单视图自己在移除前消费一次）。
    @Published var confirmingPickerItemID: String?
    /// 晃动代数：第三条录音被拒绝时 +1，整组浮条做一次「需处理」轻晃。
    @Published var shakeGeneration: Int = 0
    /// 只观察不写入：主题切换时让浮条与选单立刻重绘（主题令牌经 BrandColorCurrent 读取，
    /// 值总是对的，但视图不观察 ThemeStore 就不会失效重算，见 Brand.swift 头注释）。
    let themeStore = AppDelegate.shared.themeStore
}

/// 面板显隐相位：hidden（不可见）→ visible（入场到位）→ exiting（收起动画中）。
/// 收起途中来了新状态即从当前位置反向回 visible，不会闪出空白帧。
enum FloatBarPhase {
    case hidden
    case visible
    case exiting
}

/// 实时音量电平 0…1（高频，约 66 Hz），只被正在听那一条的球观察。
@MainActor
final class AudioLevelModel: ObservableObject {
    @Published var level: Double = 0
}

// MARK: - 面板

/// 底部状态浮条：**不抢焦点**。
///
/// `.nonactivatingPanel` + `canBecomeKey/Main = false` + `ignoresMouseEvents` 三重保险，
/// 原型阶段已实测（浮条轮播期间在 TextEdit 打字不被打断）。这是"松手直接输入"能
/// 成立的前提：浮条一旦抢焦点，目标输入框就没了。**这三条是承重件，不要删。**
///
/// 窗口本身在可见期间保持固定尺寸（取「两条录音条 + 提示条」与当前选单高度的较大者），
/// 入场 / 退场 / 条目增减 / 浮条↔选单的过渡全部在 SwiftUI 内容里做——`NSWindow` 改尺寸会卡顿（性能预算，
/// motion-v1）。
final class FloatPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 56),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // 阴影由 SwiftUI 层画，避免 borderless 的方角阴影
        hidesOnDeactivate = false
        isMovable = false
        ignoresMouseEvents = true  // 纯状态显示，不接受点击
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.minY + 22 - FloatSurface.shadowInset))
    }
}

/// 浮条控制器：只建一次 hosting view，状态与电平通过 ObservableObject 推给视图。
///
/// 之前的写法是按值持有 content view、再调用它的方法改 `@State`——改的是副本，
/// 推不到 `NSHostingView` 里真正渲染的那一份。改成模型驱动后这类失联不会再出现。
@MainActor
final class FloatPanelController {
    private let panel = FloatPanel()
    private let model = FloatPanelModel()
    private let level = AudioLevelModel()

    /// 协调器最近一次推来的条目（可能为空）；`model.entries` 是屏上正在画的那一组。
    private var current: [FloatEntry] = []
    private var lastShakeCount = 0
    private var orderOutTimer: Timer?

    init() {
        panel.contentView = NSHostingView(rootView: FloatBarView(model: model, level: level))
        panel.positionBottomCenter()
    }

    /// 推入实时音量 0…1。由音频回调以约 66 Hz 驱动。
    func setLevel(_ value: Double) {
        level.level = value
    }

    /// 更新浮条列表并决定显示/隐藏。与 `Coordinator.floats` 一一对应；自动收起的
    /// 计时在 Core 的 `FloatStack`，到点时协调器推来的列表里就没有那一条了。
    func update(entries: [FloatEntry]) {
        // 协调器的例行刷新（蓝牙状态、按键回显也在变）：列表没变就什么都不做。
        guard entries != current else { return }
        current = entries
        // 注意：这里不取消 orderOutTimer。空列表的例行刷新若掐掉退场收尾，面板会以
        // 透明（phase = hidden）状态一直挂着，下一次选单就在它上面「隐形」打开
        // （真机反馈：按菜单键不出选单，按返回才闪一下）。退场只由 showPanel 打断。
        guard !entries.isEmpty else {
            // 最后一条收起：整块面板退场，退场期间保留最后一组内容，不闪空白。
            if model.picker == nil { hidePanel() }
            return
        }
        // 选单正在淡出时来了新条目：放弃淡出，直接换成浮条列表。
        if pickerPendingClear {
            pickerPendingClear = false
            model.picker = nil
        }
        let wasShowing = panel.isVisible && model.phase == .visible && !model.entries.isEmpty
        if wasShowing {
            // 已可见：条目增减走各自的过渡，留下的条原位不动。
            withAnimation(Motion.standard) { model.entries = entries }
        } else {
            // 首次入场 / 收起途中反向回场：整组随面板一起入场，不再单独播条目过渡。
            model.entries = entries
        }
        showPanel()
    }

    /// 第三条录音被拒绝：已有浮条做一次「需处理」轻晃（计数只增不减）。
    func update(shakeCount: Int) {
        guard shakeCount != lastShakeCount else { return }
        let grew = shakeCount > lastShakeCount
        lastShakeCount = shakeCount
        guard grew, !current.isEmpty, model.picker == nil else { return }
        model.shakeGeneration += 1
    }

    /// 模式选单开合。打开时浮条切换为选单界面（自动隐藏计时交给 Coordinator：
    /// 选单的 6 秒无操作关闭由那边统一管理）。
    func update(picker: Coordinator.ModePickerState?) {
        let wasOpen = model.picker != nil
        if let picker {
            pickerPendingClear = false
            model.picker = picker
            if !wasOpen { model.pickerGeneration += 1 }
            showPanel()
        } else if !wasOpen || pickerPendingClear {
            return
        } else if current.isEmpty {
            // 返回键 / 6 秒无操作关闭：没有要接着显示的浮条时，选单**原样淡出**。
            // 先清 picker 会让退场那 0.24 s 里露出上一次的浮条（真机反馈）。
            pickerPendingClear = true
            hidePanel()
        } else {
            // 确认切换或还有录音在进行：选单收回成当前的浮条列表。
            model.entries = current
            model.picker = nil
        }
    }

    /// 选单正在淡出、等 orderOut 后再清空（见 `update(picker:)`）。
    private var pickerPendingClear = false

    /// 确认键按下：先让高亮行闪亮一下（由选单视图在移除前消费），再交给
    /// Coordinator 关闭选单。闪亮与关闭之间由 Coordinator 的消息节奏衔接。
    func flashPickerConfirm() {
        guard let picker = model.picker, picker.items.indices.contains(picker.highlight) else { return }
        model.confirmingPickerItemID = picker.items[picker.highlight].id
    }

    private func showPanel() {
        model.barWidth = Self.fittingBarWidth()
        fitPanelSize()
        panel.positionBottomCenter()

        // 要显示新内容：打断正在进行的退场收尾，别让它到点把面板 orderOut。
        orderOutTimer?.invalidate()
        orderOutTimer = nil

        if panel.isVisible, model.phase == .visible {
            // 已可见：内容就地切换（球与文字各自做状态过渡），无需重新入场。
            return
        }
        // exiting：收起途中反向回场。hidden 但面板仍在屏上（退场收尾未执行）：
        // 按首次入场处理，否则内容停在透明态，看起来像没打开。
        let reentering = model.phase == .exiting
        if !panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        // 入场（或收起途中的反向回场）：从下方 10pt、0.96、透明弹回 identity。
        // 反向回场时相位保持 exiting 的当前动画值，withAnimation 从该值反向，
        // 画面连续（AC6：无空白帧）；正常入场先渲染一帧 hidden 初值再推相位。
        if reentering {
            withAnimation(Motion.standard) {
                model.phase = .visible
            }
        } else {
            // 首次入场：先渲染 hidden 初值的一帧，再在动画里推 visible，
            // 入场弹簧（10pt / 0.96 / 透明 → identity）才播得出来。
            DispatchQueue.main.async { [model] in
                withAnimation(Motion.standard) {
                    model.phase = .visible
                }
            }
        }
    }

    /// 面板固定尺寸：取「两条录音条 + 提示条」与当前选单（按实际条目数）高度的较大者。
    /// 可见期间不再 `setContentSize`，条目增减与浮条↔选单的过渡只动 SwiftUI 内容。
    private func fitPanelSize() {
        let pickerHeight = model.picker.map { ModePickerView.height(itemCount: $0.items.count) }
        let content = max(FloatBarView.stackHeight, pickerHeight ?? 0)
        let height = content + FloatSurface.shadowInset * 2
        let size = NSSize(width: model.barWidth, height: height)
        if panel.frame.size != size { panel.setContentSize(size) }
    }

    private func hidePanel() {
        guard panel.isVisible, model.phase != .exiting else { return }
        // 已淡到透明：不再重播退场（exiting 的不透明度是 1，会闪一下）。
        // 收尾定时器还在就等它；没有了（不该发生）就直接收掉。
        if model.phase == .hidden {
            if orderOutTimer == nil { finishOrderOut() }
            return
        }
        // 先记相位，下一帧再推 hidden：视图先渲染 visible 值，withAnimation 才有
        // 起点可播（exit 0.24 s）。
        model.phase = .exiting
        DispatchQueue.main.async { [model, weak self] in
            withAnimation(Motion.exit) {
                model.phase = .hidden
            }
            // withAnimation 的 completion 回调在 macOS 14 上对隐式事务不可靠，
            // 用与 Motion.exit 等长的定时器兜底：到点才真正 orderOut。
            // 中途来新状态时相位会被打断回 visible，到点检查发现不是 hidden 就放弃。
            self?.orderOutTimer?.invalidate()
            self?.orderOutTimer = Timer.scheduledTimer(withTimeInterval: MotionTiming.exitSettle, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.model.phase == .hidden else { return }
                    self.finishOrderOut()
                }
            }
        }
    }

    /// 退场收尾：真正移出屏幕，并清掉等待淡出完成的选单内容。
    private func finishOrderOut() {
        orderOutTimer?.invalidate()
        orderOutTimer = nil
        panel.orderOut(nil)
        if pickerPendingClear {
            pickerPendingClear = false
            model.picker = nil
        }
        // 屏上已空：清掉退场期间保留的旧内容，下一次入场只画新条目。
        if current.isEmpty { model.entries = [] }
    }

    /// 横条宽度：默认 560，至少留出两侧 24pt 边距。
    static func fittingBarWidth() -> CGFloat {
        let visible = NSScreen.main?.visibleFrame.width ?? 560
        return min(560, max(320, visible - 48))
    }
}

// MARK: - 更新计数（DEBUG）

/// DEBUG 专用的浮条视图更新计数器：每次 `FloatBarView.body` 求值 +1，
/// 隐藏期间应为 0 帧（性能预算 AC3）。用 `log show --predicate
/// 'subsystem == "io.github.taliove.mivibe" && category == "motion"' --debug` 观察，
/// 或读取 `FloatUpdateCounter.count`。Release 构建整段编出，零开销。
enum FloatUpdateCounter {
    #if DEBUG
    @MainActor static private(set) var count = 0
    @MainActor static private var lastLogAt: CFAbsoluteTime = 0

    @MainActor
    static func note() {
        count += 1
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastLogAt >= 1 {
            Log.motion.debug("float view updates: \(count)（累计）")
            lastLogAt = now
        }
    }

    @MainActor
    static func reset() { count = 0 }

    @MainActor
    static func probe() -> some View {
        note()
        return EmptyView()
    }
    #else
    @MainActor
    static func probe() -> some View { EmptyView() }
    #endif
}
