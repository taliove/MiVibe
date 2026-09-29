import SwiftUI

/// 设置页通用卡片组件（macOS 系统设置观感），替代 SwiftUI `Form(grouped)`：
/// `SettingsGroup` 提供「组标题 + 圆角卡片 + 可选脚注」，`SettingsRow` 是卡片内的
/// 标准行（彩色图标 + 主副标题 + 右侧控件），`RowDivider` 是对齐标题文字的分隔线。

struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 卡片内的标准行：图标 + 主标题（可选副标题）居左，控件居右。
struct SettingsRow<Trailing: View>: View {
    var icon: String
    var iconColor: Color = .accentColor
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.intra) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, Spacing.rowH)
        .padding(.vertical, Spacing.rowV)
        .frame(minHeight: Spacing.rowMinHeight)
    }
}

extension SettingsRow where Trailing == EmptyView {
    /// 纯展示行（状态、说明），无右侧控件。
    init(icon: String, iconColor: Color = .accentColor, title: String, subtitle: String? = nil) {
        self.init(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// 卡片内的自由内容行（无图标），内边距与 `SettingsRow` 一致。
struct SettingsPlainRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, Spacing.rowH)
            .padding(.vertical, Spacing.rowV)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 行分隔线：左缩进对齐标题文字（图标 20 + 间距 10 + 行内边距 12 ≈ 42）。
struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 42)
    }
}

/// 页面顶部的提示横幅：橙色浅底 + 图标 + 一行说明 + 右侧一个操作按钮。
struct NoticeBanner: View {
    let icon: String
    let text: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: Spacing.intra) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
            Text(text).font(.callout)
            Spacer()
            Button(actionTitle, action: action)
                .controlSize(.small)
        }
        .padding(.horizontal, Spacing.rowH)
        .padding(.vertical, Spacing.rowV)
        .background(Color.orange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Radius.small))
    }
}
