import Foundation

/// LLM 改写客户端：OpenAI 兼容（/v1/chat/completions）与 Anthropic（/v1/messages）
/// 双协议，非流式一次性返回。5 秒超时——改写是注入前的可选步骤，用户的话不能等。
public enum LLMClient {
    public enum LLMError: Error, LocalizedError {
        case badBaseURL(String)
        case http(Int, String)
        case emptyContent

        public var errorDescription: String? {
            switch self {
            case .badBaseURL(let s): return "LLM 接口地址无效：\(s)"
            case .http(let code, let body): return "LLM 请求失败（HTTP \(code)）：\(body.prefix(200))"
            case .emptyContent: return "LLM 返回了空内容"
            }
        }
    }

    /// 总超时（秒）：超时按失败处理，上层静默回落原文。
    public static let timeout: TimeInterval = 5

    public static func complete(system: String, user: String, config: LLMProviderConfig) async throws -> String {
        switch config.effectiveProto {
        case .openai: return try await openAI(system: system, user: user, config: config)
        case .anthropic: return try await anthropic(system: system, user: user, config: config)
        }
    }

    // MARK: - OpenAI 兼容

    private static func openAI(system: String, user: String, config: LLMProviderConfig) async throws -> String {
        let url = try endpoint(config, path: "/chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey ?? "")", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.model ?? "",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0.3,
        ])
        let json = try await send(req)
        guard let content = json["choices"] as? [[String: Any]],
              let message = content.first?["message"] as? [String: Any],
              let text = message["content"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw LLMError.emptyContent }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic

    private static func anthropic(system: String, user: String, config: LLMProviderConfig) async throws -> String {
        let url = try endpoint(config, path: "/v1/messages")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey ?? "", forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.model ?? "",
            "max_tokens": 2048,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ])
        let json = try await send(req)
        guard let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw LLMError.emptyContent }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 内部

    /// baseURL 约定：OpenAI 系模板已含 /v1（如 https://api.openai.com/v1、
    /// http://localhost:11434/v1），自定义时用户给什么就用什么，不擅自补路径。
    private static func endpoint(_ config: LLMProviderConfig, path: String) throws -> URL {
        let base = (config.baseURL ?? "").trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let url = URL(string: base + path) else { throw LLMError.badBaseURL(config.baseURL ?? "") }
        return url
    }

    private static func send(_ req: URLRequest) async throws -> [String: Any] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let (data, response) = try await URLSession(configuration: configuration).data(for: req)
        guard let http = response as? HTTPURLResponse else { throw LLMError.http(-1, "") }
        let body = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(http.statusCode) else { throw LLMError.http(http.statusCode, body) }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
