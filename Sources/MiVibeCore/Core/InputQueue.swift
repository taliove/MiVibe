import Foundation

/// 录音/转写/输入的队列状态机（SPEC §6，交互原型已验收）。
///
/// 规则：容量 2；后句可录但必须按序输入；前句失败会阻塞后句自动输入；
/// 返回键只取消**最新活动项**，绝不隐式删除较早的待处理内容。
///
/// 纯逻辑、无副作用：不碰蓝牙、不碰网络、不碰注入，全部由外部驱动事件。
public struct InputQueue: Equatable {
    public static let capacity = 2

    /// 单条录音在队列中的阶段。
    public enum Phase: Equatable {
        case listening              // 正在按住说话
        case transcribing           // 已松手，等转写结果
        case ready(String)          // 有文字，等待按序输入
        case needsAttention(Reason) // 需用户处理，阻塞其后的自动输入

        public enum Reason: Equatable {
            case transcriptionFailed        // 转写失败，可重试（录音保留）
            case targetLost(text: String)   // 失焦/目标失效，文字暂存待「输入到这里」
            case injectionFailed(text: String) // 注入失败，文字保留
        }
    }

    public struct Item: Equatable, Identifiable {
        public let id: Int
        public var phase: Phase
    }

    public private(set) var items: [Item] = []
    private var nextID = 1

    public init() {}

    // MARK: - 查询

    public var isFull: Bool { items.count >= Self.capacity }

    /// 最新的活动项（正在听或正在转写）——返回键的作用对象。
    public var newestActiveID: Int? {
        items.last { if case .listening = $0.phase { return true }
                     if case .transcribing = $0.phase { return true }
                     return false }?.id
    }

    /// 是否存在需处理项：存在则暂停自动输入。
    public var hasBlocker: Bool {
        items.contains { if case .needsAttention = $0.phase { return true }; return false }
    }

    /// 队首若已有文字且前面无阻塞，即可输入。
    public var injectable: (id: Int, text: String)? {
        guard let first = items.first else { return nil }
        if case .ready(let text) = first.phase { return (first.id, text) }
        return nil
    }

    /// 待处理内容（退出时需用户显式取舍的部分）。
    public var pendingTexts: [String] {
        items.compactMap { item in
            switch item.phase {
            case .ready(let text): return text
            case .needsAttention(.targetLost(let text)): return text
            case .needsAttention(.injectionFailed(let text)): return text
            case .needsAttention(.transcriptionFailed): return nil  // 只有录音，无文字
            case .listening, .transcribing: return nil
            }
        }
    }

    // MARK: - 持久化（退出保留 / 崩溃兜底）

    /// 队列里**有内容、值得留存**的项，按队序。
    ///
    /// `.listening` / `.transcribing` 不算：它们还没有完整内容可留。文本为空的
    /// `targetLost` 也不算——那是一次没有产出的录音。
    public var persistableItems: [(id: Int, item: PendingItem)] {
        items.compactMap { entry in
            switch entry.phase {
            case .ready(let text) where !text.isEmpty,
                 .needsAttention(.targetLost(let text)) where !text.isEmpty,
                 .needsAttention(.injectionFailed(let text)) where !text.isEmpty:
                return (entry.id, PendingItem(kind: .text, text: text))
            case .needsAttention(.transcriptionFailed):
                return (entry.id, PendingItem(kind: .failedAudio))
            default:
                return nil
            }
        }
    }

    /// 启动恢复：把留存的内容放回队列。
    ///
    /// **全部落到 `.needsAttention`，因此 `hasBlocker` 为真、`drain()` 不会跑。**
    /// 「恢复后不自动输入」是结构上的保证，不是一句约定——用户必须自己选好输入框
    /// 再点「输入到这里」，走的是和失焦暂存完全相同的那条路（SPEC §6）。
    @discardableResult
    public mutating func restore(_ saved: [PendingItem]) -> [Int] {
        var restored: [Int] = []
        for item in saved {
            let id = nextID
            nextID += 1
            let phase: Phase
            switch item.kind {
            case .text:
                phase = .needsAttention(.targetLost(text: item.text ?? ""))
            case .failedAudio:
                phase = .needsAttention(.transcriptionFailed)
            }
            items.append(Item(id: id, phase: phase))
            restored.append(id)
        }
        return restored
    }

    // MARK: - 事件

    public enum StartResult: Equatable {
        case started(id: Int)
        case rejectedQueueFull
    }

    /// 按下语音键。队列满时拒绝——不静默丢弃，由 UI 告知用户先处理。
    @discardableResult
    public mutating func startRecording() -> StartResult {
        guard !isFull else { return .rejectedQueueFull }
        let item = Item(id: nextID, phase: .listening)
        nextID += 1
        items.append(item)
        return .started(id: item.id)
    }

    /// 松开语音键：进入转写。
    public mutating func finishRecording(id: Int) {
        update(id) { phase in
            if case .listening = phase { phase = .transcribing }
        }
    }

    /// 转写成功。转写途中已失焦的项（空文字的 `targetLost` 占位）把文字补进去，
    /// 仍保持暂存、等用户显式恢复。
    public mutating func transcriptionSucceeded(id: Int, text: String) {
        update(id) { phase in
            switch phase {
            case .transcribing: phase = .ready(text)
            case .needsAttention(.targetLost(let old)) where old.isEmpty:
                phase = .needsAttention(.targetLost(text: text))
            default: break
            }
        }
    }

    /// 没有产出的录音（误触、按住没说话、转写为空）：直接出队。
    ///
    /// 不能落成 `.ready("")` 或空的 `targetLost`——那是一条没有可恢复内容的阻塞项，
    /// 会占住容量、挡住后面的句子（真机日志里的卡死就是这么来的）。
    /// 已有文字的项不受影响。
    public mutating func transcriptionEmpty(id: Int) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        switch item.phase {
        case .listening, .transcribing, .needsAttention(.targetLost(text: "")):
            items.removeAll { $0.id == id }
        default:
            break
        }
    }

    /// 转写失败：保留录音待重试，并阻塞其后的自动输入。
    public mutating func transcriptionFailed(id: Int) {
        update(id) { phase in
            switch phase {
            case .transcribing, .needsAttention(.targetLost(text: "")):
                phase = .needsAttention(.transcriptionFailed)
            default: break
            }
        }
    }

    /// 重试失败的转写。
    public mutating func retry(id: Int) {
        update(id) { phase in
            if case .needsAttention(.transcriptionFailed) = phase { phase = .transcribing }
        }
    }

    /// 目标失效（录音期间切了应用/输入框）：文字暂存，等用户显式恢复。
    public mutating func targetLost(id: Int) {
        update(id) { phase in
            switch phase {
            case .ready(let text): phase = .needsAttention(.targetLost(text: text))
            case .transcribing: phase = .needsAttention(.targetLost(text: ""))
            default: break
            }
        }
    }

    /// 注入成功：该项出队。
    public mutating func injected(id: Int) {
        items.removeAll { $0.id == id }
    }

    /// 注入失败：文字保留待处理。
    public mutating func injectionFailed(id: Int, text: String) {
        update(id) { $0 = .needsAttention(.injectionFailed(text: text)) }
    }

    /// 「输入到这里」：用户选好目标后恢复某条待处理文字。
    /// 恢复后回到 ready，仍受按序输入约束。
    public mutating func resume(id: Int) {
        update(id) { phase in
            switch phase {
            case .needsAttention(.targetLost(let text)) where !text.isEmpty:
                phase = .ready(text)
            case .needsAttention(.injectionFailed(let text)):
                phase = .ready(text)
            default: break
            }
        }
    }

    /// 返回键：取消最新活动项。没有活动项时什么都不做——
    /// **绝不**顺手删掉较早的待处理内容。
    @discardableResult
    public mutating func cancelNewestActive() -> Int? {
        guard let id = newestActiveID else { return nil }
        items.removeAll { $0.id == id }
        return id
    }

    /// 用户显式丢弃某条待处理内容。
    public mutating func discard(id: Int) {
        items.removeAll { $0.id == id }
    }

    /// 退出时丢弃全部（用户显式选择的分支之一）。
    public mutating func discardAll() {
        items.removeAll()
    }

    // MARK: - 私有

    private mutating func update(_ id: Int, _ transform: (inout Phase) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        transform(&items[index].phase)
    }
}
