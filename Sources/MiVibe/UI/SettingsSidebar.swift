import MiVibeCore
import SwiftUI

/// 设置窗口侧栏：设备状态卡 + 分页导航（系统设置观感）。
///
/// 放在 `NSSplitViewController` 的 sidebar 项里，背景材质由系统提供（macOS 26 为
/// 玻璃面板），这里不再自绘底色；导航用原生 sidebar 列表，选中态与系统设置一致。
/// 状态卡把「遥控器连没连」从遥控器页的一行提升为常驻可见——这是用户打开设置
/// 时最想先确认的事。
struct SettingsSidebar: View {
    @ObservedObject var coordinator: Coordinator
    @ObservedObject var paneModel: SettingsPaneModel

    var body: some View {
        List(selection: Binding<SettingsPane?>(
            get: { paneModel.pane },
            // 列表不允许「取消选中」：点空白处传回 nil 时保持当前页。
            set: { if let pane = $0 { paneModel.pane = pane } }
        )) {
            deviceCard
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 10, trailing: 0))
                .listRowSeparator(.hidden)
            ForEach(SettingsPane.allCases) { pane in
                Label(pane.title, systemImage: pane.icon)
                    .tag(pane)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - 设备状态卡

    private var deviceCard: some View {
        HStack(spacing: Spacing.intra) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("MiVibe").font(.headline)
                HStack(spacing: 4) {
                    Circle()
                        .fill(coordinator.link.color)
                        .frame(width: 6, height: 6)
                    Text(coordinator.link.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7),
                    in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
    }
}
