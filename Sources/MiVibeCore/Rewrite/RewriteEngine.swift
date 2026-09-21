import Foundation

/// 改写引擎：识别完成后、注入前的一次性整句处理。
///
/// 铁律（见 CONTEXT.md「改写」）：超时或失败静默回落原文，绝不丢弃用户的话。
/// 所以 `apply` 不抛错——所有失败路径都返回原文并记日志。
public enum RewriteEngine {
    /// 按当前配置改写文本。raw 模式、未配置服务商、调用失败、返回为空——都回落原文。
    /// `keywords`：关键词纠正表，注入系统提示让模型按表纠正误识别。
    public static func apply(text: String, config: RewriteConfig,
                             keywords: [KeywordEntry] = []) async -> String {
        let resolved = RewriteModes.resolve(activeID: config.activeMode, custom: config.effectiveCustomModes,
                                            overrides: config.effectiveBuiltinPrompts)
        guard case .llm(let name, let prompt) = resolved else { return text }
        guard let provider = config.provider, provider.isComplete else {
            Log.chain.error("rewrite skipped: mode=\(name) but LLM provider incomplete")
            return text
        }

        let system = RewriteModes.systemGuard + "\n\n" + prompt
            + KeywordCorrections.llmHint(entries: keywords)
        let started = Date()
        do {
            let result = try await LLMClient.complete(system: system, user: text, config: provider)
            Log.chain.notice("rewrite ok mode=\(name) \(text.count)→\(result.count) chars, \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
            return result
        } catch {
            Log.chain.error("rewrite failed mode=\(name): \(error.localizedDescription)，注入原文")
            return text
        }
    }
}
