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

/// 应用内的品牌图标：圆角矩形 + 当前主题渐变 + 白色标记，随主题换色。
///
/// 访达、程序坞里的 AppIcon.icns 是静态文件，始终是品牌默认色（潮汐青）；
/// 应用内（设置侧栏、关于页）属于主题管辖范围，跟随用户选的主题。
struct ThemedAppIcon: View {
    let size: CGFloat
    @ObservedObject private var themeStore = AppDelegate.shared.themeStore

    var body: some View {
        let palette = themeStore.palette
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(nsColor: NSColor(palette.iconTop)),
                                              Color(nsColor: NSColor(palette.iconBottom))],
                                     startPoint: .top, endPoint: .bottom))
            // BrandMark 的 100 网格里标记占中间 64%，与 make-icon.swift 一致。
            BrandGlyph()
                .foregroundStyle(.white)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
