import MiVibeCore
import SwiftUI

/// 设置页：工具栏四分页 + 分组表单 + 短标签 + 脚注说明（SPEC §7，原型已验收）。
struct SettingsView: View {
    @ObservedObject var coordinator: Coordinator
    @State private var apiKeyDraft = ""
    @State private var saveResult: String?

    /// 按键映射页的作用范围：nil = 默认表，否则是应用的 bundle identifier。
    @State private var mappingScope: String?
    /// 遥控器图上选中的按键。
    @State private var selectedButton: RemoteButton?
    /// 输入监控权限的展示值。TCC 状态是进程外存储的，只在出现时查一次会显示
    /// 过期结果——所以存进 @State，在窗口出现和 App 重新激活（用户从系统设置
    /// 授权回来）时刷新。
    @State private var inputMonitoringGranted = false

    var body: some View {
        TabView {
            asrTab.tabItem { Label("豆包语音", systemImage: "waveform") }
            remoteTab.tabItem { Label("遥控器", systemImage: "av.remote") }
            keyMappingTab.tabItem { Label("按键映射", systemImage: "keyboard") }
            aboutTab.tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 680, height: 640)
    }

    // MARK: - 豆包语音

    private var asrTab: some View {
        Form {
            Section {
                LabeledContent("API Key:") {
                    HStack(spacing: 8) {
                        SecureField("粘贴 API Key", text: $apiKeyDraft)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                        Button("保存") { saveKey() }
                            .disabled(apiKeyDraft.isEmpty)
                    }
                }
                LabeledContent("状态:") {
                    Text(saveResult ?? (Config.isConfigured ? "已配置" : "未配置"))
                        .foregroundStyle(Config.isConfigured ? Color.green : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledContent("二遍识别:") {
                    Toggle("", isOn: Binding(
                        get: { coordinator.enableNonstream },
                        set: { coordinator.enableNonstream = $0 }
                    ))
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text("Key 存在 ~/.config/mivibe/config.json（明文）。二遍识别换来更准的标点分句，尾延迟约 +0.6s（实测 0.77s）。")
            }

            Section {
                LabeledContent("申请 Key:") {
                    Button("打开语音控制台…") {
                        NSWorkspace.shared.open(URL(string:
                            "https://console.volcengine.com/speech/new/setting/apikeys?projectName=default")!)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func saveKey() {
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

    // MARK: - 遥控器

    private var remoteTab: some View {
        Form {
            Section {
                LabeledContent("连接状态:") {
                    HStack(spacing: 6) {
                        Circle().fill(coordinator.link.color).frame(width: 8, height: 8)
                        Text(coordinator.link.rawValue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledContent("系统蓝牙:") {
                    Button("打开蓝牙设置…") { Permissions.openBluetoothSettings() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text("未配对时按遥控器说明书进入配对状态，再到系统蓝牙设置中选择「小米蓝牙语音遥控器」。")
            }

            Section {
                LabeledContent("辅助功能:") {
                    statusRow(ok: Permissions.hasAccessibility(), label: "写入文字所需")
                }
                LabeledContent("事件投递:") {
                    statusRow(ok: Permissions.hasEventPosting(), label: "粘贴降级所需")
                }
                LabeledContent("权限设置:") {
                    Button("打开隐私与安全性…") { Permissions.openAccessibilitySettings() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text("只需要这两项。不需要屏幕录制、自动化或全局键盘监听。")
            }
        }
        .formStyle(.grouped)
    }

    private func statusRow(ok: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(ok ? "已授权" : "未授权（\(label)）")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 按键映射

    /// 当前作用范围实际生效的映射表（应用未配置时回落默认表）。
    private var effectiveMapping: AppMapping {
        coordinator.keyMap.mapping(forBundleID: mappingScope)
    }

    private var keyMappingTab: some View {
        HStack(alignment: .top, spacing: 16) {
            // 左侧：遥控器图，点击选择要配置的按键
            RemoteControlView(
                selected: $selectedButton,
                configured: effectiveMapping.mappedButtons
            )
            .frame(width: 150)
            .padding(.leading, 12)
            .padding(.vertical, 12)

            // 右侧：接管开关、作用范围、预设与按键编辑
            Form {
                takeoverSection
                scopeSection
                presetSection
                buttonSection
            }
            .formStyle(.grouped)
        }
        .onAppear { refreshInputMonitoring() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in refreshInputMonitoring() }
    }

    private func refreshInputMonitoring() {
        inputMonitoringGranted = Permissions.hasInputMonitoring()
    }

    private var takeoverSection: some View {
        Section {
            LabeledContent("按键接管:") {
                Toggle("", isOn: Binding(
                    get: { coordinator.keyTakeover },
                    set: { on in
                        // 独占需要「输入监控」权限，开启时顺手发起请求（未决定才会弹）。
                        if on && !Permissions.hasInputMonitoring() {
                            Permissions.requestInputMonitoring()
                        }
                        coordinator.setKeyTakeover(on)
                    }
                ))
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            LabeledContent("输入监控:") {
                HStack(spacing: 6) {
                    Image(systemName: inputMonitoringGranted
                          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(inputMonitoringGranted ? Color.green : Color.orange)
                    Text(inputMonitoringGranted ? "已授权" : "未授权")
                    Button("去授权…") { Permissions.openInputMonitoringSettings() }
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if coordinator.keyTakeover {
                LabeledContent("接管状态:") {
                    HStack(spacing: 6) {
                        Image(systemName: coordinator.keyTakeoverActive
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(coordinator.keyTakeoverActive ? Color.green : Color.orange)
                        Text(coordinator.keyTakeoverActive ? "生效中" : "未生效（已退回仅监听）")
                        if !coordinator.keyTakeoverActive {
                            Button("重试") { coordinator.retryTakeover() }
                                .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } footer: {
            Text("接管后遥控器所有按键由 MiVibe 处置：映射键合成快捷键，未映射的键原样转发，语音键保留按住说话。关闭则系统恢复原生处理（只剩返回键取消录音）。")
        }
    }

    private var scopeSection: some View {
        Section {
            LabeledContent("作用范围:") {
                Picker("", selection: $mappingScope) {
                    Text("默认（所有应用）").tag(String?.none)
                    ForEach(configuredAppIDs, id: \.self) { bundleID in
                        Text(appName(for: bundleID)).tag(String?.some(bundleID))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            LabeledContent("添加应用:") {
                Menu("选择正在运行的应用…") {
                    ForEach(candidateApps, id: \.bundleIdentifier) { app in
                        Button {
                            guard let bundleID = app.bundleIdentifier else { return }
                            // 先克隆一份默认表作为该应用的起点，再切过去编辑。
                            coordinator.ensureAppMapping(bundleID)
                            mappingScope = bundleID
                        } label: {
                            Label {
                                Text(app.localizedName ?? app.bundleIdentifier!)
                            } icon: {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                }
                            }
                        }
                    }
                }
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let scope = mappingScope, coordinator.keyMap.hasMapping(forBundleID: scope) {
                LabeledContent("专用配置:") {
                    Button("移除，回落到默认表") {
                        coordinator.removeAppMapping(scope)
                        mappingScope = nil
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } footer: {
            Text("应用专用映射整体替换默认表：首次为某应用配置时以当前默认表为底克隆一份，之后两者互不影响。")
        }
    }

    private var presetSection: some View {
        Section {
            ForEach(KeyMapPreset.all) { preset in
                LabeledContent("\(preset.name):") {
                    HStack(spacing: 8) {
                        Text(preset.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("套用") { coordinator.applyPreset(preset, to: mappingScope) }
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } footer: {
            Text("预设写入当前作用范围，只覆盖预设里列出的键；套用后仍可逐键修改。")
        }
    }

    private var buttonSection: some View {
        Section {
            if let button = selectedButton {
                LabeledContent("\(button.displayName)键:") {
                    HStack(spacing: 8) {
                        ShortcutRecorder(shortcut: effectiveMapping[button]) { shortcut in
                            coordinator.setShortcut(shortcut, for: button, in: mappingScope)
                        }
                        if effectiveMapping[button] != nil {
                            Button("清除") {
                                coordinator.setShortcut(nil, for: button, in: mappingScope)
                            }
                            .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("点击左侧遥控器上的按键进行配置。")
                    .foregroundStyle(.secondary)
            }

            if !effectiveMapping.shortcuts.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(RemoteButton.mappable.filter { effectiveMapping[$0] != nil }, id: \.id) { button in
                    LabeledContent("\(button.displayName):") {
                        Text(effectiveMapping[button]?.display ?? "")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedButton = button }
                }
            }
        } footer: {
            Text("录音/转写进行中，返回键优先用于取消，不触发映射。未映射的键保持系统原生行为。")
        }
    }

    // MARK: - 应用解析

    /// 已配置过专用映射的应用，按显示名排序。
    private var configuredAppIDs: [String] {
        coordinator.keyMap.perApp.keys.sorted { appName(for: $0) < appName(for: $1) }
    }

    /// 可加配置的应用：正在运行的常规应用，排除自己。
    private var candidateApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && $0.bundleIdentifier != nil
                    && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func appName(for bundleID: String) -> String {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?
            .localizedName ?? bundleID
    }

    // MARK: - 关于

    private var aboutTab: some View {
        Form {
            Section {
                LabeledContent("MiVibe:") {
                    Text("第一版").frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledContent("用法:") {
                    Text("按住遥控器语音键说话，松开即写入当前输入框")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text("通用模式不会自动发送消息。终端场景尚未验证，不在兼容承诺内。")
            }
        }
        .formStyle(.grouped)
    }
}
