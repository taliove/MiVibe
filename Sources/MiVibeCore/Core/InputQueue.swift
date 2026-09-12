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

    /// 转写成功。
    public mutating func transcriptionSucceeded(id: Int, text: String) {
        update(id) { phase in
            if case .transcribing = phase { phase = .ready(text) }
        }
    }

    /// 转写失败：保留录音待重试，并阻塞其后的自动输入。
    public mutating func transcriptionFailed(id: Int) {
        update(id) { phase in
            if case .transcribing = phase { phase = .needsAttention(.transcriptionFailed) }
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
