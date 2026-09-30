import MiVibeCore
import SwiftUI

/// 可复用的品牌标记视图（epic #1 子任务 B）。
///
/// 用 Shape 绘制 BrandMark 几何，填充当前前景样式（foregroundStyle），
/// 尺寸完全由外部 `.frame` 决定。其他界面（菜单弹层头部磁贴、设置连接行等）
/// 在合并后直接引用本视图，不重复实现路径。
struct BrandGlyph: View {
    var body: some View {
        BrandMarkShape()
            .fill(.foreground)
            .aspectRatio(1, contentMode: .fit)
    }
}

/// BrandMark 的 SwiftUI Shape 包装：path(in:) 由 Core 提供，保持单一几何来源。
private struct BrandMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(BrandMark.path(in: rect))
    }
}
