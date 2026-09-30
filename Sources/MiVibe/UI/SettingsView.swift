import MiVibeCore
import SwiftUI

/// 设置窗口侧栏当前选中页（窗口控制器持有，视图观察）。
///
/// 内部维护一份前进 / 后退导航历史（`NavigationHistory`）：直接给 `pane` 赋值
/// 即视为访问新页并记入历史；`goBack()` / `goForward()` 只切换当前页，不再
/// 重复记录。
@MainActor
final class SettingsPaneModel: ObservableObject {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    /// 当前页。直接赋值（如 `paneModel.pane = .remote`）即记入导航历史。
    @Published var pane: SettingsPane {
        didSet {
            history.visit(pane)
            syncHistoryState()
        }
    }

    private var history: NavigationHistory<SettingsPane>

    init(initial: SettingsPane = .recognition) {
        history = NavigationHistory(initial: initial)
        pane = initial
    }

    /// 后退一页（不重复记历史）；无可回退时不做操作。
    func goBack() {
        guard let target = history.goBack() else { return }
        pane = target
        syncHistoryState()
    }

    /// 前进一页（不重复记历史）；无可前进时不做操作。
    func goForward() {
        guard let target = history.goForward() else { return }
        pane = target
        syncHistoryState()
    }

    private func syncHistoryState() {
        canGoBack = history.canGoBack
        canGoForward = history.canGoForward
    }
}

/// 设置页内容：系统设置风分组卡片（组件见 SettingsComponents.swift）；页名在窗口
/// 工具栏显示，内容区只留副标题。分页容器在 `SettingsWindowController`（侧栏
/// 分栏），这里只渲染详情列的选中页。
struct SettingsView: View {
    @ObservedObject var coordinator: Coordinator
    @ObservedObject var paneModel: SettingsPaneModel
    @ObservedObject var themeStore: ThemeStore
    @State var apiKeyDraft = ""
    @State var saveResult: String?

    /// 外观页「新」胶囊：窗口打开时读一次配置，打开过外观页即写入并隐藏。
    @State var appearancePaneSeen = false

    /// 按键映射页的作用范围：nil = 默认表，否则是应用的 bundle identifier。
    @State var mappingScope: String?
    /// 遥控器图上选中的按键。
    @State var selectedButton: RemoteButton?
    /// 输入监控权限的展示值。TCC 状态是进程外存储的，只在出现时查一次会显示
    /// 过期结果——所以存进 @State，在窗口出现和 App 重新激活（用户从系统设置
    /// 授权回来）时刷新。
    @State var inputMonitoringGranted = false

    // 改写页的草稿状态（LLM 服务商与自定义模式编辑）。
    @State var llmTemplateID = "custom"
    @State var llmProtoDraft: LLMProviderConfig.Proto = .openai
    @State var llmBaseURLDraft = ""
    @State var llmKeyDraft = ""
    @State var llmModelDraft = ""
    /// 非 nil 时显示模式提示词编辑 sheet（内置与自定义模式共用）。
    @State var modeEditorTarget: ModeEditorTarget?

    /// 关键词纠正的新增草稿（识别 Tab）。
    @State var keywordFromDraft = ""
    @State var keywordToDraft = ""

    /// 权限状态的展示值（遥控器页）。随窗口出现与 App 重新激活刷新，理由同
    /// `inputMonitoringGranted`。
    @State var accessibilityGranted = false
    @State var eventPostingGranted = false

    /// 模式编辑对象：内置模式只调 prompt（存为覆盖），自定义模式名称 prompt 都可改。
    struct ModeEditorTarget: Identifiable {
        let mode: RewriteMode
        let isBuiltin: Bool
        let hasOverride: Bool
        var id: String { mode.id }
    }

    var body: some View {
        // 窗口高度各页统一，内容超出由这里滚动。按页设 id：切页回到顶部，
        // 不沿用上一页的滚动位置。切页只做淡入淡出，不滑动（与系统设置一致，F）。
        ScrollView {
            Group {
                switch paneModel.pane {
                case .recognition: recognitionTab
                case .rewrite: rewriteTab
                case .keyMapping: keyMappingTab
                case .remote: remoteTab
                case .appearance:
                    SettingsAppearanceView(themeStore: themeStore)
                case .about: aboutTab
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .id(paneModel.pane)
        .transition(.opacity)
        .animation(Motion.quick, value: paneModel.pane)
        .tint(Color.brandAccent)
        .onAppear {
            loadLLMDrafts()
            appearancePaneSeen = Config.load().appearancePaneSeen ?? false
            markAppearancePaneSeenIfNeeded()
        }
        .onChange(of: paneModel.pane) { markAppearancePaneSeenIfNeeded() }
        .sheet(item: $modeEditorTarget) { target in
            CustomModeEditor(
                draft: target.mode,
                title: target.isBuiltin ? "调整提示词：\(target.mode.name)" : nil,
                nameEditable: !target.isBuiltin,
                deleteLabel: target.isBuiltin ? "恢复默认" : "删除",
                onSave: { mode in
                    if target.isBuiltin {
                        coordinator.saveBuiltinPrompt(mode.id, prompt: mode.prompt)
                    } else {
                        coordinator.saveCustomMode(mode)
                    }
                    modeEditorTarget = nil
                },
                onDelete: (target.isBuiltin && !target.hasOverride) ? nil : {
                    if target.isBuiltin {
                        coordinator.resetBuiltinPrompt(target.mode.id)
                    } else {
                        coordinator.deleteCustomMode(target.mode.id)
                    }
                    modeEditorTarget = nil
                },
                onCancel: { modeEditorTarget = nil }
            )
        }
    }

    // MARK: - 豆包 Key 保存（识别 Tab 使用）

    func saveKey() {
        do {
            var cfg = Config.load()
            cfg.doubaoAPIKey = apiKeyDraft
            try Config.save(cfg)
            apiKeyDraft = ""
            saveResult = "已保存"
        } catch {
            saveResult = error.localizedDescription
        }
    }

    // MARK: - 外观页「新」标记

    /// 第一次打开外观页即写入配置（与 ThemeStore.persist 同一读—改—写模式），
    /// 侧栏「新」胶囊随 `appearancePaneSeen` 状态隐藏。
    private func markAppearancePaneSeenIfNeeded() {
        guard paneModel.pane == .appearance, !appearancePaneSeen else { return }
        appearancePaneSeen = true
        // 侧栏收到通知即隐藏「新」胶囊（窗口控制器桥接侧栏 rootView）。
        NotificationCenter.default.post(name: .settingsAppearancePaneSeen, object: nil)
        do {
            var cfg = Config.load()
            cfg.appearancePaneSeen = true
            try Config.save(cfg)
        } catch {
            Log.settings.error("appearance-seen flag save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 关于

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            heroCard

            HStack(alignment: .top, spacing: Spacing.intra) {
                stepCard(number: "01 · 按住", title: "按住语音键",
                         detail: "光标放进任意输入框，按住遥控器上的语音键。")
                stepCard(number: "02 · 说话", title: "正常说话",
                         detail: "浮条显示正在听；想中途放弃，按返回键。")
                stepCard(number: "03 · 松手", title: "文字写入",
                         detail: "松开后自动转写并写入，不会替你按回车。")
            }

            SettingsGroup(title: "链接",
                          footer: "通用模式不会自动发送消息。终端场景尚未验证，不在兼容承诺内。") {
                SettingsRow(icon: "curlybraces", title: "项目主页",
                            subtitle: "github.com/taliove/mi-vibe") {
                    Button("打开…") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/taliove/mi-vibe")!)
                    }
                    .controlSize(.small)
                }
                RowDivider()
                SettingsRow(icon: "doc.text", title: "发布说明",
                            subtitle: "查看本版本的变化与安装说明") {
                    Button("打开…") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/taliove/mi-vibe/releases/latest")!)
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(Spacing.page)
    }

    /// 品牌头图：应用图标 + 字标 + 标语（后半句主题色）+ 版本。
    private var heroCard: some View {
        VStack(spacing: 6) {
            ThemedAppIcon(size: 84)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 8)
            Text("MiVibe")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .padding(.top, 6)
            (Text("按住说话，") + Text("松手成文。").foregroundStyle(Color.brandAccent))
                .font(.callout)
            Text("版本 \(Self.versionString) · \(Self.archString)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
    }

    private func stepCard(number: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(number)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.brandAccent)
            Text(title)
                .font(.callout.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.rowH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
    }

    /// 版本号读 bundle，不手写——手写的一定会过期。
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version)（\(build)）"
    }

    /// 运行架构：Apple Silicon 或 Intel。
    private static var archString: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return machine.hasPrefix("arm64") ? "Apple Silicon" : "Intel"
    }
}
