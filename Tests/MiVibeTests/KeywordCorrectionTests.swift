import Foundation
import MiVibeCore

/// 关键词纠正的验收。
///
/// 替换顺序写错（短词先替换）会把长词吃成错误的拼接——这是这个功能最容易
/// 悄悄引入的回归，钉成断言。
enum KeywordCorrectionTests {
    static func run() {
        Harness.suite("关键词纠正：确定性替换") {
            let entries = [
                KeywordEntry(from: "考戴克斯", to: "Codex"),
                KeywordEntry(from: "小米书入", to: "小米输入"),
            ]

            Harness.expectEqual(
                KeywordCorrections.apply(text: "你好，这是考戴克斯的测试。", entries: entries),
                "你好，这是Codex的测试。",
                "误识别词被替换为正确写法"
            )
            Harness.expectEqual(
                KeywordCorrections.apply(text: "没有误写的文本", entries: entries),
                "没有误写的文本",
                "不含误写时原文不动"
            )
            Harness.expectEqual(
                KeywordCorrections.apply(text: "考戴克斯和考戴克斯都要换", entries: entries),
                "Codex和Codex都要换",
                "多处出现全部替换"
            )
            // 空表 / 空 from 不影响文本。
            Harness.expectEqual(
                KeywordCorrections.apply(text: "原文", entries: []),
                "原文",
                "空表原文不动"
            )
            Harness.expectEqual(
                KeywordCorrections.apply(text: "原文", entries: [KeywordEntry(from: "", to: "X")]),
                "原文",
                "空误写词被忽略"
            )
        }

        Harness.suite("关键词纠正：长词优先") {
            // "小米" 先于 "小米书入" 替换会把后者吃成 "小米输入入" 之类的错尾巴，
            // 所以实现必须按 from 长度降序替换——与表里的顺序无关。
            let entries = [
                KeywordEntry(from: "小米", to: "大米"),
                KeywordEntry(from: "小米书入", to: "小米输入"),
            ]
            Harness.expectEqual(
                KeywordCorrections.apply(text: "这是小米书入的功能", entries: entries),
                "这是小米输入的功能",
                "长词先替换，短词不吃长词的尾巴"
            )
        }

        Harness.suite("关键词纠正：提示词生成") {
            Harness.expect(KeywordCorrections.llmHint(entries: []).isEmpty, "空表不生成 LLM 提示")
            Harness.expect(
                KeywordCorrections.llmHint(entries: [KeywordEntry(from: "考戴克斯", to: "Codex")])
                    .contains("考戴克斯 → Codex"),
                "LLM 提示包含对照条目"
            )
            Harness.expect(
                KeywordCorrections.vocabularyHint(entries: []) == nil,
                "空表不生成词汇提示"
            )
            Harness.expect(
                KeywordCorrections.vocabularyHint(entries: [KeywordEntry(from: "考戴克斯", to: "Codex")])?
                    .contains("Codex") == true,
                "词汇提示包含正确写法"
            )
        }
    }
}
