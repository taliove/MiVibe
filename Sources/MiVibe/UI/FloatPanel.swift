import AppKit
import Combine
import MiVibeCore
import SwiftUI

// MARK: - 模型
//
// 状态文案与音频电平分成两个 ObservableObject：电平每秒更新约 66 次，若和文字共用
// 一个模型，横条上的两段文字会跟着球一起重绘。分开之后高频更新只碰球。

/// 浮条的状态与文案（低频，只在事件发生时变化）。
@MainActor
final class FloatPanelModel: ObservableObject {
    @Published var state: FloatState?
    @Published var message: String = ""
    /// 非 nil 时浮条渲染改写模式选单（优先级高于状态横条）。
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

/// 实时音量电平 0…1（高频，约 66 Hz），只被球观察。
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
/// 窗口本身在可见期间保持固定尺寸（取横条与当前选单高度的较大者），入场 / 退场 /
/// 横条↔选单的过渡全部在 SwiftUI 内容里做——`NSWindow` 改尺寸会卡顿（性能预算，
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

    private var shown: FloatState?
    private var shownMessage = ""
    private var dismissed = false
    private var autoHideTimer: Timer?
    private var orderOutTimer: Timer?

    init() {
        panel.contentView = NSHostingView(rootView: FloatBarView(model: model, level: level))
        panel.positionBottomCenter()
    }

    /// 推入实时音量 0…1。由音频回调以约 66 Hz 驱动。
    func setLevel(_ value: Double) {
        level.level = value
    }

    /// 更新状态并决定显示/隐藏。与 `Coordinator.float` 一一对应。
    func update(state: FloatState?, message: String) {
        // 同一状态重复上报（例如蓝牙连接状态也在变）时，若已经自动消失过就不要再
        // 弹回来——否则已输入/需处理会反复闪现。
        if state == shown, message == shownMessage, dismissed { return }

        autoHideTimer?.invalidate()
        autoHideTimer = nil
        orderOutTimer?.invalidate()
        orderOutTimer = nil
        shown = state
        shownMessage = message
        dismissed = false
        model.state = state
        model.message = message

        guard let state else {
            if model.picker == nil { hidePanel() }
            return
        }
        // 选单正在淡出时来了新状态：放弃淡出，直接换成横条显示新状态。
        if pickerPendingClear {
            pickerPendingClear = false
            model.picker = nil
        }

        showPanel()

        // 已输入在对勾画完后停留 1.6 秒收起（净可见时长与旧版 2 秒相当）；
        // 提示 2 秒收起；需处理要等用户动手，30 秒后收起（超时后菜单栏图标仍带
        // 角标，内容不会丢）。听音/转写/改写期间不自动消失。
        switch state {
        case .inserted:
            scheduleHide(after: MotionTiming.insertedHideDelay)
        case .notice:
            scheduleHide(after: MotionTiming.noticeHideDelay)
        case .attention:
            scheduleHide(after: MotionTiming.attentionHideDelay)
        case .listening, .transcribing, .polishing:
            break
        }
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
        } else if model.state == nil || dismissed {
            // 返回键 / 6 秒无操作关闭：没有要接着显示的状态时，选单**原样淡出**。
            // 先清 picker 会让退场那 0.24 s 里露出上一次的状态横条（真机反馈）。
            pickerPendingClear = true
            hidePanel()
        } else {
            // 确认切换：选单收回成横条，横条显示新的提示。
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

        if panel.isVisible, model.phase != .exiting {
            // 已可见：内容就地切换（球与文字各自做状态过渡），无需重新入场。
            return
        }
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

    /// 面板固定尺寸：取横条与当前选单（按实际条目数）高度的较大者。
    /// 可见期间不再 `setContentSize`，横条↔选单的过渡只动 SwiftUI 内容。
    private func fitPanelSize() {
        let pickerHeight = model.picker.map { ModePickerView.height(itemCount: $0.items.count) }
        let content = max(FloatSurface.barHeight, pickerHeight ?? 0)
        let height = content + FloatSurface.shadowInset * 2
        let size = NSSize(width: model.barWidth, height: height)
        if panel.frame.size != size { panel.setContentSize(size) }
    }

    private func hidePanel() {
        guard panel.isVisible, model.phase != .exiting else { return }
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
                    self.panel.orderOut(nil)
                    if self.pickerPendingClear {
                        self.pickerPendingClear = false
                        self.model.picker = nil
                    }
                }
            }
        }
    }

    /// 横条宽度：默认 560，至少留出两侧 24pt 边距。
    static func fittingBarWidth() -> CGFloat {
        let visible = NSScreen.main?.visibleFrame.width ?? 560
        return min(560, max(320, visible - 48))
    }

    private func scheduleHide(after seconds: TimeInterval) {
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.dismissed = true
                // 选单开着时不收：上一条提示的计时到点不能把用户正在用的选单关掉。
                guard self.model.picker == nil else { return }
                self.hidePanel()
            }
        }
    }
}

// MARK: - 横条

struct FloatBarView: View {
    @ObservedObject var model: FloatPanelModel
    @ObservedObject var level: AudioLevelModel
    /// 主题观察：主题切换时浮条与模式选单立刻重绘（值取自 BrandColorCurrent，
    /// 不观察则颜色对但不重算，见 Brand.swift 头注释）。
    @ObservedObject private var themeStore: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: FloatState { model.state ?? .listening }

    init(model: FloatPanelModel, level: AudioLevelModel) {
        self.model = model
        self.level = level
        self._themeStore = ObservedObject(wrappedValue: model.themeStore)
    }

    var body: some View {
        // 面板本身按最大宽度开、完全透明且不接收鼠标；可见的条按内容收缩并居中，
        // 短提示不再拖着一条大半空着的 560pt 横条。
        Group {
            if let picker = model.picker {
                ModePickerView(
                    picker: picker,
                    width: min(model.barWidth, 360),
                    generation: model.pickerGeneration,
                    confirmingItemID: model.confirmingPickerItemID,
                    reduceMotion: reduceMotion
                )
                .floatSurface(tint: nil, cornerRadius: FloatSurface.pickerCornerRadius)
            } else {
                HStack(spacing: 10) {
                    StatusBall(state: state, level: level.level, reduceMotion: reduceMotion)
                        .frame(width: 40, height: 40)

                    Text(state.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize()
                        .id(state)
                        .transition(reduceMotion ? .opacity : labelTransition)

                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .id(detail)
                            .transition(reduceMotion ? .opacity : labelTransition)
                    }
                }
                .padding(.leading, 4)
                .padding(.trailing, 16)
                .frame(height: FloatSurface.barHeight)
                .frame(maxWidth: model.barWidth - FloatSurface.shadowInset * 2)
                .fixedSize(horizontal: true, vertical: false)
                .floatSurface(tint: state.color, cornerRadius: FloatSurface.cornerRadius)
                .animation(Motion.quick, value: state)
            }
        }
        // 入场 / 出场位移、缩放、透明度的目标值（减弱动态效果时只淡入淡出）。
        // 驱动方式：相位写入总在 withAnimation 里（见控制器），这里只声明值。
        .opacity(phaseOpacity)
        .offset(y: phaseOffset)
        .scaleEffect(phaseScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 横条 ↔ 选单的内容切换用 standard（高度弹簧撑开 / 收回）。
        // 注意：相位过渡的动画由控制器侧的 withAnimation 给出，不在这里声明——
        // 否则状态的每次低频变化都会给 offset/opacity 套上弹簧。
        .animation(Motion.standard, value: model.picker != nil)
        .background(FloatUpdateCounter.probe())
    }

    private var phaseOpacity: Double {
        model.phase == .hidden ? 0 : 1
    }

    private var phaseOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        switch model.phase {
        case .visible: return 0
        case .exiting, .hidden: return 6
        }
    }

    private var phaseScale: CGFloat {
        guard !reduceMotion else { return 1 }
        switch model.phase {
        case .visible: return 1
        case .exiting: return 0.98
        case .hidden: return 0.96
        }
    }

    /// 文字过渡：旧文字上移 4pt 淡出，新文字从下方 4pt 淡入（quick 时长）。
    private var labelTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 4).combined(with: .opacity),
            removal: .offset(y: -4).combined(with: .opacity)
        )
    }

    /// 已输入只说"写好了"，不再把刚上屏的文字复述一遍。
    private var detail: String {
        if state == .inserted || model.message.isEmpty { return state.hint }
        return model.message
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

// MARK: - 表面
//
// 浮条盖在任意应用之上：深色终端、浅色文档、花哨网页都有。原先的 86% 纯黑条
// 在深色背景上几乎没有边界。改为系统毛玻璃（跟随浅色/深色外观）+ 发丝描边 +
// 状态色描边：底色随系统，描边保证在任何背景上都有清楚的轮廓，颜色同时说明状态。

enum FloatSurface {
    static let barHeight: CGFloat = 44
    static let cornerRadius: CGFloat = 22
    /// 模式选单的圆角（打开时从 22 变形到 16）。
    static let pickerCornerRadius: CGFloat = 16
    /// 给阴影留的透明边距（面板比可见的条大这么多）。
    static let shadowInset: CGFloat = 12
}

/// 窗口背后的实时模糊。SwiftUI 的 Material 在透明无边框面板里拿不到桌面内容，
/// 必须用 `.behindWindow` 的 NSVisualEffectView。
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct FloatSurfaceModifier: ViewModifier {
    let tint: Color?
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(BehindWindowBlur().clipShape(shape))
            .overlay(
                // 外圈：状态色（无状态时用中性发丝线），保证轮廓。
                shape.strokeBorder((tint ?? Color.primary).opacity(tint == nil ? 0.14 : 0.55), lineWidth: 1)
            )
            .overlay(
                // 内圈高光：让玻璃边缘在深色背景上也立得住。
                shape.inset(by: 1)
                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.08 : 0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.18), radius: 10, y: 4)
    }
}

private extension View {
    func floatSurface(tint: Color?, cornerRadius: CGFloat) -> some View {
        modifier(FloatSurfaceModifier(tint: tint, cornerRadius: cornerRadius))
    }
}

/// 改写模式选单：↑↓ 移动、确认选定、返回关闭。遥控器专属界面，浮条不抢焦点，
/// 所以这里没有任何可点元素——导航全部由按键路由完成。
///
/// 动效（epic #1 子任务 F）：打开时条目按 20 ms 交错淡入上移（首条延迟 60 ms）；
/// 高亮块是一块 `matchedGeometryEffect` 的填充，在行之间滑动而不是瞬跳；
/// 确认时高亮行闪亮一次（160 ms）。减弱动态效果时全部瞬切。
private struct ModePickerView: View {
    let picker: Coordinator.ModePickerState
    let width: CGFloat
    /// 打开代数：每次打开 +1，用来重置交错入场（`onAppear` 不换 id 不会重播）。
    let generation: Int
    /// 确认时闪亮的条目 id（消费一次，下一次打开时自动失效）。
    let confirmingItemID: String?
    let reduceMotion: Bool

    /// 高亮块的 matchedGeometry 命名空间。
    @Namespace private var highlightSpace
    /// 条目入场进度：0 = 未入场（透明 + 下移），1 = 到位。
    @State private var appeared = false
    /// 确认闪亮进度（0…1，160 ms）。
    @State private var flash: Double = 0

    /// 选单内容高度：条目 34 + 页脚 28 + 上下内边距 8。
    static func height(itemCount: Int) -> CGFloat {
        CGFloat(itemCount) * 34 + 28 + 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(picker.items.enumerated()), id: \.element.id) { index, item in
                let isHighlight = index == picker.highlight
                HStack(spacing: 8) {
                    Image(systemName: isHighlight ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isHighlight ? Color.brandOnAccentFill : Color.secondary)
                        .font(.system(size: 13))
                    Text(item.name)
                        .font(.system(size: 14, weight: isHighlight ? .semibold : .regular))
                        .foregroundStyle(isHighlight ? Color.brandOnAccentFill : Color.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background {
                    if isHighlight {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.brandAccentFill)
                            // 一块高亮块在行之间滑动（减弱动态效果时由系统转为瞬切）。
                            .matchedGeometryEffect(id: "highlight", in: highlightSpace)
                            .brightness(flash * 0.35)
                    }
                }
                .padding(.horizontal, 6)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 4)
                .animation(reduceMotion ? nil : Motion.quick.delay(0.06 + Double(index) * 0.02),
                           value: appeared)
            }
            Text("↑↓ 选择 · 确认键切换 · 返回键关闭")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .frame(height: 28)
                .opacity(appeared ? 1 : 0)
        }
        .padding(.vertical, 8)
        .frame(width: width)
        .animation(reduceMotion ? nil : Motion.standard, value: picker.highlight)
        .id(generation)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                appeared = false
                withAnimation { appeared = true }
            }
        }
        .onChange(of: confirmingItemID) { _, id in
            guard id != nil, !reduceMotion else { return }
            flash = 0
            withAnimation(Motion.instant) { flash = 1 }
            withAnimation(Motion.instant.delay(MotionTiming.pickerConfirmFlash)) { flash = 0 }
        }
    }
}
