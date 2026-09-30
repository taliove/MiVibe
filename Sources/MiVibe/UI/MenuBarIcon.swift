import AppKit
import MiVibeCore

/// 菜单栏模板图标（epic #1 子任务 B）：由 BrandMark 几何绘制的 18×18 pt NSImage，
/// `isTemplate = true`，深浅菜单栏都由系统着色，不写死颜色。
///
/// 状态图（B 交付静态图；正在听的三帧电平动画由 F 任务驱动）：
/// - connected：完整标记
/// - listening：暂用完整标记（`levelFrames` 已备好三帧，F 按 0.45 / 0.75 / 1.0 选帧）
/// - pairedOffline：标记 38% 透明度
/// - unpaired：标记 38% 透明度 + 右下角实心圆（挖空加号）
@MainActor
enum MenuBarIcon {
    /// 图标点数与内部绘制网格（网格 100 单位，含留白）。
    private static let pointSize: CGFloat = 18
    /// 标记在图标内的占比（四周各留 ~9% 呼吸位）。
    private static let markFraction: CGFloat = 0.82

    /// 电平档三帧（0.45 / 0.75 / 1.0），F 任务按音量选帧驱动菜单栏动画。
    static let levelFrames: [NSImage] = [0.45, 0.75, 1.0].map { tier in
        draw(levelTier: tier, alpha: 1, badge: false)
    }

    /// 按链路状态取模板图标。
    static func image(for link: LinkState) -> NSImage {
        switch link {
        case .connected:
            return draw(levelTier: 1.0, alpha: 1, badge: false)
        case .pairedOffline:
            return draw(levelTier: 1.0, alpha: 0.38, badge: false)
        case .unpaired:
            return draw(levelTier: 1.0, alpha: 0.38, badge: true)
        }
    }

    /// 正在听（暂为静态完整标记，与 connected 相同；F 接管后按电平选 `levelFrames`）。
    static var listening: NSImage {
        draw(levelTier: 1.0, alpha: 1, badge: false)
    }

    // MARK: - 绘制

    private static func draw(levelTier: Double, alpha: CGFloat, badge: Bool) -> NSImage {
        let s = pointSize
        let image = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let markEdge = s * markFraction
            let markRect = CGRect(x: (s - markEdge) / 2, y: (s - markEdge) / 2,
                                  width: markEdge, height: markEdge)
            ctx.setFillColor(NSColor.black.withAlphaComponent(alpha).cgColor)
            ctx.addPath(BrandMark.path(in: markRect, levelTier: levelTier))
            ctx.fillPath()

            if badge {
                // 右下角实心圆 + 挖空加号（未配对，需要配对的提示）。
                let d = s * 0.34
                let circle = CGRect(x: s - d, y: 0, width: d, height: d)
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fillEllipse(in: circle)
                ctx.setBlendMode(.clear)
                let stroke = d * 0.16
                let arm = d * 0.52
                let cx = circle.midX, cy = circle.midY
                ctx.fill(CGRect(x: cx - arm / 2, y: cy - stroke / 2, width: arm, height: stroke))
                ctx.fill(CGRect(x: cx - stroke / 2, y: cy - arm / 2, width: stroke, height: arm))
                ctx.setBlendMode(.normal)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
