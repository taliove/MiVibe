import MiVibeCore
import SwiftUI

/// 「改写」Tab：改写模式管理 + LLM 服务商配置。
extension SettingsView {

    var rewriteTab: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            PageHeader(subtitle: "转写完成后、注入前交给语言模型处理；可自定义模式与服务商。")

            modeGroup
            customModeGroup
            llmGroup
        }
        .padding(Spacing.page)
    }

    // MARK: - 模式选择

    private var modeGroup: some View {
        SettingsGroup(title: "改写模式",
                      footer: "「原文直出」不调用 LLM。点铅笔可查看并调整每个模式的提示词；内置模式的调整存为覆盖，可恢复默认。遥控器菜单键可呼出模式选单快速切换。") {
            ForEach(Array(allModeRows.enumerated()), id: \.element.id) { index, row in
                if index != 0 { RowDivider() }
                modeRow(row)
            }
        }
    }

    private func modeRow(_ row: ModeRow) -> some View {
        HStack(spacing: Spacing.intra) {
            Button {
                coordinator.selectMode(row.id)
            } label: {
                HStack(spacing: Spacing.intra) {
                    Image(systemName: row.id == coordinator.rewrite.effectiveActiveMode
                          ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(row.id == coordinator.rewrite.effectiveActiveMode
                                         ? Color.brandAccent : Color.secondary)
                        .frame(width: 20)
                    Text(row.name)
                        .foregroundStyle(.primary)
                    if row.isCustom {
                        Text("自定义")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if row.hasOverride {
                        Text("已调整")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.brandAttention.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.brandAttention)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            // 查看/调整提示词：内置与自定义模式都开放（原文直出没有 prompt）。
            if row.id != RewriteModes.rawID {
                Button {
                    modeEditorTarget = row.editorTarget(coordinator: coordinator)
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("查看/调整提示词")
            }
        }
        .padding(.horizontal, Spacing.rowH)
        .padding(.vertical, Spacing.rowV)
        .frame(minHeight: Spacing.rowMinHeight)
    }

    private struct ModeRow: Identifiable {
        let id: String
        let name: String
        let isCustom: Bool
        let hasOverride: Bool

        @MainActor
        func editorTarget(coordinator: Coordinator) -> SettingsView.ModeEditorTarget {
            if isCustom {
                let mode = coordinator.rewrite.effectiveCustomModes.first { $0.id == id }
                    ?? RewriteMode(id: id, name: name, prompt: "")
                return .init(mode: mode, isBuiltin: false, hasOverride: false)
            }
            return .init(
                mode: RewriteMode(id: id, name: name, prompt: coordinator.effectiveBuiltinPrompt(id)),
                isBuiltin: true, hasOverride: hasOverride)
        }
    }

    private var allModeRows: [ModeRow] {
        [ModeRow(id: RewriteModes.rawID, name: "原文直出", isCustom: false, hasOverride: false)]
            + RewriteModes.builtins.map {
                ModeRow(id: $0.id, name: $0.name, isCustom: false,
                        hasOverride: coordinator.rewrite.effectiveBuiltinPrompts[$0.id] != nil)
            }
            + coordinator.rewrite.effectiveCustomModes.map {
                ModeRow(id: $0.id, name: $0.name, isCustom: true, hasOverride: false)
            }
    }

    // MARK: - 自定义模式

    private var customModeGroup: some View {
        SettingsGroup(title: "自定义模式",
                      footer: "自定义模式只需描述想要的处理（例如「改成邮件语气」），系统会自动附加「只输出处理后文本」的约束。点击上方列表里自定义模式的铅笔进行编辑或删除。") {
            SettingsPlainRow {
                Button("新建自定义模式…") {
                    modeEditorTarget = ModeEditorTarget(
                        mode: RewriteMode(name: "", prompt: ""), isBuiltin: false, hasOverride: false)
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - LLM 服务商

    private var llmGroup: some View {
        SettingsGroup(title: "LLM 服务商",
                      footer: "支持 OpenAI 兼容与 Anthropic 两种协议。改写请求非流式、5 秒超时；超时或失败时注入原始转写文本，绝不丢弃。") {
            SettingsRow(icon: "square.grid.2x2", title: "服务商模板") {
                Picker("", selection: Binding(
                    get: { llmTemplateID },
                    set: { applyLLMTemplate($0) }
                )) {
                    ForEach(Self.llmTemplates) { t in
                        Text(t.name).tag(t.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if llmTemplateID == "custom" {
                RowDivider()
                SettingsRow(icon: "network", title: "协议") {
                    Picker("", selection: $llmProtoDraft) {
                        Text("OpenAI 兼容").tag(LLMProviderConfig.Proto.openai)
                        Text("Anthropic").tag(LLMProviderConfig.Proto.anthropic)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            RowDivider()
            SettingsRow(icon: "link", title: "接口地址") {
                TextField("https://api.openai.com/v1", text: $llmBaseURLDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Spacing.fieldWidth)
            }
            RowDivider()
            SettingsRow(icon: "key.fill", title: "API Key") {
                SecureField("sk-…", text: $llmKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Spacing.fieldWidth)
            }
            RowDivider()
            SettingsRow(icon: "cpu", title: "模型") {
                TextField("gpt-4o-mini", text: $llmModelDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Spacing.fieldWidth)
            }
            RowDivider()
            SettingsRow(icon: "info.circle", title: "状态",
                        subtitle: llmStatusText) {
                Button("保存") { saveLLMProvider() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(llmBaseURLDraft.isEmpty || llmModelDraft.isEmpty)
            }
        }
    }

    private var llmStatusText: String {
        if coordinator.rewrite.provider?.isComplete == true { return "已配置" }
        if coordinator.rewrite.effectiveActiveMode != RewriteModes.rawID {
            return "未配置完整，当前模式将按原文直出"
        }
        return "未配置"
    }

    // MARK: - 模板与草稿

    struct LLMTemplate: Identifiable {
        let id: String
        let name: String
        let proto: LLMProviderConfig.Proto
        let baseURL: String
        let model: String
    }

    static let llmTemplates: [LLMTemplate] = [
        LLMTemplate(id: "custom", name: "自定义", proto: .openai, baseURL: "", model: ""),
        LLMTemplate(id: "openai", name: "OpenAI", proto: .openai,
                    baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini"),
        LLMTemplate(id: "anthropic", name: "Anthropic", proto: .anthropic,
                    baseURL: "https://api.anthropic.com", model: "claude-haiku-4-5-20251001"),
        LLMTemplate(id: "deepseek", name: "DeepSeek", proto: .openai,
                    baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat"),
        LLMTemplate(id: "ollama", name: "Ollama（本地）", proto: .openai,
                    baseURL: "http://localhost:11434/v1", model: "qwen3:4b"),
    ]

    /// 从已保存配置初始化草稿（窗口出现时调用）。
    func loadLLMDrafts() {
        let p = coordinator.rewrite.provider
        llmBaseURLDraft = p?.baseURL ?? ""
        llmKeyDraft = p?.apiKey ?? ""
        llmModelDraft = p?.model ?? ""
        llmProtoDraft = p?.effectiveProto ?? .openai
        llmTemplateID = Self.llmTemplates.first {
            $0.id != "custom" && $0.baseURL == p?.baseURL
        }?.id ?? "custom"
    }

    private func applyLLMTemplate(_ id: String) {
        llmTemplateID = id
        guard let t = Self.llmTemplates.first(where: { $0.id == id }), id != "custom" else { return }
        llmProtoDraft = t.proto
        llmBaseURLDraft = t.baseURL
        llmModelDraft = t.model
        // 换模板不换 Key：已保存的 Key 保留，模板只填地址与模型。
    }

    private func saveLLMProvider() {
        coordinator.setLLMProvider(LLMProviderConfig(
            proto: llmProtoDraft.rawValue,
            baseURL: llmBaseURLDraft.trimmingCharacters(in: .whitespaces),
            apiKey: llmKeyDraft.trimmingCharacters(in: .whitespaces),
            model: llmModelDraft.trimmingCharacters(in: .whitespaces)
        ))
    }
}
