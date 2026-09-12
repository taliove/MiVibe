import MiVibeCore
import SwiftUI

/// 设置页：工具栏三分页 + 分组表单 + 短标签 + 脚注说明（SPEC §7，原型已验收）。
struct SettingsView: View {
    @ObservedObject var coordinator: Coordinator
    @State private var apiKeyDraft = ""
    @State private var saveResult: String?

    var body: some View {
        TabView {
            asrTab.tabItem { Label("豆包语音", systemImage: "waveform") }
            remoteTab.tabItem { Label("遥控器", systemImage: "av.remote") }
            aboutTab.tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 400)
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
                    Text(saveResult ?? (Credentials.isConfigured ? "已配置" : "未配置"))
                        .foregroundStyle(Credentials.isConfigured ? Color.green : Color.secondary)
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
                Text("Key 只存入本机钥匙串。二遍识别换来更准的标点分句，尾延迟约 +0.6s（实测 0.77s）。")
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
            try Credentials.save(apiKey: apiKeyDraft)
            apiKeyDraft = ""
            saveResult = "已保存到钥匙串"
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
