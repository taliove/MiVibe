import Foundation
import MiVibeCore

// Coordinator 的辅助类型与只读查询：从 Coordinator.swift 拆出，保持主文件聚焦在链路编排上。
extension Coordinator {
    struct ModePickerState: Equatable, Sendable {
        struct Item: Equatable, Sendable, Identifiable {
            let id: String
            let name: String
        }
        var items: [Item]
        var highlight: Int
    }

    /// 全部可选模式：原文直出 + 内置 + 自定义。
    var modeItems: [ModePickerState.Item] {
        [ModePickerState.Item(id: RewriteModes.rawID, name: "原文直出")]
            + RewriteModes.builtins.map { ModePickerState.Item(id: $0.id, name: $0.name) }
            + rewrite.effectiveCustomModes.map { ModePickerState.Item(id: $0.id, name: $0.name) }
    }

    /// 菜单栏弹层的「点一下切到下一个模式」。
    func cycleMode() {
        let items = modeItems
        guard let idx = items.firstIndex(where: { $0.id == rewrite.effectiveActiveMode }) else {
            selectMode(RewriteModes.rawID)
            return
        }
        selectMode(items[(idx + 1) % items.count].id)
    }

    /// 内置模式当前生效的 prompt（覆盖优先）。
    func effectiveBuiltinPrompt(_ id: String) -> String {
        rewrite.effectiveBuiltinPrompts[id]
            ?? RewriteModes.builtins.first { $0.id == id }?.prompt
            ?? ""
    }

    /// 一次预设套用的撤销信息。会话内有效，不落盘。
    struct PresetUndo {
        let presetName: String
        let scope: String?
        /// 套用前该作用范围的原始表；nil 表示当时该应用还没有覆盖表（撤销 = 移除整个配置）。
        let previous: AppMapping?
    }

    /// 转写整体超时。本地引擎是阻塞 C 调用、取消不掉，超时后它的结果会晚到，
    /// 那时该项已是「转写失败」，`transcriptionSucceeded` 对它是 no-op。
    nonisolated static func transcribe(pcm: Data, with provider: any ASRProvider,
                                               timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await provider.transcribe(pcm: pcm) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TranscribeTimeout(seconds: timeout)
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    struct TranscribeTimeout: LocalizedError {
        let seconds: TimeInterval
        var errorDescription: String? { "转写超时（\(Int(seconds)) 秒），可在菜单里重试" }
    }
}

/// 极简 UserDefaults 支撑的属性包装（避免为一个开关引入 SwiftUI 依赖）。
@propertyWrapper
struct AppStorageBacked<Value> {
    private let key: String
    private let defaultValue: Value

    init(_ key: String, default defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var wrappedValue: Value {
        get { UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
