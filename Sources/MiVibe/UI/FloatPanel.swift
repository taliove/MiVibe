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
    private var hideTimer: Timer?

    init() {
        panel.contentView = NSHostingView(rootView: FloatBarView(model: model, level: level))
        panel.positionBottomCenter()
    }

    #if DEBUG
    /// 开发走查：强制浅色/深色外观（nil 跟随系统）。
    func debugForceAppearance(_ name: NSAppearance.Name?) {
        panel.appearance = name.flatMap(NSAppearance.init(named:))
    }
    #endif

    /// 推入实时音量 0…1。由音频回调以约 66 Hz 驱动。
    func setLevel(_ value: Double) {
        level.level = value
    }

    /// 更新状态并决定显示/隐藏。与 `Coordinator.float` 一一对应。
    func update(state: FloatState?, message: String) {
        // 同一状态重复上报（例如蓝牙连接状态也在变）时，若已经自动消失过就不要再
        // 弹回来——否则已输入/需处理会反复闪现。
        if state == shown, message == shownMessage, dismissed { return }

        hideTimer?.invalidate()
        hideTimer = nil
        shown = state
        shownMessage = message
        dismissed = false
        model.state = state
        model.message = message

        guard let state else {
            if model.picker == nil { panel.orderOut(nil) }
            return
        }

        showPanel()

        // 已输入/提示是一次完成，2 秒收起；需处理要等用户动手，30 秒后收起（超时后
        // 菜单栏图标仍带角标，内容不会丢）。听音/转写/改写期间不自动消失。
        switch state {
        case .inserted, .notice:
            scheduleHide(after: 2.0)
        case .attention:
            scheduleHide(after: 30.0)
        case .listening, .transcribing, .polishing:
            break
        }
    }

    /// 模式选单开合。打开时浮条切换为选单界面（自动隐藏计时交给 Coordinator：
    /// 选单的 6 秒无操作关闭由那边统一管理）。
    func update(picker: Coordinator.ModePickerState?) {
        model.picker = picker
        if picker != nil {
            showPanel()
        } else if model.state == nil || dismissed {
            panel.orderOut(nil)
        }
    }

    private func showPanel() {
        // 选单比状态横条高：按条目数撑开。宽度跟随屏幕可用区，窄屏不溢出。
        let content: CGFloat = model.picker.map { CGFloat($0.items.count) * 34 + 44 } ?? FloatSurface.barHeight
        let height = content + FloatSurface.shadowInset * 2
        model.barWidth = Self.fittingBarWidth()
        panel.setContentSize(NSSize(width: model.barWidth, height: height))
        panel.positionBottomCenter()
        panel.orderFrontRegardless()
    }

    /// 横条宽度：默认 560，至少留出两侧 24pt 边距。
    static func fittingBarWidth() -> CGFloat {
        let visible = NSScreen.main?.visibleFrame.width ?? 560
        return min(560, max(320, visible - 48))
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.panel.orderOut(nil)
                self.dismissed = true
            }
        }
    }
}

// MARK: - 横条

struct FloatBarView: View {
    @ObservedObject var model: FloatPanelModel
    @ObservedObject var level: AudioLevelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: FloatState { model.state ?? .listening }

    var body: some View {
        // 面板本身按最大宽度开、完全透明且不接收鼠标；可见的条按内容收缩并居中，
        // 短提示不再拖着一条大半空着的 560pt 横条。
        Group {
            if let picker = model.picker {
                ModePickerView(picker: picker, width: min(model.barWidth, 360))
                    .floatSurface(tint: nil)
            } else {
                HStack(spacing: 10) {
                    StatusBall(state: state, level: level.level, reduceMotion: reduceMotion)
                        .frame(width: 40, height: 40)

                    Text(state.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize()

                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.leading, 4)
                .padding(.trailing, 16)
                .frame(height: FloatSurface.barHeight)
                .frame(maxWidth: model.barWidth - FloatSurface.shadowInset * 2)
                .fixedSize(horizontal: true, vertical: false)
                .floatSurface(tint: state.color)
                .animation(.easeOut(duration: 0.18), value: state)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 已输入只说"写好了"，不再把刚上屏的文字复述一遍。
    private var detail: String {
        if state == .inserted || model.message.isEmpty { return state.hint }
        return model.message
    }
}

// MARK: - 表面
//
// 浮条盖在任意应用之上：深色终端、浅色文档、花哨网页都有。原先的 86% 纯黑条
// 在深色背景上几乎没有边界。改为系统毛玻璃（跟随浅色/深色外观）+ 发丝描边 +
// 状态色描边：底色随系统，描边保证在任何背景上都有清楚的轮廓，颜色同时说明状态。

enum FloatSurface {
    static let barHeight: CGFloat = 44
    static let cornerRadius: CGFloat = 22
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
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: FloatSurface.cornerRadius, style: .continuous)
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
    func floatSurface(tint: Color?) -> some View {
        modifier(FloatSurfaceModifier(tint: tint))
    }
}

/// 改写模式选单：↑↓ 移动、确认选定、返回关闭。遥控器专属界面，浮条不抢焦点，
/// 所以这里没有任何可点元素——导航全部由按键路由完成。
private struct ModePickerView: View {
    let picker: Coordinator.ModePickerState
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(picker.items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 8) {
                    Image(systemName: index == picker.highlight ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(index == picker.highlight ? Color.white : Color.secondary)
                        .font(.system(size: 13))
                    Text(item.name)
                        .font(.system(size: 14, weight: index == picker.highlight ? .semibold : .regular))
                        .foregroundStyle(index == picker.highlight ? Color.white : Color.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(index == picker.highlight ? Color.accentColor : .clear)
                )
                .padding(.horizontal, 6)
            }
            Text("↑↓ 选择 · 确认键切换 · 返回键关闭")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .frame(height: 28)
        }
        .padding(.vertical, 8)
        .frame(width: width)
    }
}

// MARK: - 球
//
// 同一个球贯穿四态，动作不同：听音=随音量脉冲 + 放射声波，转写=圆弧旋转，
// 已输入=画出对勾，需处理=双拍心跳（随时间衰减）。
//
// 开启系统「减弱动态效果」时退化为静态球：循环动画（旋转、声波、心跳）全部去掉，
// 只剩随音量的胀缩——那是信息，不是装饰。

struct StatusBall: View {
    let state: FloatState
    let level: Double
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            ZStack {
                Circle()
                    .fill(state.color)
                    .frame(width: 15, height: 15)
            }
            .frame(width: 40, height: 40)
        } else {
            TimelineView(.animation) { context in
                // 用绝对时间驱动，状态切换时动画不会从头跳一下。
                let time = context.date.timeIntervalSinceReferenceDate
                switch state {
                case .listening:
                    ListeningBall(color: state.color, level: level, time: time)
                case .transcribing, .polishing:
                    TranscribingBall(color: state.color, time: time)
                case .inserted:
                    InsertedBall(color: state.color)
                case .notice:
                    NoticeBall(color: state.color)
                case .attention:
                    AttentionBall(color: state.color, time: time)
                }
            }
        }
    }
}

/// 听音：球随音量胀缩，外面 12 根放射短线随同一读数伸缩。
private struct ListeningBall: View {
    let color: Color
    let level: Double
    let time: Double

    private let barCount = 12

    /// 安静时补一层极缓呼吸（0.5 Hz，±8%），免得球在停顿处冻住、被读成"没在听"。
    /// 有声时完全让位给真实音量。
    private var amplitude: Double {
        let quiet = 0.06 + 0.05 * (1 + sin(time * .pi))
        return level > 0.06 ? level : quiet
    }

    var body: some View {
        let a = min(1, max(0, amplitude))
        let core = 8 + 12 * a
        let glow = core + 10

        ZStack {
            Circle()
                .fill(color.opacity(0.16 + 0.22 * a))
                .frame(width: glow, height: glow)
                .blur(radius: 3)

            Circle()
                .fill(color)
                .frame(width: core, height: core)

            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(color.opacity(0.5 + 0.4 * a))
                    .frame(width: 2, height: 3 + 5 * a)
                    .offset(y: -(core / 2 + 4))
                    .rotationEffect(.degrees(Double(index) / Double(barCount) * 360))
            }
        }
        .frame(width: 40, height: 40)
    }
}

/// 转写：缺口圆弧匀速旋转——"正在处理"的通用语汇。
private struct TranscribingBall: View {
    let color: Color
    let time: Double

    var body: some View {
        let turn = time.truncatingRemainder(dividingBy: 1.2) / 1.2

        ZStack {
            Circle()
                .stroke(color.opacity(0.25), lineWidth: 2.5)
                .frame(width: 22, height: 22)

            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 22, height: 22)
                .rotationEffect(.degrees(turn * 360))

            Circle()
                .fill(color.opacity(0.55))
                .frame(width: 6, height: 6)
        }
        .frame(width: 40, height: 40)
    }
}

/// 已输入：对勾被"画"出来，画完即静——一次性动作才配得上"结束"。
private struct InsertedBall: View {
    let color: Color
    @State private var drawn: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)

            CheckmarkShape()
                .trim(from: 0, to: drawn)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
        }
        .frame(width: 40, height: 40)
        .onAppear {
            drawn = 0
            withAnimation(.easeOut(duration: 0.35)) { drawn = 1 }
        }
    }
}

/// 提示：静止的信息点。提示可能是"已切换模式"也可能是"没听到内容"，
/// 不能借用已输入的对勾，否则"已忽略"会被读成"成功了"。
private struct NoticeBall: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 22, height: 22)
            Image(systemName: "info")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 40, height: 40)
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

/// 需处理：双拍心跳（快-快-停）。前 5 秒明显，之后节奏放慢、幅度衰减，30 秒内
/// 几乎归静——它要提醒你，但不该在你忙着找输入框时一直敲你。
private struct AttentionBall: View {
    let color: Color
    let time: Double
    @State private var appearedAt: Double?

    var body: some View {
        let elapsed = appearedAt.map { max(0, time - $0) } ?? 0
        let fade = max(0, 1 - elapsed / 22)
        let period = 1.4 + 0.9 * min(1, elapsed / 20)
        let beat = Self.heartbeat(elapsed.truncatingRemainder(dividingBy: period))
        let scale = 1 + 0.24 * beat * fade

        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 26, height: 26)
                .scaleEffect(scale)

            Circle()
                .fill(color)
                .frame(width: 13, height: 13)
                .scaleEffect(scale)
        }
        .frame(width: 40, height: 40)
        .onAppear {
            if appearedAt == nil { appearedAt = time }
        }
    }

    /// 双拍：两个窄高斯峰挨着，其余时间近乎归零。
    private static func heartbeat(_ x: Double) -> Double {
        let first = exp(-pow((x - 0.06) / 0.10, 2))
        let second = exp(-pow((x - 0.30) / 0.10, 2))
        return max(first, second)
    }
}
