import Foundation

/// 关键词纠正（见 CONTEXT.md）：用户维护的「误识别 → 正确写法」对照表。
///
/// 语音识别对专有名词、技术术语的误写是系统性的（每次都错成同一个词），
/// 所以一张小小的对照表就能把体感准确率拉上去一大截。
public struct KeywordEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// 误识别出来的样子（如 "考戴克斯"）。
    public var from: String
    /// 正确的写法（如 "Codex"）。
    public var to: String

    public init(id: String = UUID().uuidString, from: String, to: String) {
        self.id = id
        self.from = from
        self.to = to
    }
}

public enum KeywordCorrections {
    /// 转写完成后的确定性替换：按表把误识别词逐一替换成正确写法。
    ///
    /// 单遍扫描 + 每个位置最长匹配优先：**替换产物绝不再被扫描**。
    /// （简单的"按长度降序 replace"会踩坑：长词的替换结果里若含短词，
    /// 短词接着把产物再改一遍——"小米书入→小米输入"后"小米→大米"会把
    /// 刚写对的"小米输入"再改成"大米输入"。）
    public static func apply(text: String, entries: [KeywordEntry]) -> String {
        let valid = entries
            .filter { !$0.from.isEmpty && $0.from != $0.to }
            .sorted { $0.from.count > $1.from.count }
        guard !valid.isEmpty, !text.isEmpty else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            if let entry = valid.first(where: { text[index...].hasPrefix($0.from) }) {
                result += entry.to
                index = text.index(index, offsetBy: entry.from.count)
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return result
    }

    /// 给 LLM 改写的提示段：附在系统守卫之后，让模型整理时也按表纠正近似错误。
    /// 空表返回空串。
    public static func llmHint(entries: [KeywordEntry]) -> String {
        let valid = entries.filter { !$0.from.isEmpty && !$0.to.isEmpty }
        guard !valid.isEmpty else { return "" }
        let pairs = valid.map { "- \($0.from) → \($0.to)" }.joined(separator: "\n")
        return "\n\n以下词汇是用户的专有名词对照表，语音识别容易误写。如果文本中出现左列或与其近似的写法，请替换为右列：\n\(pairs)"
    }

    /// 给本地识别引擎的词汇提示（whisper initial_prompt）：正确写法的词表。
    /// 空表返回 nil（不传提示，保持引擎默认行为）。
    public static func vocabularyHint(entries: [KeywordEntry]) -> String? {
        let terms = entries.map(\.to).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        return "以下是包含这些词汇的普通话口述：" + terms.joined(separator: "，") + "。"
    }
}
