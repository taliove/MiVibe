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
                SettingsRow(icon: coordinator.link.icon, iconColor: coordinator.link.color,
                            title: "连接状态", subtitle: coordinator.link.rawValue)
                RowDivider()
                SettingsRow(icon: "antenna.radiowaves.left.and.right",
                            title: "系统蓝牙", subtitle: "配对与回连在系统侧完成") {
                    Button("打开蓝牙设置…") { Permissions.openBluetoothSettings() }
                        .controlSize(.small)
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
                .foregroundStyle(light == .ok ? Color.green
                                 : (light == .pending ? Color.secondary : Color.red))
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
                    .foregroundStyle(light == .pending ? Color.secondary : Color.orange)
            }
        }
        .padding(.horizontal, Spacing.rowH)
        .padding(.vertical, Spacing.rowV)
    }

    func permissionRow(ok: Bool, title: String, need: String) -> some View {
        SettingsRow(icon: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    iconColor: ok ? Color.green : Color.orange,
                    title: title, subtitle: ok ? "已授权" : "未授权（\(need)）")
    }

    // MARK: - 按键接管

    func refreshInputMonitoring() {
        inputMonitoringGranted = Permissions.hasInputMonitoring()
    }

    var takeoverGroup: some View {
        SettingsGroup(title: "按键接管",
                      footer: coordinator.keyTakeover && !coordinator.keyTakeoverActive
                      ? "接管后遥控器所有按键由 MiVibe 处置。注意：「输入监控」条目在但开关关着时这里也会显示已授权——独占被拒请到系统设置把 MiVibe 的开关关掉再打开，App 激活时会自动重试接管。"
                      : "接管后遥控器所有按键由 MiVibe 处置：映射键合成快捷键，未映射的键原样转发，语音键保留按住说话。关闭则系统恢复原生处理（只剩返回键取消录音）。") {
            SettingsRow(icon: "hand.raised.fill", title: "接管遥控器按键",
                        subtitle: "需要「输入监控」权限") {
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
            }
            RowDivider()
            SettingsRow(icon: inputMonitoringGranted
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        iconColor: inputMonitoringGranted ? Color.green : Color.orange,
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
                            iconColor: coordinator.keyTakeoverActive ? Color.green : Color.orange,
                            title: "接管状态",
                            subtitle: coordinator.keyTakeoverActive ? "生效中" : "未生效（已退回仅监听）") {
                    if !coordinator.keyTakeoverActive {
                        HStack(spacing: 8) {
                            Button("重试") { coordinator.retryTakeover() }
                                .controlSize(.small)
                            Button("去授权…") { Permissions.openInputMonitoringSettings() }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}
