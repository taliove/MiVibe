import MiVibeCore
import SwiftUI

/// 「遥控器」页：连接状态、按键接管、链路自检、系统权限。
extension SettingsView {

    // MARK: - 遥控器

    var remoteTab: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            PageHeader(subtitle: "连接状态、按键接管，以及写入文字所需的两项系统权限。")

            SettingsGroup(title: "连接",
                          footer: "未配对时按遥控器说明书进入配对状态，再到系统蓝牙设置中选择「小米蓝牙语音遥控器」。") {
                SettingsRow(icon: SettingsRow<EmptyView>.brandMarkIcon,
                            iconColor: coordinator.link == .pairedOffline
                                ? Color.brandNotice.opacity(0.6) : coordinator.link.color,
                            title: "连接状态", subtitle: coordinator.link.rawValue)
                RowDivider()
                SettingsRow(icon: "antenna.radiowaves.left.and.right",
                            title: "系统蓝牙", subtitle: "配对与回连在系统侧完成") {
                    // 未配对时这是用户最可能的下一步，给主按钮样式。
                    if coordinator.link == .unpaired {
                        Button("打开蓝牙设置…") { Permissions.openBluetoothSettings() }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            .tint(Color.brandControlFill)
                    } else {
                        Button("打开蓝牙设置…") { Permissions.openBluetoothSettings() }
                            .controlSize(.small)
                    }
                }
            }

            takeoverGroup

            SettingsGroup(title: "链路自检") {
                checkRow(light: coordinator.link == .connected ? .ok : .bad,
                         title: "遥控器已连接",
                         fix: "没连上：检查电量并靠近 Mac；仍不行就按说明书重新配对。")
                RowDivider()
                checkRow(light: coordinator.lastAudioFrameAt != nil ? .ok : .pending,
                         title: "按语音键有音频帧",
                         fix: "现在按住遥控器语音键说一句话——收到音频即通过；没反应请先确认连接与电量。",
                         pendingText: "待检测")
                RowDivider()
                checkRow(light: engineReady ? .ok : .bad,
                         title: "识别引擎可用",
                         fix: engineFix)
                RowDivider()
                checkRow(light: accessibilityGranted ? .ok : .bad,
                         title: "辅助功能已授权",
                         fix: "在下方「权限」组打开隐私与安全性，勾选 MiVibe 后回来。")
            }

            SettingsGroup(title: "权限",
                          footer: "只需要这两项。不需要屏幕录制、自动化或全局键盘监听。") {
                permissionRow(ok: accessibilityGranted,
                              title: "辅助功能", need: "写入文字所需")
                RowDivider()
                permissionRow(ok: eventPostingGranted,
                              title: "事件投递", need: "粘贴降级所需")
                RowDivider()
                SettingsRow(icon: "gearshape", title: "权限设置") {
                    Button("打开隐私与安全性…") { Permissions.openAccessibilitySettings() }
                        .controlSize(.small)
                }
            }
        }
        .padding(Spacing.page)
        .onAppear { refreshRemotePermissions() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in refreshRemotePermissions() }
    }

    func refreshRemotePermissions() {
        accessibilityGranted = Permissions.hasAccessibility()
        eventPostingGranted = Permissions.hasEventPosting()
        refreshInputMonitoring()
    }

    /// 识别引擎就绪判定：豆包看 Key，本地看有没有选用模型。
    var engineReady: Bool {
        switch coordinator.asrEngine {
        case .doubao: return Config.isConfigured
        case .local: return coordinator.localModelID != nil
        }
    }

    var engineFix: String {
        switch coordinator.asrEngine {
        case .doubao: return "到「识别」页粘贴豆包 API Key 并保存。"
        case .local: return "到「识别」页下载并选用一个本地模型。"
        }
    }

    enum CheckLight { case ok, bad, pending }

    func checkRow(light: CheckLight, title: String, fix: String,
                          pendingText: String = "未通过") -> some View {
        HStack(alignment: .top, spacing: Spacing.intra) {
            Image(systemName: light == .ok ? "checkmark.circle.fill"
                  : (light == .pending ? "circle.dotted" : "xmark.circle.fill"))
                .foregroundStyle(light == .ok ? Color.brandSuccess
                                 : (light == .pending ? Color.secondary : Color.brandError))
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if light != .ok {
                    Text(fix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if light != .ok {
                Text(light == .pending ? pendingText : "未通过")
                    .font(.caption)
                    .foregroundStyle(light == .pending ? Color.secondary : Color.brandAttention)
            }
        }
        .padding(.horizontal, Spacing.rowH)
        .padding(.vertical, Spacing.rowV)
    }

    func permissionRow(ok: Bool, title: String, need: String) -> some View {
        SettingsRow(icon: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    iconColor: ok ? Color.brandSuccess : Color.brandAttention,
                    title: title, subtitle: ok ? "已授权" : "未授权（\(need)）")
    }

    // MARK: - 按键接管

    func refreshInputMonitoring() {
        inputMonitoringGranted = Permissions.hasInputMonitoring()
    }

    private var takeoverStatusText: String {
        if coordinator.keyTakeoverActive { return "生效中" }
        guard let failure = coordinator.takeoverFailure else { return "未生效（等待遥控器连接）" }
        return "未生效：\(failure.reason)"
    }

    private var takeoverFooter: String {
        let normal = "接管后遥控器所有按键由 MiVibe 处置：映射键合成快捷键，未映射的键原样转发，语音键保留按住说话。关闭则系统恢复原生处理（只剩返回键取消录音）。"
        guard coordinator.keyTakeover, !coordinator.keyTakeoverActive else { return normal }
        switch coordinator.takeoverFailure {
        case .notPermitted:
            return "「输入监控」条目在但开关关着时这里也会显示已授权——请到系统设置把 MiVibe 的开关关掉再打开，App 激活时会自动重试接管。"
        case .remapRejected:
            return "系统拒绝为遥控器写入按键重映射，按键仍由系统原生处理。可点「重试」，或断开重连遥控器后再试。"
        case .exclusiveAccess:
            return "遥控器已被其他程序（如按键改键工具）占用，退出该程序后点「重试」。"
        case nil:
            return "等待遥控器连接：连上后自动接管。按键暂由系统原生处理。"
        default:
            return "按键仍由系统原生处理，返回键取消录音照常可用。可点「重试」。"
        }
    }

    var takeoverGroup: some View {
        SettingsGroup(title: "按键接管",
                      footer: takeoverFooter) {
            SettingsRow(icon: "hand.raised.fill", title: "接管遥控器按键",
                        subtitle: "需要「输入监控」权限") {
                Toggle("", isOn: Binding(
                    get: { coordinator.keyTakeover },
                    set: { on in
                        // 读取按键需要「输入监控」权限，开启时顺手发起请求（未决定才会弹）。
                        if on && !Permissions.hasInputMonitoring() {
                            Permissions.requestInputMonitoring()
                        }
                        coordinator.setKeyTakeover(on)
                    }
                ))
                .labelsHidden()
                .tint(Color.brandAccent)
            }
            RowDivider()
            SettingsRow(icon: inputMonitoringGranted
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        iconColor: inputMonitoringGranted ? Color.brandSuccess : Color.brandAttention,
                        title: "输入监控",
                        subtitle: inputMonitoringGranted ? "已授权" : "未授权") {
                if !inputMonitoringGranted {
                    Button("去授权…") { Permissions.openInputMonitoringSettings() }
                        .controlSize(.small)
                }
            }
            if coordinator.keyTakeover {
                RowDivider()
                SettingsRow(icon: coordinator.keyTakeoverActive
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            iconColor: coordinator.keyTakeoverActive ? Color.brandSuccess : Color.brandAttention,
                            title: "接管状态",
                            subtitle: takeoverStatusText) {
                    if !coordinator.keyTakeoverActive {
                        HStack(spacing: 8) {
                            Button("重试") { coordinator.retryTakeover(manual: true) }
                                .controlSize(.small)
                            if coordinator.takeoverFailure?.isRetryable ?? true {
                                Button("去授权…") { Permissions.openInputMonitoringSettings() }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }
            RowDivider()
            SettingsRow(icon: "keyboard", title: "按键提示",
                        subtitle: "按键时在屏幕中央显示键名与执行结果") {
                Toggle("", isOn: $coordinator.keyHints)
                    .labelsHidden()
                    .tint(Color.brandAccent)
            }
        }
    }
}
