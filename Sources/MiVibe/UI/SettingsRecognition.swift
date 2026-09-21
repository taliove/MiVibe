import MiVibeCore
import SwiftUI

/// 「识别」Tab：识别引擎选择 + 豆包配置 + 本地模型下载管理。
extension SettingsView {

    var recognitionTab: some View {
        Form {
            Section {
                LabeledContent("识别引擎:") {
                    Picker("", selection: Binding(
                        get: { coordinator.asrEngine },
                        set: { coordinator.setASREngine($0) }
                    )) {
                        ForEach(ASREngine.allCases, id: \.self) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text(coordinator.asrEngine == .local
                     ? "本地识别完全离线，音频不出本机。识别失败不会自动回退云端。"
                     : "豆包语音为云端服务，按使用量计费。")
            }

            if coordinator.asrEngine == .doubao {
                doubaoSection
            } else {
                localSection
            }

            keywordSection
        }
        .formStyle(.grouped)
    }

    // MARK: - 关键词纠正

    private var keywordSection: some View {
        Section {
            ForEach(coordinator.keywords) { entry in
                LabeledContent {
                    Button {
                        coordinator.deleteKeyword(entry.id)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack(spacing: 6) {
                        Text(entry.from)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.to)
                            .fontWeight(.medium)
                    }
                }
            }

            LabeledContent("误识别:") {
                TextField("例如：考戴克斯", text: $keywordFromDraft)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LabeledContent("正确写法:") {
                HStack(spacing: 8) {
                    TextField("例如：Codex", text: $keywordToDraft)
                        .labelsHidden()
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("关键词纠正")
        } footer: {
            Text("语音识别对专有名词、术语的误写是系统性的。对照表在转写完成后立即替换（两个引擎、「原文直出」都生效）；正确词表也会提示本地引擎与 LLM 改写按表纠正。")
        }
    }

    // MARK: - 豆包语音

    private var doubaoSection: some View {
        Group {
            Section {
                LabeledContent("API Key:") {
                    HStack(spacing: 8) {
                        SecureField("粘贴 API Key", text: $apiKeyDraft)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
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
    }

    // MARK: - 本地识别

    private var localSection: some View {
        Group {
            Section {
                LabeledContent("本机配置:") {
                    Text(String(format: "%.0f GB 内存 · %@", HardwareProfile.memoryGB,
                                HardwareProfile.isAppleSilicon ? "Apple Silicon" : "Intel"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                Text("推荐档位按内存与芯片给出，只是建议——任何档位都可以自由下载使用。")
            }

            Section {
                ForEach(ModelCatalog.all) { model in
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
            } footer: {
                Text("模型保存在 ~/Library/Application Support/MiVibe/models。首次本地识别需编译 GPU 内核，较慢（约 15 秒），之后恢复正常。")
            }
        }
    }
}

/// 单个模型行：下载状态 + 推荐徽标 + 选用。
private struct ModelRow: View {
    let model: ModelCatalog.Model
    @ObservedObject var store: ModelStore
    let isRecommended: Bool
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                actionView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 6) {
                Text(model.displayName)
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
        }
    }

    @ViewBuilder
    private var actionView: some View {
        // 布局约定：左边固定是状态对应的操作按钮，右边固定是模型的速度/质量描述，
        // 每行结构一致，扫一眼按钮列就知道每个模型的状态。
        HStack(spacing: 8) {
            controls
            Spacer(minLength: 8)
            Text("\(model.speedNote) · \(model.qualityNote)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var controls: some View {
        switch store.states[model.id] ?? .notDownloaded {
        case .notDownloaded:
            Button("下载") { store.download(model) }
                .controlSize(.small)
        case .downloading(let progress):
            ProgressView(value: progress)
                .frame(width: 100)
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .monospacedDigit()
            Button("取消") { store.cancelDownload(model) }
                .controlSize(.small)
        case .downloaded:
            Button {
                onSelect()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    Text(isActive ? "使用中" : "使用")
                }
            }
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
