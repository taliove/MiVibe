import MiVibeCore
import SwiftUI

// MARK: - 浮条列表

/// 浮条面板的根视图：选单打开时渲染选单，否则渲染浮条列表（SPEC §13）。
///
/// 列表底部锚定：最新一句在最下面、紧贴原来单条浮条的位置，旧句被推上去；
/// 提示条在最上。上方的条收起时下方的条原位不动（已输入的旧句先收起是常见情况）。
struct FloatBarView: View {
    @ObservedObject var model: FloatPanelModel
    /// 只转交给正在听的那一条，列表本身不观察它（电平约 66 Hz，不能拖着整列重算）。
    let level: AudioLevelModel
    /// 主题观察：主题切换时浮条与模式选单立刻重绘（值取自 BrandColorCurrent，
    /// 不观察则颜色对但不重算，见 Brand.swift 头注释）。
    @ObservedObject private var themeStore: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 晃动进度：每次 +1，`AttentionShakeEffect` 取小数部分画一次轻晃。
    @State private var shakeProgress: Double = 0

    /// 列表最高时的内容高度：两条录音条 + 一条提示条。面板按它（或选单）固定尺寸。
    static var stackHeight: CGFloat {
        let bars = CGFloat(FloatStack.maxRecordingBars + 1)
        return bars * FloatSurface.barHeight + (bars - 1) * FloatSurface.barSpacing
    }

    init(model: FloatPanelModel, level: AudioLevelModel) {
        self.model = model
        self.level = level
        self._themeStore = ObservedObject(wrappedValue: model.themeStore)
    }

    var body: some View {
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
                VStack(spacing: FloatSurface.barSpacing) {
                    ForEach(model.entries) { entry in
                        FloatBarRow(entry: entry, level: level,
                                    maxWidth: model.barWidth - FloatSurface.shadowInset * 2,
                                    reduceMotion: reduceMotion)
                            .transition(rowTransition)
                    }
                }
                .modifier(AttentionShakeEffect(progress: shakeProgress))
            }
        }
        // 入场 / 出场位移、缩放、透明度的目标值（减弱动态效果时只淡入淡出）。
        // 驱动方式：相位写入总在 withAnimation 里（见控制器），这里只声明值。
        .opacity(phaseOpacity)
        .offset(y: phaseOffset)
        .scaleEffect(phaseScale, anchor: .bottom)
        .padding(.bottom, FloatSurface.shadowInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // 浮条 ↔ 选单的内容切换用 standard（高度弹簧撑开 / 收回）。
        // 注意：相位过渡的动画由控制器侧的 withAnimation 给出，不在这里声明——
        // 否则状态的每次低频变化都会给 offset/opacity 套上弹簧。
        .animation(Motion.standard, value: model.picker != nil)
        .onChange(of: model.shakeGeneration) { _, _ in
            // 减弱动态效果：不晃（需处理条自身的描边颜色已经说明状态）。
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: MotionTiming.shakeDuration)) {
                shakeProgress = shakeProgress.rounded(.down) + 1
            }
        }
        .background(FloatUpdateCounter.probe())
    }

    /// 条目增减：新条从下方 10pt、0.96 弹入；收起的条原地缩小淡出。减弱动态效果时只淡入淡出。
    private var rowTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(y: 10).combined(with: .scale(scale: 0.96)).combined(with: .opacity),
            removal: .scale(scale: 0.96).combined(with: .opacity)
        )
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
}

// MARK: - 单条浮条

/// 一条浮条：球 + 状态名 + 指引文案，描边随状态着色。录音条与提示条外观相同。
private struct FloatBarRow: View {
    let entry: FloatEntry
    let level: AudioLevelModel
    let maxWidth: CGFloat
    let reduceMotion: Bool

    private var state: FloatState { entry.state }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if state == .listening {
                    LevelDrivenBall(level: level, reduceMotion: reduceMotion)
                } else {
                    StatusBall(state: state, level: 0, reduceMotion: reduceMotion)
                }
            }
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
        .frame(maxWidth: maxWidth)
        .fixedSize(horizontal: true, vertical: false)
        .floatSurface(tint: state.color, cornerRadius: FloatSurface.cornerRadius)
        .animation(Motion.quick, value: state)
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
        if state == .inserted || entry.message.isEmpty { return state.hint }
        return entry.message
    }
}

/// 正在听的那颗球：只有它观察实时电平，其他条和文字不随电平重算。
private struct LevelDrivenBall: View {
    @ObservedObject var level: AudioLevelModel
    let reduceMotion: Bool

    var body: some View {
        StatusBall(state: .listening, level: level.level, reduceMotion: reduceMotion)
    }
}

/// 整组浮条的「需处理」轻晃（与需处理球同一条曲线：0 → −4 → 4 → −3 → 2 → 0 pt）。
/// `progress` 每次 +1，取小数部分：整数处位移为 0，动画经过 n → n+1 时画一次。
private struct AttentionShakeEffect: GeometryEffect {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let fraction = progress - progress.rounded(.down)
        return ProjectionTransform(CGAffineTransform(translationX: AttentionShake.offset(fraction), y: 0))
    }
}
