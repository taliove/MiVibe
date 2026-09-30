import AppKit
import SwiftUI

// MARK: - 表面
//
// 浮条盖在任意应用之上：深色终端、浅色文档、花哨网页都有。原先的 86% 纯黑条
// 在深色背景上几乎没有边界。改为系统毛玻璃（跟随浅色/深色外观）+ 发丝描边 +
// 状态色描边：底色随系统，描边保证在任何背景上都有清楚的轮廓，颜色同时说明状态。

enum FloatSurface {
    static let barHeight: CGFloat = 44
    /// 叠放的浮条之间的间距。
    static let barSpacing: CGFloat = 8
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

extension View {
    func floatSurface(tint: Color?, cornerRadius: CGFloat) -> some View {
        modifier(FloatSurfaceModifier(tint: tint, cornerRadius: cornerRadius))
    }
}
