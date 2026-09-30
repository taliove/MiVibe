import MiVibeCore
import SwiftUI

/// 外观模式的中文展示名（界面层；MiVibeCore 不带界面文案）。
extension AppearanceMode {
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

/// 「外观」页（epic #1 子任务 D）：界面外观三选 + 六套主题色 + 浮条预览。
///
/// 改动经 `ThemeStore` 立即生效（设置窗口、菜单弹层与浮条一起），并持久化到配置。
/// 本页只做选择，不持有任何草稿状态——选择即应用。
struct SettingsAppearanceView: View {
    @ObservedObject var themeStore: ThemeStore
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            PageHeader(subtitle: "选择设置窗口、菜单与浮条的外观和主题色。")

            appearanceGroup
            themeGroup
            previewGroup
        }
        .padding(Spacing.page)
    }

    // MARK: - 界面外观

    private var appearanceGroup: some View {
        SettingsGroup(title: "界面外观",
                      footer: "跟随系统时，设置窗口、菜单与浮条随 macOS 外观自动切换。") {
            HStack(spacing: Spacing.intra) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    appearanceThumbnail(mode)
                }
            }
            .padding(Spacing.rowH)
        }
    }

    private func appearanceThumbnail(_ mode: AppearanceMode) -> some View {
        let isSelected = themeStore.appearance == mode
        return Button {
            themeStore.set(appearance: mode)
        } label: {
            VStack(spacing: 6) {
                AppearanceThumbnail(mode: mode)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.brandAccent, lineWidth: isSelected ? 2 : 0))
                Text(mode.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.brandAccent : Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 主题色

    private var themeGroup: some View {
        SettingsGroup(title: "主题色",
                      footer: "已输入、需处理、出错的颜色固定，不随主题改变。应用图标始终使用品牌默认色。") {
            SettingsRow(icon: "paintpalette", title: "主题色",
                        subtitle: "\(themeStore.palette.displayName) · 用于录音、转写、改写状态与选中项") {
                HStack(spacing: 9) {
                    ForEach(ThemeID.allCases, id: \.self) { id in
                        themeSwatch(id)
                    }
                }
            }
        }
    }

    private func themeSwatch(_ id: ThemeID) -> some View {
        let palette = ThemePalette.palette(id)
        let isSelected = themeStore.theme == id
        return Button {
            themeStore.set(theme: id)
        } label: {
            Circle()
                .fill(Color(nsColor: .dynamic(light: palette.accent, dark: palette.accentDark)))
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.brandAccent.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
                .padding(2)
                .overlay(Circle().strokeBorder(Color.brandAccent, lineWidth: isSelected ? 2 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(palette.displayName)
        .accessibilityLabel(palette.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 预览

    private var previewGroup: some View {
        SettingsGroup(title: "预览") {
            floatBarPreview
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color(white: 0.93), Color(white: 0.17)],
                        startPoint: UnitPoint(x: 0.25, y: 0),
                        endPoint: UnitPoint(x: 0.75, y: 1)
                    ),
                    in: RoundedRectangle(cornerRadius: Radius.small)
                )
                .padding(.horizontal, Spacing.rowH)
                .padding(.vertical, Spacing.rowV)
        }
    }

    /// 静态「正在听」浮条：实心主题色圆 + 三条声波柱 + 文案。与真实浮条同观感，
    /// 但固定不动（动效属子任务 F）。深色填充面上的文字用 brandOnAccentFill。
    private var floatBarPreview: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.brandAccentFill)
                    .frame(width: 34, height: 34)
                HStack(alignment: .center, spacing: 2.5) {
                    Capsule().frame(width: 3, height: 10)
                    Capsule().frame(width: 3, height: 16)
                    Capsule().frame(width: 3, height: 12)
                }
                .foregroundStyle(Color.brandOnAccentFill)
            }
            Text("正在听")
                .fontWeight(.semibold)
            Text("松开语音键结束")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.trailing, 16)
        .frame(height: 44)
        .background(.regularMaterial, in: Capsule())
    }
}

/// 外观模式缩略图：左侧 30% 侧栏色 + 右侧 70% 内容区，内容里两条示意行
/// （一条主题色、一条侧栏色）。跟随系统是浅 / 深对半分。
private struct AppearanceThumbnail: View {
    let mode: AppearanceMode

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                sidebar
                    .frame(width: geo.size.width * 0.3)
                content
            }
        }
        .frame(height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
    }
    /// 侧栏区域（跟随系统时左浅右深对半）。
    @ViewBuilder
    private var sidebar: some View {
        if mode == .system {
            LinearGradient(colors: [Color(white: 0.93), Color(white: 0.15)],
                           startPoint: .leading, endPoint: .trailing)
        } else {
            sidebarColor
        }
    }

    /// 内容区域：背景 + 两条示意行。
    private var content: some View {
        contentBase
            .overlay(
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(Color.brandAccent).frame(width: 30, height: 5)
                    Capsule().fill(sidebarColor).frame(width: 44, height: 5)
                }
                .padding(6),
                alignment: .topLeading
            )
    }

    @ViewBuilder
    private var contentBase: some View {
        if mode == .system {
            LinearGradient(colors: [Color.white, Color(white: 0.12)],
                           startPoint: .leading, endPoint: .trailing)
        } else {
            contentColor
        }
    }

    private var sidebarColor: Color {
        mode == .dark ? Color(white: 0.15) : Color(white: 0.93)
    }

    private var contentColor: Color {
        mode == .dark ? Color(white: 0.12) : Color.white
    }
}
