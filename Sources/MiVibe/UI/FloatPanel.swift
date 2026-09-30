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
        model.picker = picker
        if picker != nil {
            if !wasOpen { model.pickerGeneration += 1 }
            showPanel()
        } else if model.state == nil || dismissed {
            hidePanel()
        }
    }

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
            self?.orderOutTimer = Timer.scheduledTimer(withTimeInterval: 0.26, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.model.phase == .hidden else { return }
                    self.panel.orderOut(nil)
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
                self.hidePanel()
                self.dismissed = true
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
            withAnimation(Motion.instant.delay(0.16)) { flash = 0 }
        }
    }
}

// MARK: - 球
//
// 同一颗球贯穿六态（epic #1 子任务 F）：听音 = 品牌三根声波随音量起伏，
// 松手 = 签名动作（声波收拢成点、展开成转写圆弧，420 ms），转写 = 圆弧旋转，
// 改写 = 白弧 + 四角星闪烁，已输入 = 合圈 + 对勾描线一次，需处理 = 轻晃一次 +
// 心跳三下后静止，提示 = 信息符号弹出。
//
// TimelineView 只包持续动画的状态：听音、签名、转写 / 改写、需处理的前 5 秒。
// 已输入 / 提示是一次性动画，播完不再逐帧重绘（性能预算：浮条静态时 0 帧）。
//
// 开启系统「减弱动态效果」时每态保留可辨认的静态图形，只做透明度 / 颜色变化。

struct StatusBall: View {
    let state: FloatState
    let level: Double
    let reduceMotion: Bool

    var body: some View {
        // 球直径 34：与品牌块的观感一致，状态色由调用方给定。
        switch state {
        case .listening:
            if reduceMotion {
                ListeningBallReduced(color: state.color, level: level)
            } else {
                TimelineView(.animation) { context in
                    ListeningBall(color: state.color, level: level,
                                  time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        case .transcribing, .polishing:
            if reduceMotion {
                TranscribingBallReduced(color: state.color, polishing: state == .polishing)
            } else {
                TimelineView(.animation) { context in
                    SignatureBall(color: state.color, polishing: state == .polishing,
                                  time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        case .inserted:
            InsertedBall(color: state.color, reduceMotion: reduceMotion)
        case .notice:
            NoticeBall(color: state.color, reduceMotion: reduceMotion)
        case .attention:
            if reduceMotion {
                AttentionBallReduced(color: state.color)
            } else {
                AttentionBall(color: state.color)
            }
        }
    }
}

/// 听音：主题色圆里三根白色声波柱（品牌标记比例 0.55 / 1.0 / 0.7），
/// 各自跟随音量起伏、彼此有相位差；安静（level ≤ 0.08）时用 0.5 Hz 呼吸代替，
/// 免得球在停顿处冻住、被读成"没在听"。每帧只改三根柱的缩放，不重新布局文字。
private struct ListeningBall: View {
    let color: Color
    let level: Double
    let time: Double

    var body: some View {
        let quiet = level <= MotionTiming.quietLevelThreshold
        // 安静呼吸：0.5 Hz，读数在 0.1…0.26 之间缓慢起伏。
        let amplitude = quiet ? 0.1 + 0.08 * (1 + sin(time * .pi * 2 * MotionTiming.quietBreathHz)) : level

        ZStack {
            Circle()
                .fill(Color(nsColor: .brandAccentFill))

            HStack(spacing: 2.6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule(style: .continuous)
                        .frame(width: 3.4, height: 16)
                        .scaleEffect(y: MotionTiming.barScale(
                            level: amplitude,
                            base: MotionTiming.barBases[index],
                            wobblePhase: time * 9 + Double(index) * 2.1))
                }
            }
            .foregroundStyle(Color.brandOnAccentFill)
        }
        .frame(width: 34, height: 34)
        .frame(width: 40, height: 40)
    }
}

/// 听音（减弱动态效果）：三根柱固定在中等高度，整体透明度随音量在 0.7…1 之间变化。
private struct ListeningBallReduced: View {
    let color: Color
    let level: Double

    var body: some View {
        ZStack {
            Circle().fill(Color(nsColor: .brandAccentFill))
            HStack(spacing: 2.6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule(style: .continuous)
                        .frame(width: 3.4, height: 16)
                        .scaleEffect(y: 0.22 + (0.7 * MotionTiming.barBases[index] + 0.1))
                }
            }
            .foregroundStyle(Color.brandOnAccentFill)
        }
        .frame(width: 34, height: 34)
        .frame(width: 40, height: 40)
        .opacity(0.7 + 0.3 * min(1, max(0, level)))
    }
}

/// 签名动作 + 转写 / 改写（motion-v1 时序图，以进入转写为 0）：
/// - 0–200 ms   三根声波向中心收拢、压扁到 0.16
/// - 140–260 ms 声波淡出
/// - 0–180 ms   球底从主题色褪到 18% 主题色
/// - 180–420 ms 圆弧画入（0 → 28%），同时开始以 1.2 s/圈 旋转
///
/// 进入转写时本视图才挂载，`onAppear` 记下起始时刻，时间轴由此对齐。
/// 改写：底色填满主题色、圆弧转白继续转，四角星 1.6 s 周期闪烁。
private struct SignatureBall: View {
    let color: Color
    let polishing: Bool
    let time: Double

    /// 进入转写态的时刻（AUDIO_STOP）。
    @State private var startedAt: Double?

    private var elapsed: Double {
        max(0, time - (startedAt ?? time))
    }

    var body: some View {
        let t = elapsed
        // 收拢进度 0…1（0–200 ms）；淡出 0…1（140–260 ms）；底色 0…1（0–180 ms）；
        // 画弧 0…1（180–420 ms，目标弧长 28%）。
        let converge = Self.progress(t, from: 0, to: MotionTiming.signatureBarsConverge)
        let fadeOut = Self.progress(t, from: 0.14, to: MotionTiming.signatureBarsGone)
        let fillFade = Self.progress(t, from: 0, to: MotionTiming.signatureArcStart)
        let arcDraw = Self.progress(t, from: MotionTiming.signatureArcStart,
                                    to: MotionTiming.signatureDuration)
        // 圆弧从 180 ms 起匀速旋转。
        let turn = max(0, t - MotionTiming.signatureArcStart)
            .truncatingRemainder(dividingBy: MotionTiming.spinPeriod) / MotionTiming.spinPeriod

        ZStack {
            Circle()
                .fill(polishing ? Color(nsColor: .brandAccentFill) : color.opacity(1 - 0.82 * fillFade))
                .animation(Motion.quick, value: polishing)

            // 声波三根：向中心收拢并压扁，随后淡出。
            HStack(spacing: 2.6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule(style: .continuous)
                        .frame(width: 3.4, height: 16)
                        .scaleEffect(y: 0.6 * (1 - converge) + 0.16 * converge)
                }
            }
            // 左右两根向中心平移收拢（中间一根不动）。
            .offset(x: 0)
            .opacity(1 - fadeOut)

            // 圆弧：18% 底色圆 + 28% 弧段旋转；改写时弧转白。
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(polishing ? Color.brandOnAccentFill : color,
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(-90 + turn * 360))
                .opacity(arcDraw)

            // 改写四角星：签名播完后淡入并闪烁。
            if polishing {
                FourPointStar()
                    .fill(Color.brandOnAccentFill)
                    .frame(width: 12, height: 12)
                    .scaleEffect(1 - 0.11 * (1 + sin(time * .pi * 2 / MotionTiming.twinklePeriod)))
                    .opacity(Self.progress(t, from: MotionTiming.signatureDuration,
                                           to: MotionTiming.signatureDuration + 0.18))
            }
        }
        .frame(width: 34, height: 34)
        .frame(width: 40, height: 40)
        .onAppear {
            if startedAt == nil { startedAt = time }
        }
    }

    /// 线性进度：时刻 t 落在 from…to 内的位置，两端截断。
    private static func progress(_ t: Double, from: Double, to: Double) -> Double {
        guard to > from else { return 1 }
        return min(1, max(0, (t - from) / (to - from)))
    }
}

/// 转写 / 改写（减弱动态效果）：静态 28% 圆弧，不旋转；改写多一颗静态四角星。
private struct TranscribingBallReduced: View {
    let color: Color
    let polishing: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(polishing ? color : color.opacity(0.18))
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(polishing ? Color.brandOnAccentFill : color,
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(-90))
            if polishing {
                FourPointStar()
                    .fill(Color.brandOnAccentFill)
                    .frame(width: 12, height: 12)
            }
        }
        .frame(width: 34, height: 34)
        .frame(width: 40, height: 40)
    }
}

/// 已输入：圆弧先合拢成整圈（200 ms）→ 底色变成功绿、圆弧淡出 → 对勾描线一次
/// （350 ms）。一次性动作才配得上"结束"，播完即静（不套 TimelineView）。
///
/// 对勾色用 `brandOnAccentFill`（浅色白 / 深色墨绿，不随主题变）：深色下成功色是
/// 亮绿 #3CC97D，白勾对比度只有约 2.1:1，墨绿勾约 8:1（spec C 验收的填充面对比规则）。
private struct InsertedBall: View {
    let color: Color
    let reduceMotion: Bool
    @State private var arcTrim: CGFloat = 0.28
    @State private var fillUp = false
    @State private var drawn: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(fillUp ? color : color.opacity(0.18))

            Circle()
                .trim(from: 0, to: arcTrim)
                .stroke(fillUp ? color.opacity(0) : color,
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(-90))

            CheckmarkShape()
                .trim(from: 0, to: drawn)
                .stroke(Color.brandOnAccentFill,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
        }
        .frame(width: 34, height: 34)
        .frame(width: 40, height: 40)
        .onAppear {
            if reduceMotion {
                // 减弱动态效果：对勾直接出现。
                arcTrim = 1
                fillUp = true
                drawn = 1
                return
            }
            arcTrim = 0.28
            fillUp = false
            drawn = 0
            withAnimation(.easeOut(duration: MotionTiming.arcCloseDuration)) { arcTrim = 1 }
            withAnimation(Motion.quick.delay(MotionTiming.arcCloseDuration)) { fillUp = true }
            withAnimation(Motion.draw.delay(MotionTiming.arcCloseDuration)) { drawn = 1 }
        }
    }
}

/// 提示：信息符号从 0.4 倍弹入（spring）。提示可能是"已切换模式"也可能是
/// "没听到内容"，不能借用已输入的对勾，否则"已忽略"会被读成"成功了"。
private struct NoticeBall: View {
    let color: Color
    let reduceMotion: Bool
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
            Image(systemName: "info")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .scaleEffect(appeared ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)
        }
        .frame(width: 34, height: 34)
        .frame(width: 40, height: 40)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                appeared = false
                withAnimation(Motion.standard) { appeared = true }
            }
        }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.84))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.minY + rect.height * 0.16))
        return path
    }
}

/// 四角星（改写的"打磨"记号）：上下左右四个尖角。
private struct FourPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        let arm = min(rect.width, rect.height) / 2
        let waist = arm * 0.28
        var path = Path()
        path.move(to: CGPoint(x: mid.x, y: mid.y - arm))
        path.addQuadCurve(to: CGPoint(x: mid.x + arm, y: mid.y),
                          control: CGPoint(x: mid.x + waist, y: mid.y - waist))
        path.addQuadCurve(to: CGPoint(x: mid.x, y: mid.y + arm),
                          control: CGPoint(x: mid.x + waist, y: mid.y + waist))
        path.addQuadCurve(to: CGPoint(x: mid.x - arm, y: mid.y),
                          control: CGPoint(x: mid.x - waist, y: mid.y + waist))
        path.addQuadCurve(to: CGPoint(x: mid.x, y: mid.y - arm),
                          control: CGPoint(x: mid.x - waist, y: mid.y - waist))
        return path
    }
}

/// 需处理：出现 220 ms 后横向轻晃一次（±4 pt，400 ms），同时小球以 1.4 s 周期
/// 心跳三下，之后静止。提醒到了就停，不一直敲你——TimelineView 只活到第 5 秒，
/// 之后换成静态副本，不再逐帧重绘。
private struct AttentionBall: View {
    let color: Color

    /// 状态出现时刻（以 TimelineView 的首帧近似）。
    @State private var startedAt: Double?
    /// 轻晃进度驱动（0…1，对应 400 ms）。
    @State private var shake: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60,
                                paused: (startedAt.map {
                                    $0 < Date.timeIntervalSinceReferenceDate - MotionTiming.attentionAnimateWindow
                                }) ?? false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let elapsed = startedAt.map { max(0, time - $0) } ?? 0
            content(elapsed: elapsed)
        }
        .offset(x: reduceShakeOffset)
        .onAppear {
            if startedAt == nil { startedAt = Date.timeIntervalSinceReferenceDate }
            // 220 ms 后晃一次（0 → −4 → 4 → −3 → 2 → 0 pt，400 ms）。
            shake = 0
            withAnimation(.easeOut(duration: MotionTiming.shakeDuration)
                .delay(MotionTiming.shakeDelay)) { shake = 1 }
        }
    }

    /// 球体：底色 20% + 感叹号，心跳三下后归静。
    private func content(elapsed: Double) -> some View {
        let beatIndex = elapsed / MotionTiming.heartbeatPeriod
        let phase = beatIndex.truncatingRemainder(dividingBy: 1)
        let beating = beatIndex < Double(MotionTiming.heartbeatCount)
        let scale = beating ? 1 + 0.16 * Self.beatPulse(phase) : 1

        return ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .scaleEffect(scale)
            ExclamationGlyph()
                .fill(color)
                .frame(width: 8, height: 14)
                .scaleEffect(scale)
        }
        .frame(width: 34, height: 34)
        .frame(width: 40, height: 40)
    }

    /// 单拍曲线：0–6% 起到 1，18% 回落，26% 再起到 0.86，44% 归 0（motion-v1 的
    /// beat 关键帧）。用几段平滑插值近似。
    private static func beatPulse(_ x: Double) -> Double {
        switch x {
        case ..<0.06: return x / 0.06
        case ..<0.18: return 1 - (x - 0.06) / 0.12
        case ..<0.26: return 0.86 * (x - 0.18) / 0.08
        case ..<0.44: return 0.86 * (1 - (x - 0.26) / 0.18)
        default: return 0
        }
    }

    /// 轻晃位移：0 → −4 → 4 → −3 → 2 → 0 pt。
    private var reduceShakeOffset: CGFloat {
        let x = shake
        let offsets: [(Double, Double)] = [(0, 0), (0.2, -4), (0.45, 4), (0.65, -3), (0.85, 2), (1, 0)]
        for i in 1..<offsets.count {
            if x <= offsets[i].0 {
                let (t0, v0) = offsets[i - 1]
                let (t1, v1) = offsets[i]
                let f = (x - t0) / (t1 - t0)
                return CGFloat(v0 + (v1 - v0) * f)
            }
        }
        return 0
    }
}

/// 需处理（减弱动态效果）：静态底色 + 感叹号，不晃不跳。
private struct AttentionBallReduced: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.2))
            ExclamationGlyph()
                .fill(color)
                .frame(width: 8, height: 14)
        }
        .frame(width: 34, height: 34)
        .frame(width: 40, height: 40)
    }
}

/// 感叹号符号：上竖下点（不用系统图标，与 motion-v1 的几何一致）。
private struct ExclamationGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let stemWidth = rect.width * 0.36
        let stemHeight = rect.height * 0.66
        path.addRoundedRect(
            in: CGRect(x: rect.midX - stemWidth / 2, y: rect.minY,
                       width: stemWidth, height: stemHeight),
            cornerSize: CGSize(width: stemWidth / 2, height: stemWidth / 2))
        let dot = rect.width * 0.4
        path.addEllipse(in: CGRect(x: rect.midX - dot / 2, y: rect.maxY - dot,
                                   width: dot, height: dot))
        return path
    }
}
