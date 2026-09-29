import SwiftUI

// MARK: - 全局设计常量（对齐 macOS 系统设置观感：统一间距 / 圆角 / 动效，消灭散落的魔法数字）

/// 间距体系：页面 20 / 组间 16 / 组内 10 / 行内 12×7。
enum Spacing {
    /// 页面内容四周留白
    static let page: CGFloat = 20
    /// 分组（卡片）之间的垂直距离
    static let section: CGFloat = 16
    /// 组内元素间距（图标与文字、标题与控件）
    static let intra: CGFloat = 10
    /// 行左右内边距
    static let rowH: CGFloat = 12
    /// 行上下内边距
    static let rowV: CGFloat = 7
    /// 表单行最小高度
    static let rowMinHeight: CGFloat = 34
    /// 卡片内自由布局的内边距
    static let cardPadding: CGFloat = 14
    /// 行尾文本框统一宽度（与系统设置的右对齐控件一致）
    static let fieldWidth: CGFloat = 220
}

/// 圆角体系：小标记 6 / 徽标 7 / 卡片 10。
enum Radius {
    static let small: CGFloat = 6
    static let badge: CGFloat = 7
    static let card: CGFloat = 10
}

/// 动效体系：选中/高亮 0.15s 缓动；微提示出现快、退场慢。
enum Motion {
    static let select = Animation.easeInOut(duration: 0.15)
    static let quickFade = Animation.easeIn(duration: 0.1)
    static let toastFade = Animation.easeOut(duration: 0.4)
}

/// 每页内容区顶部的一行说明小字。页名显示在窗口工具栏，内容区不再重复。
struct PageHeader: View {
    let subtitle: String

    var body: some View {
        Text(subtitle)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
