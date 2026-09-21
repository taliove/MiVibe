import Foundation

/// 改写模式的持久化配置（config.json 的 `rewrite` 字段）。全部 Optional——
/// 新增字段破坏旧配置解码的代价是抹掉整个配置文件（见 Config 类型头注释）。
public struct RewriteConfig: Codable, Sendable, Equatable {
    /// 当前模式：内置模式的 id 或自定义模式的 uuid。nil = 原文直出。
    public var activeMode: String?
    public var customModes: [RewriteMode]?
    public var provider: LLMProviderConfig?
    /// 内置模式 prompt 的用户覆盖：键是内置模式 id，值是改过的 prompt。
    /// 解析顺序 覆盖 > 内置默认；删掉覆盖即恢复默认。
    public var builtinPrompts: [String: String]?

    public init(activeMode: String? = nil, customModes: [RewriteMode]? = nil,
                provider: LLMProviderConfig? = nil, builtinPrompts: [String: String]? = nil) {
        self.activeMode = activeMode
        self.customModes = customModes
        self.provider = provider
        self.builtinPrompts = builtinPrompts
    }

    public var effectiveActiveMode: String { activeMode ?? RewriteModes.rawID }
    public var effectiveCustomModes: [RewriteMode] { customModes ?? [] }
    public var effectiveBuiltinPrompts: [String: String] { builtinPrompts ?? [:] }
}

/// 用户自定义的改写模式（内置模式不进配置，见 RewriteModes）。
public struct RewriteMode: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var prompt: String

    public init(id: String = UUID().uuidString, name: String, prompt: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }
}

/// LLM 服务商配置：协议 + baseURL + Key + 模型名。
public struct LLMProviderConfig: Codable, Sendable, Equatable {
    /// "openai" | "anthropic"
    public var proto: String?
    public var baseURL: String?
    public var apiKey: String?
    public var model: String?

    public init(proto: String? = nil, baseURL: String? = nil, apiKey: String? = nil, model: String? = nil) {
        self.proto = proto
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    public enum Proto: String, Sendable {
        case openai, anthropic
    }

    public var effectiveProto: Proto { Proto(rawValue: proto ?? "") ?? .openai }

    /// 配置完整才可发起改写；不完整时按「原文直出」处理（设置页负责提示）。
    public var isComplete: Bool {
        guard let baseURL, let apiKey, let model else { return false }
        return !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }
}
