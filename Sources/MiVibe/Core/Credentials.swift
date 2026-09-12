import Foundation

/// 豆包 API Key 的存取。
///
/// 只存 macOS 钥匙串，服务名沿用诊断阶段已在用的 `mivibe-volc-apikey`，
/// 所以此前手工存进去的 Key 可以直接用。Key 绝不落盘到仓库或日志。
enum Credentials {
    static let service = "mivibe-volc-apikey"

    enum CredentialError: Error, LocalizedError {
        case notFound
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .notFound: return "尚未配置 API Key"
            case .keychain(let status): return "钥匙串操作失败（\(status)）"
            }
        }
    }

    /// 环境变量优先，方便临时覆盖；否则读钥匙串。
    static func apiKey() throws -> String {
        if let fromEnv = ProcessInfo.processInfo.environment["VOLC_API_KEY"],
           !fromEnv.isEmpty {
            return fromEnv
        }

        // 未打包/未稳定签名时（开发期直接跑 SwiftPM 产物），SecItemCopyMatching 会
        // 因为钥匙串 ACL 找不到可信身份而**无声挂起**——不是报错，是永远不返回。
        // 打包成 .app 并用固定身份签名后才走得通。开发期回退到 Apple 签名的
        // `security` CLI，行为一致且不会挂。
        if Bundle.main.bundleIdentifier == nil {
            return try apiKeyViaSecurityCLI()
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let key = String(data: data, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty
            else { throw CredentialError.notFound }
            return key
        case errSecItemNotFound:
            throw CredentialError.notFound
        default:
            throw CredentialError.keychain(status)
        }
    }

    private static func apiKeyViaSecurityCLI() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { throw CredentialError.notFound }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let key = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { throw CredentialError.notFound }
        return key
    }

    static var isConfigured: Bool {
        (try? apiKey()) != nil
    }

    /// 写入/更新钥匙串。
    static func save(apiKey: String) throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(key.utf8)

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]

        // 先试更新，不存在再新增。
        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialError.keychain(updateStatus)
        }

        var insert = base
        insert[kSecValueData as String] = data
        insert[kSecAttrAccount as String] = NSUserName()
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialError.keychain(addStatus)
        }
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychain(status)
        }
    }
}
