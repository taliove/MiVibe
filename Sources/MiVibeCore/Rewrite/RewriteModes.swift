import Foundation

/// 内置改写模式。prompt 硬编码在代码里（用户只能改自定义模式），
/// 选中任一非「原文直出」模式即视为启用改写——不存在独立的改写开关。
public enum RewriteModes {
    /// 原文直出的固定 id：不调用 LLM，转写是什么就注入什么。默认模式。
    public static let rawID = "raw"

    public struct Builtin: Sendable, Identifiable, Equatable {
        public let id: String
        public let name: String
        public let prompt: String
    }

    public static let builtins: [Builtin] = [
        Builtin(id: "tidy", name: "转录整理", prompt: """
            整理这段语音听写文本：去除口头禅、重复和结巴，补上正确的标点符号，必要时分段。\
            保持说话人的措辞和语气不变，只做最小修改，绝不改写表达方式或增删信息。
            """),
        Builtin(id: "formal", name: "正式书面", prompt: """
            把这段语音听写文本改写为正式的书面语：可以调整句式和用词使其规范、得体，\
            但不得改变原意，不得增删信息点。
            """),
        Builtin(id: "concise", name: "简洁", prompt: """
            压缩这段语音听写文本中的冗余表达，使其简洁明了。保留全部信息点，不得遗漏。
            """),
        Builtin(id: "translate-en", name: "翻译为英文", prompt: """
            把这段语音听写文本翻译成英文。技术术语、产品名、代码标识符保留原形。\
            只输出译文。
            """),
        Builtin(id: "vibe-coding", name: "Vibe Coding", prompt: """
            这段文字是口述给编程助手的指令。把它整理成清晰、结构化的任务描述：\
            用要点分条列出，保留全部技术名词、标识符、文件名和路径的原形，\
            补全因口语省略而缺失的指代，但不要替用户做任何技术决策、不要添加用户没说的需求。
            """),
    ]

    /// 所有请求的固定系统守卫：用户 prompt（含内置模式）拼在它后面。
    /// 短文本一次性改写场景下这层约束几乎总是想要的——只输出文本本身，
    /// 不解释、不对话、不加引号。
    public static let systemGuard = """
        你正在处理语音听写得到的文本。严格按照用户的要求处理它。\
        只输出处理后的文本本身：不要解释、不要评论、不要对话、不要使用引号或代码块包裹。\
        如果输入是空白或无法理解的噪声，原样输出。
        """

    /// 解析当前模式：raw / 内置 id（可被 overrides 覆盖 prompt）/ 自定义模式。
    /// 未知 id（比如模式被删了）回落 raw。
    public static func resolve(activeID: String?, custom: [RewriteMode],
                               overrides: [String: String] = [:]) -> Resolved {
        guard let activeID, activeID != rawID else { return .raw }
        if let b = builtins.first(where: { $0.id == activeID }) {
            return .llm(name: b.name, prompt: overrides[b.id] ?? b.prompt)
        }
        if let c = custom.first(where: { $0.id == activeID }) {
            return .llm(name: c.name, prompt: c.prompt)
        }
        return .raw
    }

    public enum Resolved: Equatable {
        case raw
        case llm(name: String, prompt: String)

        public var isRaw: Bool { self == .raw }
        /// 选单/设置页展示用。
        public func name(custom: [RewriteMode]) -> String {
            switch self {
            case .raw: return "原文直出"
            case .llm(let name, _): return name
            }
        }
    }
}
