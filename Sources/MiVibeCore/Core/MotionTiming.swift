import Foundation

/// 动效计时合同（epic #1 子任务 F）。纯常量与纯函数，无副作用、不读时钟，
/// 界面层（`DesignSystem.Motion`、浮条、菜单栏驱动）从这里取值，测试直接断言。
///
/// 设计来源：`.scratch/mivibe/design/motion-v1.html`（令牌表、签名时序图、
/// 菜单栏三档电平帧、声波高度公式）。改数字前先改设计稿。
public enum MotionTiming {
    // MARK: - 时长（秒）

    /// 签名动作：正在听 → 正在转写，总长（声波收拢 0–200 ms → 圆弧画入 180–420 ms）。
    public static let signatureDuration: Double = 0.42
    /// 签名动作内，圆弧开始画入 / 转圈的起始时刻。
    public static let signatureArcStart: Double = 0.18
    /// 签名动作内，声波收拢到位的时刻。
    public static let signatureBarsConverge: Double = 0.20
    /// 签名动作内，声波完全淡出的时刻。
    public static let signatureBarsGone: Double = 0.26
    /// 签名圆弧的目标弧长占比（与转写态相同）。
    public static let signatureArcTrim: Double = 0.28

    /// 转写 / 改写圆弧匀速一圈的周期。
    public static let spinPeriod: Double = 1.2
    /// 听音安静时的呼吸频率（Hz）。
    public static let quietBreathHz: Double = 0.5
    /// 电平低于此值视为安静，用呼吸代替音量驱动声波。
    public static let quietLevelThreshold: Double = 0.08

    /// 已输入：对勾画完后停留这么久再收起。
    public static let insertedHideDelay: Double = 1.6
    /// 提示：出现后停留这么久再收起。
    public static let noticeHideDelay: Double = 2.0
    /// 需处理：出现后停留这么久再收起。
    public static let attentionHideDelay: Double = 30.0

    /// 按键提示：最后一次按键后停留这么久再淡出（连发时每次按键重新计时）。
    public static let keyHintHideDelay: Double = 0.8

    /// 对勾描线时长（`Motion.draw` 对应的时间值）。
    public static let drawDuration: Double = 0.35
    /// 已输入时圆弧合拢成整圈的时长。
    public static let arcCloseDuration: Double = 0.20
    /// 需处理横向轻晃的总时长（0 → −4 → 4 → −3 → 2 → 0 pt）。
    public static let shakeDuration: Double = 0.40
    /// 轻晃相对状态切换的延迟。
    public static let shakeDelay: Double = 0.22
    /// 需处理心跳周期。
    public static let heartbeatPeriod: Double = 1.4
    /// 需处理心跳次数。
    public static let heartbeatCount: Int = 3
    /// 需处理持续动画的截止时长（之后视图静止，不再逐帧重绘）。
    public static let attentionAnimateWindow: Double = 5.0
    /// 改写四角星闪烁周期（缩放到 0.78 再回来）。
    public static let twinklePeriod: Double = 1.6

    // MARK: - 菜单栏

    /// 模式选单确认：高亮行闪亮时长，闪完才收回选单。
    public static let pickerConfirmFlash: Double = 0.16
    /// 退场动画（Motion.exit，0.24 s）走完再 orderOut 的等待，多留 20 ms 余量。
    public static let exitSettle: Double = 0.26

    /// 菜单栏电平帧的最高更新频率。
    public static let menuBarMaxFPS: Double = 6
    /// 相邻两帧的最小间隔。
    public static var menuBarFrameInterval: Double { 1.0 / menuBarMaxFPS }

    /// 电平 0…1 → 三档菜单栏帧（0.45 / 0.75 / 1.0）。档边界左闭右开：
    /// < 0.30 用最低帧，< 0.65 用中帧，其余满帧。越界输入按端点收敛。
    public static func menuBarTier(level: Double) -> Double {
        menuBarTiers[menuBarFrameIndex(level: level)]
    }

    /// 菜单栏三帧的声波高度档，按帧序排列（MenuBarIcon 据此预绘 levelFrames）。
    public static let menuBarTiers: [Double] = [0.45, 0.75, 1.0]

    /// 菜单栏声波的跳动图案（三根柱各自的相对高度）。正在听时每帧换一个图案，
    /// 所以即使音量稳定图标也在跳；音量只决定跳动幅度（`menuBarTiers`）。
    /// 只按档位整体缩放在 18 pt 图标上几乎看不出来（真机反馈）。
    public static let menuBarPatterns: [[Double]] = [
        [0.55, 1.20, 0.70],
        [1.00, 0.60, 1.10],
        [0.70, 1.05, 0.45],
        [1.15, 0.80, 0.90],
    ]

    /// 某档位 × 某图案的三根柱最终缩放：图案 × 幅度，下限 0.3 避免柱子消失。
    public static func menuBarBarScales(tierIndex: Int, patternIndex: Int) -> [Double] {
        let amplitude = menuBarTiers[min(max(tierIndex, 0), menuBarTiers.count - 1)]
        let pattern = menuBarPatterns[((patternIndex % menuBarPatterns.count) + menuBarPatterns.count) % menuBarPatterns.count]
        return pattern.map { max(0.3, $0 * amplitude) }
    }

    /// 电平 0…1 → 帧序号（与 `menuBarTiers` 同序）。
    public static func menuBarFrameIndex(level: Double) -> Int {
        let clamped = min(1, max(0, level))
        if clamped < 0.30 { return 0 }
        if clamped < 0.65 { return 1 }
        return 2
    }

    // MARK: - 声波高度

    /// 三根声波柱的基准高度比（品牌标记比例）。
    public static let barBases: [Double] = [0.55, 1.0, 0.7]

    /// 听音柱的垂直缩放：clamp(0.22…1, (0.25 + 0.75·level·wobble)·base + 0.1)。
    ///
    /// `wobble = 0.78 + 0.22·sin(phase)`，由调用方按 `9t + 2.1i` 给出相位；
    /// 越界电平同样被夹回 0.22…1（音频管线异常时不至于把球画飞）。
    public static func barScale(level: Double, base: Double, wobblePhase: Double) -> Double {
        let wobble = 0.78 + 0.22 * sin(wobblePhase)
        let raw = (0.25 + 0.75 * level * wobble) * base + 0.1
        return min(1.0, max(0.22, raw))
    }

    // MARK: - 帧节流

    /// 频率节流器：距上次放行不足 `1/fps` 秒的请求一律拒绝。菜单栏电平帧
    /// 用它把约 66 Hz 的电平回调压到 ≤ 6 fps。可值语义、可注入时间，方便测试。
    public struct FrameThrottle {
        public let fps: Double
        private var lastAdvance: Double?

        public init(fps: Double) {
            self.fps = fps
        }

        /// 询问时刻 `time`（秒）是否可以推进一帧；可以则记录该时刻并返回 true。
        public mutating func shouldAdvance(at time: Double) -> Bool {
            if let lastAdvance, time - lastAdvance < 1.0 / fps { return false }
            lastAdvance = time
            return true
        }

        /// 清空历史，下一次询问必然放行（重新开始听音时用）。
        public mutating func reset() {
            lastAdvance = nil
        }
    }
}
