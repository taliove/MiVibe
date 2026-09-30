import MiVibeCore
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

/// 动效令牌（epic #1 子任务 F）：界面代码只引用这些名字，不再散落 0.18 / 0.35
/// 这样的数字。纯计时值（签名时长、自动隐藏、fps）在 `MotionTiming`（MiVibeCore，
/// 可测试）；这里的 `signatureDuration` 等直接转发，两处不会漂移。
///
/// 设计来源：`.scratch/mivibe/design/motion-v1.html` 令牌表。弹簧阻尼 0.86 只有
/// 约 1% 过冲，看起来"落位"而不是"弹跳"。
enum Motion {
    /// 按下反馈、悬停底色、按键回显闪亮（100 ms）。
    static let instant = Animation.easeOut(duration: 0.10)
    /// 状态颜色、描边、文字淡入淡出（180 ms）。
    static let quick = Animation.easeOut(duration: 0.18)
    /// 出现、宽度伸缩、选单高亮与侧栏选中块移动（约 300 ms 弹簧）。
    static let standard = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// 浮条收起、选单关闭（240 ms）。
    static let exit = Animation.easeIn(duration: 0.24)
    /// 对勾描线、圆弧画入（350 ms）。
    static let draw = Animation.easeOut(duration: 0.35)
    /// 切换主题色时整窗换色（250 ms）。
    static let theme = Animation.easeInOut(duration: 0.25)

    /// 签名动作总长：正在听 → 正在转写。
    static let signatureDuration = MotionTiming.signatureDuration
    /// 转写 / 改写圆弧一圈的周期。
    static let spinPeriod = MotionTiming.spinPeriod
    /// 听音安静时的呼吸频率。
    static let quietBreathHz = MotionTiming.quietBreathHz
    /// 菜单栏电平帧的最高更新频率。
    static let menuBarMaxFPS = MotionTiming.menuBarMaxFPS
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
