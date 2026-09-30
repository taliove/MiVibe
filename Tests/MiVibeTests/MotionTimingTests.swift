import Foundation
import MiVibeCore

/// MotionTiming 纯函数与常量（epic #1 子任务 F）。
///
/// 这些数字是动效设计的合同：签名动作 420 ms、转写圈 1.2 s、菜单栏 ≤ 6 fps、
/// 自动隐藏 1.6 / 2.0 / 30 s。界面层（DesignSystem.Motion）从这里取值，
/// 测试直接断言这里的常量，两处不会漂移。
enum MotionTimingTests {
    static func run() {
        Harness.suite("MotionTiming 常量") {
            Harness.expectEqual(MotionTiming.signatureDuration, 0.42, "签名动作 420 ms")
            Harness.expectEqual(MotionTiming.spinPeriod, 1.2, "转写一圈 1.2 s")
            Harness.expectEqual(MotionTiming.quietBreathHz, 0.5, "安静呼吸 0.5 Hz")
            Harness.expectEqual(MotionTiming.menuBarMaxFPS, 6, "菜单栏至多 6 fps")
            Harness.expectEqual(MotionTiming.insertedHideDelay, 1.6, "已输入 1.6 s 后收起")
            Harness.expectEqual(MotionTiming.noticeHideDelay, 2.0, "提示 2.0 s 后收起")
            Harness.expectEqual(MotionTiming.attentionHideDelay, 30.0, "需处理 30 s 后收起")
        }

        Harness.suite("MotionTiming 菜单栏电平分档") {
            Harness.expectEqual(MotionTiming.menuBarTier(level: 0), 0.45, "电平 0 → 最低帧")
            Harness.expectEqual(MotionTiming.menuBarTier(level: 0.29), 0.45, "电平 0.29 → 最低帧")
            Harness.expectEqual(MotionTiming.menuBarTier(level: 0.30), 0.75, "电平 0.30 → 中帧")
            Harness.expectEqual(MotionTiming.menuBarTier(level: 0.64), 0.75, "电平 0.64 → 中帧")
            Harness.expectEqual(MotionTiming.menuBarTier(level: 0.65), 1.0, "电平 0.65 → 满帧")
            Harness.expectEqual(MotionTiming.menuBarTier(level: 1.0), 1.0, "电平 1.0 → 满帧")
            // 越界输入按端点收敛，不允许产出档外值。
            Harness.expectEqual(MotionTiming.menuBarTier(level: -0.5), 0.45, "负电平收敛到最低帧")
            Harness.expectEqual(MotionTiming.menuBarTier(level: 2.0), 1.0, "超 1 电平收敛到满帧")
        }

        Harness.suite("MotionTiming 菜单栏帧序号与档位同序") {
            // 驱动器按序号取 MenuBarIcon.levelFrames，序号与档位表必须一一对应。
            Harness.expectEqual(MotionTiming.menuBarTiers, [0.45, 0.75, 1.0], "三档按帧序排列")
            for level in [-1.0, 0, 0.29, 0.30, 0.64, 0.65, 1.0, 3.0] {
                let index = MotionTiming.menuBarFrameIndex(level: level)
                Harness.expect((0..<3).contains(index), "电平 \(level) 的帧序号在 0…2")
                Harness.expectEqual(MotionTiming.menuBarTiers[index], MotionTiming.menuBarTier(level: level),
                                    "电平 \(level)：序号取出的档位与 menuBarTier 一致")
            }
            Harness.expectEqual(MotionTiming.exitSettle > 0.24, true, "orderOut 等待长于退场动画 0.24 s")
            Harness.expectEqual(MotionTiming.pickerConfirmFlash, 0.16, "选单确认闪亮 160 ms")
        }

        Harness.suite("MotionTiming 菜单栏 6 fps 节流") {
            var throttle = MotionTiming.FrameThrottle(fps: 6)
            Harness.expect(throttle.shouldAdvance(at: 100.0), "首帧放行")
            Harness.expect(!throttle.shouldAdvance(at: 100.1), "距上帧 100 ms（< 1/6 s）不放行")
            Harness.expect(!throttle.shouldAdvance(at: 100.16), "距上帧 160 ms 仍不放行")
            Harness.expect(throttle.shouldAdvance(at: 100.0 + 1.0 / 6.0), "恰好 1/6 s 放行")
            Harness.expect(!throttle.shouldAdvance(at: 100.2), "放行后 1/30 s 不放行")
            Harness.expect(throttle.shouldAdvance(at: 100.4), "距上帧约 233 ms 放行")
            throttle.reset()
            Harness.expect(throttle.shouldAdvance(at: 100.4), "reset 后立即放行")
        }

        Harness.suite("MotionTiming 声波高度函数") {
            // 电平 −1…2 都被夹在 0.22…1 之间（三根柱各自的基准不同，逐根验证）。
            for base in [0.55, 1.0, 0.7] {
                for level in stride(from: -1.0, through: 2.0, by: 0.25) {
                    for phase in stride(from: 0.0, through: .pi * 2, by: 0.7) {
                        let scale = MotionTiming.barScale(level: level, base: base, wobblePhase: phase)
                        Harness.expect(
                            (0.22...1.0).contains(scale),
                            "barScale(level: \(level), base: \(base)) = \(scale) 在 0.22…1 内")
                    }
                }
            }
            Harness.expectEqual(MotionTiming.barScale(level: 1, base: 1, wobblePhase: .pi / 2),
                                1.0, "满电平满相位到达上限 1")
            Harness.expectEqual(MotionTiming.barScale(level: -1, base: 0.55, wobblePhase: 0),
                                0.22, "极低电平触到下限 0.22")
        }
    }
}
