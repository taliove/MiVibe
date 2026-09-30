import Foundation
import MiVibeCore

/// 外观页相关持久化的验收（spec D，epic #1 子任务 #5）。
///
/// 守的契约：
/// - `appearancePaneSeen` 是 Optional：老配置（没有这个键）解码后必须是 nil，
///   「新」胶囊才会显示；不能因新增字段毁掉整份配置（见 Config.swift 头注释）。
/// - 看过外观页写入 true 后，编码—解码往返保留。
enum AppearancePaneConfigTests {
    static func run() {
        legacyConfigDecodesAsUnseen()
        roundTrip()
    }

    /// 老配置文件：没有 appearancePaneSeen 键，其余字段（API Key 等）必须原样存活。
    static func legacyConfigDecodesAsUnseen() {
        Harness.suite("外观页标记：老配置解码为未看过") {
            let legacy = #"{"doubaoAPIKey":"sk-abcdef","enableNonstream":true,"theme":"rose"}"#
            guard let data = legacy.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(Config.Data.self, from: data)
            else {
                Harness.expect(false, "没有 appearancePaneSeen 的老配置应该能解码")
                return
            }
            Harness.expectEqual(decoded.doubaoAPIKey, "sk-abcdef", "API Key 必须存活")
            Harness.expect(decoded.appearancePaneSeen == nil, "缺失的 appearancePaneSeen 解码为 nil")
            Harness.expectEqual(decoded.effectiveTheme, .rose, "既有主题字段不受影响")
        }
    }

    static func roundTrip() {
        Harness.suite("外观页标记：看过状态往返保存") {
            var cfg = Config.Data()
            cfg.appearancePaneSeen = true
            cfg.doubaoAPIKey = "sk-roundtrip"
            guard let encoded = try? JSONEncoder().encode(cfg),
                  let decoded = try? JSONDecoder().decode(Config.Data.self, from: encoded)
            else {
                Harness.expect(false, "编码后应能解码回来")
                return
            }
            Harness.expectEqual(decoded.appearancePaneSeen, true, "看过标记往返保留")
            Harness.expectEqual(decoded.doubaoAPIKey, "sk-roundtrip", "其他字段往返保留")
        }
    }
}
