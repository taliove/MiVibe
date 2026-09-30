import CoreGraphics

/// 品牌标记几何（epic #1 子任务 B，设计依据 .scratch/mivibe/design/design-system-v3.html）。
///
/// 三根声波接一个文本光标，寓意「声音变成文字」。坐标采用 100×100 网格（y 向上），
/// 所有元素都是纯填充的圆角矩形，不依赖 SwiftUI/AppKit，方便 MiVibeTests 直接断言。
///
/// - 声波三根：(17,40,9,20)、(31,28,9,44)、(45,36,9,28)，圆角 4.5；
/// - 光标柱：(66,21,8,58)，圆角 4；
/// - 光标衬线：(59,18,22,7)、(59,75,22,7)，圆角 3.5。
///
/// 整体并集 x 17...81、y 18...82，落在中央 64×64 安全区（18...82）内。
/// `Scripts/make-icon.swift` 不能导入本模块，携带同一表格的逐字拷贝；
/// `BrandMarkTests` 会读脚本原文核对每个字面量，防止两份拷贝漂移。
public enum BrandMark {
    /// 六个圆角矩形（100 单位网格）。顺序：三根声波 → 光标柱 → 两条衬线。
    public static let bars: [CGRect] = [
        CGRect(x: 17, y: 40, width: 9, height: 20),
        CGRect(x: 31, y: 28, width: 9, height: 44),
        CGRect(x: 45, y: 36, width: 9, height: 28),
        CGRect(x: 66, y: 21, width: 8, height: 58),
        CGRect(x: 59, y: 18, width: 22, height: 7),
        CGRect(x: 59, y: 75, width: 22, height: 7),
    ]

    /// 与 `bars` 一一对应的圆角半径。
    public static let cornerRadii: [CGFloat] = [4.5, 4.5, 4.5, 4, 3.5, 3.5]

    /// 将 100 单位网格映射到目标矩形，返回完整标记的路径。
    public static func path(in rect: CGRect) -> CGPath {
        path(in: rect, levelTier: 1.0)
    }

    /// 电平档变体（菜单栏「正在听」动画用，F 任务按 0.45 / 0.75 / 1.0 驱动）。
    /// 只对三根声波按 `levelTier` 缩短高度并保持垂直居中，光标柱与衬线不变。
    public static func path(in rect: CGRect, levelTier: Double) -> CGPath {
        let tier = min(max(levelTier, 0), 1)
        let path = CGMutablePath()
        for (index, bar) in bars.enumerated() {
            var scaled = bar
            if index < 3 {
                // 声波柱：绕自身垂直中心缩短高度。
                let height = bar.height * tier
                scaled = CGRect(
                    x: bar.minX, y: bar.midY - height / 2,
                    width: bar.width, height: height)
            }
            path.addPath(rounded(scaled, radius: cornerRadii[index], in: rect))
        }
        return path
    }

    /// 把 100 网格里的一个圆角矩形变换到目标矩形（各向同性缩放 + 居中，y 翻转交给 CoreGraphics 的坐标约定）。
    private static func rounded(_ bar: CGRect, radius: CGFloat, in rect: CGRect) -> CGPath {
        let scale = min(rect.width, rect.height) / 100
        let offsetX = rect.minX + (rect.width - 100 * scale) / 2
        let offsetY = rect.minY + (rect.height - 100 * scale) / 2
        var transform = CGAffineTransform(translationX: offsetX, y: offsetY)
            .scaledBy(x: scale, y: scale)
        return CGPath(
            roundedRect: bar, cornerWidth: radius, cornerHeight: radius,
            transform: &transform)
    }
}
