import Foundation
import MiVibeCore

/// 待处理内容留存的验收。
///
/// 这里守的是一个很容易悄悄失效的契约：**加一个新字段不该毁掉老配置**。
/// `Config.load()` 吞掉解码错误后返回默认值，而 `save()` 会把默认值写回去——
/// 一次解码失败就等于用户的 API Key 没了。所以每个新字段都必须是 Optional，
/// 而这条规矩只能靠测试钉住。
enum PendingStoreTests {
    static func run() {
        roundTrip()
        filePermissions()
        legacyConfigDecodes()
        unknownFutureFieldsIgnored()
        emptySaveClears()
        audioBudget()
        queuePersistableItems()
        queueRestoreDoesNotAutoInject()
    }

    // MARK: - 工具

    /// 每个用例一个独立临时目录，互不干扰。
    private static func withTempDir(_ body: (URL) throws -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mivibe-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try body(dir)
        } catch {
            Harness.expect(false, "临时目录用例抛出异常：\(error)")
        }
    }

    // MARK: - 用例

    static func roundTrip() {
        Harness.suite("待处理内容往返") {
            withTempDir { dir in
                let pcm = Data(repeating: 0x7F, count: 3200)
                let items = [
                    PendingItem(kind: .text, text: "第一句"),
                    PendingItem(kind: .failedAudio, pcm: pcm),
                ]
                do {
                    try PendingStore.save(items, in: dir)
                } catch {
                    Harness.expect(false, "保存应成功：\(error)")
                    return
                }
                let loaded = PendingStore.load(in: dir)
                Harness.expectEqual(loaded.count, 2, "读回两条")
                Harness.expectEqual(loaded.first?.text, "第一句", "文字保留")
                Harness.expectEqual(loaded.first?.kind, .text, "种类保留")
                Harness.expectEqual(loaded.last?.pcm, pcm, "音频字节完整")
            }
        }
    }

    static func filePermissions() {
        Harness.suite("留存文件权限为 0600") {
            withTempDir { dir in
                do {
                    try PendingStore.save([PendingItem(kind: .text, text: "私密")], in: dir)
                } catch {
                    Harness.expect(false, "保存应成功：\(error)")
                    return
                }
                let url = PendingStore.fileURL(in: dir)
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let mode = (attributes?[.posixPermissions] as? NSNumber)?.intValue
                Harness.expectEqual(mode, 0o600, "文件权限为 0600（同机其他用户读不到）")
            }
        }
    }

    static func legacyConfigDecodes() {
        Harness.suite("老配置能解码（新增字段不得毁掉它）") {
            // 这是会真正伤到用户的那种失败：老文件没有 keyMap/keyTakeover，
            // 若它们不是 Optional，整个解码失败 → load() 返回空配置 → API Key 丢。
            let legacy = #"{"doubaoAPIKey":"sk-abcdef","enableNonstream":true}"#
            guard let data = legacy.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(Config.Data.self, from: data)
            else {
                Harness.expect(false, "只有 2 个字段的老配置应该能解码")
                return
            }
            Harness.expectEqual(decoded.doubaoAPIKey, "sk-abcdef", "API Key 必须存活")
            Harness.expect(decoded.keyMap == nil, "缺失的映射表解码为 nil")
            Harness.expect(decoded.effectiveKeyTakeover, "接管默认开启")
            Harness.expect(
                decoded.effectiveKeyMap.mapping(forBundleID: nil).shortcuts.isEmpty,
                "缺失的映射表回落为空表"
            )
        }
    }

    static func unknownFutureFieldsIgnored() {
        Harness.suite("未来字段与嵌套缺失字段都不致命") {
            // 未来版本加的字段，本版本读到时必须忽略而不是报错。
            let withFuture = #"{"doubaoAPIKey":"k","enableNonstream":true,"someFutureField":42}"#
            let decoded = withFuture.data(using: .utf8)
                .flatMap { try? JSONDecoder().decode(Config.Data.self, from: $0) }
            Harness.expectEqual(decoded?.doubaoAPIKey, "k", "陌生字段被忽略，Key 仍在")

            // 嵌套层级同理：映射表里只写了部分键，其余字段缺失。
            let partialMap = #"{"doubaoAPIKey":"k","enableNonstream":true,"keyMap":{"perApp":{}}}"#
            let nested = partialMap.data(using: .utf8)
                .flatMap { try? JSONDecoder().decode(Config.Data.self, from: $0) }
            Harness.expect(nested?.keyMap != nil, "缺 defaultMapping 的映射表仍能解码")
        }
    }

    static func emptySaveClears() {
        Harness.suite("保存空列表即清除文件") {
            withTempDir { dir in
                try? PendingStore.save([PendingItem(kind: .text, text: "x")], in: dir)
                Harness.expect(
                    FileManager.default.fileExists(atPath: PendingStore.fileURL(in: dir).path),
                    "先写下文件"
                )
                try? PendingStore.save([], in: dir)
                Harness.expect(
                    !FileManager.default.fileExists(atPath: PendingStore.fileURL(in: dir).path),
                    "保存空列表后文件消失（不形成长期历史）"
                )
            }
        }
    }

    static func audioBudget() {
        Harness.suite("音频超预算时只留文字") {
            withTempDir { dir in
                // 造两段超过预算的音频。
                let big = Data(repeating: 0x01, count: PendingStore.audioBudgetBytes / 2 + 1024)
                let items = [
                    PendingItem(kind: .text, text: "保留我", pcm: big),
                    PendingItem(kind: .failedAudio, pcm: big),
                ]
                try? PendingStore.save(items, in: dir)
                let loaded = PendingStore.load(in: dir)
                Harness.expectEqual(loaded.count, 2, "条目数不变")
                Harness.expectEqual(loaded.first?.text, "保留我", "文字仍在")
                Harness.expect(loaded.allSatisfy { $0.pcm == nil }, "音频被丢弃")
            }
        }
    }

    // MARK: - 队列侧

    static func queuePersistableItems() {
        Harness.suite("队列：哪些内容值得留存") {
            var q = InputQueue()
            guard case .started(let id) = q.startRecording() else {
                Harness.expect(false, "应能开始录音")
                return
            }
            Harness.expect(q.persistableItems.isEmpty, "正在听、还没内容 → 不留存")

            q.finishRecording(id: id)
            Harness.expect(q.persistableItems.isEmpty, "正在转写、还没内容 → 不留存")

            q.transcriptionSucceeded(id: id, text: "有内容了")
            Harness.expectEqual(q.persistableItems.count, 1, "有文字 → 留存")
            Harness.expectEqual(q.persistableItems.first?.item.text, "有内容了", "文字正确")

            // 转写失败：只有录音没有文字，仍值得留存（可重试）。
            var q2 = InputQueue()
            guard case .started(let id2) = q2.startRecording() else { return }
            q2.finishRecording(id: id2)
            q2.transcriptionFailed(id: id2)
            Harness.expectEqual(q2.persistableItems.count, 1, "转写失败 → 留存（可重试）")
            Harness.expectEqual(
                q2.persistableItems.first?.item.kind, .failedAudio, "种类为 failedAudio"
            )
        }
    }

    static func queueRestoreDoesNotAutoInject() {
        Harness.suite("队列恢复后绝不自动输入") {
            var q = InputQueue()
            let ids = q.restore([
                PendingItem(kind: .text, text: "上次的话"),
                PendingItem(kind: .failedAudio),
            ])

            Harness.expectEqual(ids.count, 2, "恢复两条")
            Harness.expectEqual(q.items.count, 2, "队列里两条")
            Harness.expect(q.hasBlocker, "恢复的项都阻塞自动输入")

            // 这是本用例的核心：恢复后必须**不能**自动注入。
            Harness.expect(q.injectable == nil, "没有可自动注入的项")

            // 恢复的 id 不能和后续录音撞车。恢复两条已占满容量（上限 2），
            // 所以先处理掉一条腾出位置。
            q.resume(id: ids[0])
            q.injected(id: ids[0])
            guard case .started(let newID) = q.startRecording() else {
                Harness.expect(false, "腾出容量后仍可录音")
                return
            }
            Harness.expect(!ids.contains(newID), "新录音的 id 与恢复项不冲突")

            // 恢复的文字仍然可以正常恢复输入。
            q.discard(id: ids[1])
            Harness.expect(!q.hasBlocker, "恢复项被处理后可继续")
        }
    }
}
