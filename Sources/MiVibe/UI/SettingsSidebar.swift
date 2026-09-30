import MiVibeCore
import SwiftUI

/// 设置窗口侧栏：设备状态卡 + 分页导航（系统设置观感）。
///
/// 自绘导航行而不是 `List(selection:)`：原生 sidebar 列表的选中色只能跟系统
/// 强调色（本机没有 actool，无法声明 NSAccentColorName），epic 要求选中色跟随
/// 主题。行是 Button，选中 = 主题填充底 + 填充面文字色，悬停 = 着色背景 60%。
///
/// 键盘：侧栏持有焦点时 ↑/↓ 移动选中（相邻页即上下相邻，不用翻历史）；
/// ⌘数字与 ⌘[ / ⌘] 仍由窗口控制器处理。
///
/// 放在 `NSSplitViewController` 的 sidebar 项里，背景材质由系统提供（macOS 26 为
/// 玻璃面板），这里不再自绘底色。状态卡把「遥控器连没连」从遥控器页的一行提升为
/// 常驻可见——这是用户打开设置时最想先确认的事。
struct SettingsSidebar: View {
    @ObservedObject var coordinator: Coordinator
    @ObservedObject var paneModel: SettingsPaneModel
    /// 「新」胶囊是否还显示（外观页被打开过一次后隐藏）。
    var showAppearanceNewBadge: Bool

    /// 侧栏焦点：只有聚焦时 ↑/↓ 才移动选中，避免抢走详情列里控件的方向键。
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                deviceCard
                    .padding(.bottom, 10)
                ForEach(SettingsPane.allCases) { pane in
                    SidebarRow(
                        pane: pane,
                        isSelected: paneModel.pane == pane,
                        showNewBadge: pane == .appearance && showAppearanceNewBadge
                    ) {
                        paneModel.pane = pane
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .tint(Color.brandAccent)
        .focused($focused)
        .focusable()
        .onMoveCommand { direction in
            guard focused else { return }
            let panes = SettingsPane.allCases
            guard let index = panes.firstIndex(of: paneModel.pane) else { return }
            switch direction {
            case .up:
                if index > panes.startIndex { paneModel.pane = panes[index - 1] }
            case .down:
                if index < panes.index(before: panes.endIndex) { paneModel.pane = panes[index + 1] }
            default:
                break
            }
        }
    }

    // MARK: - 设备状态卡

    private var deviceCard: some View {
        HStack(spacing: Spacing.intra) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("MiVibe").font(.headline)
                statusCapsule
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7),
                    in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
    }

    /// 状态胶囊：已连接 = 成功点（带 3pt 光晕）+ 成功色文字；已配对未连接 = 中性
    /// 提示；未配对 = 需要注意。颜色固定语义色，不随主题（epic 色彩规则）。
    private var statusCapsule: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(coordinator.link.color)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(coordinator.link == .connected
                                ? coordinator.link.color.opacity(0.35) : .clear,
                                lineWidth: 3)
                )
            Text(coordinator.link.rawValue)
                .font(.caption2)
                .foregroundStyle(coordinator.link == .connected
                                 ? coordinator.link.color : Color.secondary)
        }
    }
}

/// 侧栏导航行：28pt 高、图标 + 标题，选中 = 主题填充底 + 填充面文字/图标色，
/// 悬停 = 着色背景 60%。选中切换即时完成，无滑动动画（动效属子任务 F）。
private struct SidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    var showNewBadge = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: pane.icon)
                    .frame(width: 18)
                Text(pane.title)
                    .font(.system(size: 13.5))
                Spacer(minLength: 4)
                if showNewBadge {
                    Text("新")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(isSelected
                                    ? Color.brandOnAccentFill.opacity(0.25)
                                    : Color.brandAccentSoft,
                                    in: Capsule())
                        .foregroundStyle(isSelected ? Color.brandOnAccentFill : Color.brandAccent)
                }
            }
            .foregroundStyle(isSelected ? Color.brandOnAccentFill : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background,
                        in: RoundedRectangle(cornerRadius: Radius.badge))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return Color.brandAccentFill }
        if hovering { return Color.brandAccentSoft.opacity(0.6) }
        return .clear
    }
}
