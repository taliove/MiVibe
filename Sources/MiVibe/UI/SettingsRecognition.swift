import MiVibeCore
import SwiftUI

/// 「识别」Tab：识别引擎选择 + 豆包配置 + 本地模型下载管理 + 关键词纠正。
extension SettingsView {

    var recognitionTab: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            PageHeader(subtitle: "选择识别引擎，管理 API Key、本地模型与关键词纠正。")

            engineGroup

            if coordinator.asrEngine == .doubao {
                doubaoGroup
            } else {
                localGroup
            }

            keywordGroup
        }
        .padding(Spacing.page)
    }

    // MARK: - 识别引擎

    private var engineGroup: some View {
        SettingsGroup(title: "识别引擎",
                      footer: coordinator.asrEngine == .local
                      ? "本地识别完全离线，音频不出本机。识别失败不会自动回退云端。"
                      : "豆包语音为云端服务，按使用量计费。") {
            SettingsPlainRow {
                Picker("", selection: Binding(
                    get: { coordinator.asrEngine },
                    set: { coordinator.setASREngine($0) }
                )) {
                    ForEach(ASREngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    // MARK: - 关键词纠正

    private var keywordGroup: some View {
        SettingsGroup(title: "关键词纠正",
                      footer: "语音识别对专有名词、术语的误写是系统性的。对照表在转写完成后立即替换（两个引擎、「原文直出」都生效）；正确词表也会提示本地引擎与 LLM 改写按表纠正。") {
            ForEach(Array(coordinator.keywords.enumerated()), id: \.element.id) { index, entry in
                if index != 0 { RowDivider() }
                SettingsRow(icon: "character", title: entry.from) {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.to)
                                .fontWeight(.medium)
                        }
                        Button {
                            coordinator.deleteKeyword(entry.id)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("删除这条纠正")
                    }
                }
            }
            if !coordinator.keywords.isEmpty { RowDivider() }
            SettingsPlainRow {
                HStack(spacing: 8) {
                    TextField("误识别，例如：考戴克斯", text: $keywordFromDraft)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("正确写法，例如：Codex", text: $keywordToDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("添加") {
                        coordinator.addKeyword(from: keywordFromDraft, to: keywordToDraft)
                        keywordFromDraft = ""
                        keywordToDraft = ""
                    }
                    .controlSize(.small)
                    .disabled(keywordFromDraft.trimmingCharacters(in: .whitespaces).isEmpty
                              || keywordToDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - 豆包语音

    private var doubaoGroup: some View {
        SettingsGroup(title: "豆包语音",
                      footer: "Key 存在 ~/.config/mivibe/config.json（明文）。二遍识别换来更准的标点分句，尾延迟约 +0.6s（实测 0.77s）。") {
            SettingsRow(icon: "key.fill", title: "API Key",
                        subtitle: saveResult ?? (Config.isConfigured ? "已配置" : "未配置")) {
                HStack(spacing: 8) {
                    SecureField("粘贴 API Key", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    Button("保存") { saveKey() }
                        .controlSize(.small)
                        .disabled(apiKeyDraft.isEmpty)
                }
            }
            RowDivider()
            SettingsRow(icon: "checkmark.circle", title: "二遍识别",
                        subtitle: "更准的标点分句，尾延迟约 +0.6s") {
                Toggle("", isOn: Binding(
                    get: { coordinator.enableNonstream },
                    set: { coordinator.enableNonstream = $0 }
                ))
                .labelsHidden()
            }
            RowDivider()
            SettingsRow(icon: "link", title: "申请 Key",
                        subtitle: "火山引擎语音控制台") {
                Button("打开…") {
                    NSWorkspace.shared.open(URL(string:
                        "https://console.volcengine.com/speech/new/setting/apikeys?projectName=default")!)
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - 本地识别

    private var localGroup: some View {
        SettingsGroup(title: "本地识别",
                      footer: "模型保存在 ~/Library/Application Support/MiVibe/models。首次本地识别需编译 GPU 内核，较慢（约 15 秒），之后恢复正常。推荐档位按内存与芯片给出，只是建议——任何档位都可以自由下载使用。") {
            SettingsRow(icon: "memorychip", title: "本机配置",
                        subtitle: String(format: "%.0f GB 内存 · %@", HardwareProfile.memoryGB,
                                         HardwareProfile.isAppleSilicon ? "Apple Silicon" : "Intel"))
            RowDivider()
            ForEach(Array(ModelCatalog.all.enumerated()), id: \.element.id) { index, model in
                if index != 0 { RowDivider() }
                ModelRow(
                    model: model,
                    store: coordinator.modelStore,
                    isRecommended: model.id == HardwareProfile.recommendedModelID,
                    isActive: coordinator.localModelID == model.id,
                    onSelect: { coordinator.setLocalModel(model.id) },
                    onDelete: {
                        // 删掉正在使用的模型时一并清掉选用，避免配置指向不存在的文件。
                        if coordinator.localModelID == model.id { coordinator.setLocalModel(nil) }
                        try? coordinator.modelStore.delete(model)
                    }
                )
            }
        }
    }
}

/// 单个模型行：选用状态 + 推荐徽标 + 下载/选用操作。
private struct ModelRow: View {
    let model: ModelCatalog.Model
    @ObservedObject var store: ModelStore
    let isRecommended: Bool
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Spacing.intra) {
            Image(systemName: stateIcon)
                .foregroundStyle(stateIconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(model.displayName).font(.body)
                    Text(model.sizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isRecommended {
                        Text("推荐")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text("\(model.speedNote) · \(model.qualityNote)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            controls
        }
        .padding(.horizontal, Spacing.rowH)
        .padding(.vertical, Spacing.rowV)
        .frame(minHeight: Spacing.rowMinHeight)
    }

    private var stateIcon: String {
        switch store.states[model.id] ?? .notDownloaded {
        case .notDownloaded: return "arrow.down.circle"
        case .downloading: return "arrow.down.circle.fill"
        case .downloaded: return isActive ? "checkmark.circle.fill" : "circle"
        case .failed: return "exclamationmark.circle"
        }
    }

    private var stateIconColor: Color {
        switch store.states[model.id] ?? .notDownloaded {
        case .downloaded: return isActive ? Color.accentColor : Color.secondary
        case .failed: return Color.red
        default: return Color.secondary
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch store.states[model.id] ?? .notDownloaded {
        case .notDownloaded:
            Button("下载") { store.download(model) }
                .controlSize(.small)
        case .downloading(let progress):
            ProgressView(value: progress)
                .frame(width: 80)
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .monospacedDigit()
            Button("取消") { store.cancelDownload(model) }
                .controlSize(.small)
        case .downloaded:
            Button(isActive ? "使用中" : "使用") { onSelect() }
                .controlSize(.small)
                .disabled(isActive)
            Button("删除") { onDelete() }
                .controlSize(.small)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
            Button("重试") { store.download(model) }
                .controlSize(.small)
        }
    }
}
