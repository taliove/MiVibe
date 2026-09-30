import AppKit
import Combine
import MiVibeCore
import SwiftUI

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
                .fill(polishing ? Color(nsColor: .brandAccentFill) : color.opacity(1 - 0.72 * fillFade))
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

            // 圆弧：28% 底色圆 + 整圈浅轨道 + 28% 弧段旋转；改写时弧转白。
            // 早先只有 18% 底色 + 细弧，叠在毛玻璃上几乎看不出（真机反馈）。
            Circle()
                .stroke((polishing ? Color.brandOnAccentFill : color).opacity(0.3), lineWidth: 3)
                .frame(width: 16, height: 16)
                .opacity(arcDraw)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(polishing ? Color.brandOnAccentFill : color,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
                .fill(polishing ? color : color.opacity(0.28))
            Circle()
                .stroke((polishing ? Color.brandOnAccentFill : color).opacity(0.3), lineWidth: 3)
                .frame(width: 16, height: 16)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(polishing ? Color.brandOnAccentFill : color,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
            // 浅色下灰色信息符号叠在 20% 灰底上几乎看不见（实测截图），
            // 符号改用前景色 65%：仍是中性灰，深浅两态都清楚。
            Image(systemName: "info")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.primary.opacity(0.65))
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
    private var reduceShakeOffset: CGFloat { AttentionShake.offset(shake) }
}

/// 「需处理」轻晃曲线：进度 0…1 → 横向位移 0 → −4 → 4 → −3 → 2 → 0 pt。
/// 需处理球与整组浮条（第三条录音被拒绝）共用这一条曲线。
enum AttentionShake {
    private static let keyframes: [(Double, Double)] = [(0, 0), (0.2, -4), (0.45, 4), (0.65, -3), (0.85, 2), (1, 0)]

    static func offset(_ progress: Double) -> CGFloat {
        let x = min(1, max(0, progress))
        for i in 1..<keyframes.count where x <= keyframes[i].0 {
            let (t0, v0) = keyframes[i - 1]
            let (t1, v1) = keyframes[i]
            let f = (x - t0) / (t1 - t0)
            return CGFloat(v0 + (v1 - v0) * f)
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
