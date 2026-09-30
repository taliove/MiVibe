import Foundation

/// 浮条状态（SPEC §6 四状态，后增改写中与提示）。文案与颜色在界面层（AppState.swift）。
public enum FloatState: String, CaseIterable, Identifiable, Sendable {
    case listening, transcribing, polishing, inserted, notice, attention

    public var id: String { rawValue }

    /// 自动收起的延迟（秒）；进行中状态不自动收起，返回 nil。
    public var hideDelay: Double? {
        switch self {
        case .inserted: return MotionTiming.insertedHideDelay
        case .notice: return MotionTiming.noticeHideDelay
        case .attention: return MotionTiming.attentionHideDelay
        case .listening, .transcribing, .polishing: return nil
        }
    }
}

/// 浮条列表里的一条：要么跟随一条录音，要么是不属于任何录音的提示条。
public struct FloatEntry: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        /// 跟随队列里的一条录音（关联值是队列项 id）。
        case recording(Int)
        /// 模式切换、空录音忽略、接管失败等提示。
        case notice
    }

    public let kind: Kind
    public let state: FloatState
    /// 具体指引文案；空串表示用状态默认指引。
    public let message: String

    public init(kind: Kind, state: FloatState, message: String) {
        self.kind = kind
        self.state = state
        self.message = message
    }

    /// 视图身份：同一条录音从听音走到已输入始终是同一条，提示条只有一个位置。
    public var id: String {
        switch kind {
        case .recording(let queueID): return "recording-\(queueID)"
        case .notice: return "notice"
        }
    }
}

/// 多条浮条的纯模型（SPEC §13）：一条录音一条浮条，最多两条，另加至多一条提示条。
///
/// 录音条的状态由队列推导（`sync`，协调器在每次队列变化后调用），队列表达不了的
/// 瞬时显示状态由协调器补充：改写中、已输入（出队后还要停留 1.6 s）、具体文案。时间由调用方传入（秒，单调时钟），
/// 不读时钟、无副作用，测试直接驱动。
///
/// 列表顺序：提示条在最上，录音条按录制先后（新句在下）。提示条放在最上，是为了
/// 它出现 / 收起时不推动下方锚定在底部的录音条。
public struct FloatStack: Equatable, Sendable {
    /// 录音条上限，与录音队列容量一致。
    public static let maxRecordingBars = InputQueue.capacity

    private struct Track: Equatable, Sendable {
        var state: FloatState
        var message: String
        /// 文案是否由协调器显式给出（否则每次推导按阶段刷新默认文案）。
        var custom: Bool
        /// 进入当前状态的时刻，自动收起从这里计时。
        var since: Double
    }

    private struct Notice: Equatable, Sendable {
        var state: FloatState
        var message: String
        var since: Double
    }

    private var tracks: [Int: Track] = [:]
    private var polishing: Set<Int> = []
    private var notice: Notice?

    /// 第三条录音被拒绝的次数：每 +1，界面让已有浮条晃一次。
    public private(set) var shakeCount = 0

    public init() {}

    // MARK: - 事件

    /// 给某条录音的当前状态指定文案（须在推出该状态的 `sync` 之后调用）。
    /// 文案保留到这条浮条换状态为止；换状态后回到该阶段的默认文案。
    public mutating func setMessage(_ message: String, for id: Int) {
        guard tracks[id] != nil else { return }
        tracks[id]?.message = message
        tracks[id]?.custom = true
    }

    /// 标记某条录音正在改写 / 改写结束（下一次 `sync` 生效）。
    public mutating func setPolishing(_ on: Bool, for id: Int) {
        if on { polishing.insert(id) } else { polishing.remove(id) }
    }

    /// 某条录音已写入并出队：浮条转为已输入，停留 `insertedHideDelay` 后单独收起。
    /// 须在 `InputQueue.injected` 之后调用（否则下一次 `sync` 会按队列阶段覆盖）。
    public mutating func markInserted(id: Int, now: Double) {
        polishing.remove(id)
        tracks[id] = Track(state: .inserted, message: "", custom: false, since: now)
    }

    /// 发一条不属于任何录音的提示，替换现有提示条。
    public mutating func postNotice(_ message: String, attention: Bool = false, now: Double) {
        notice = Notice(state: attention ? .attention : .notice, message: message, since: now)
    }

    /// 第三条录音因队列已满被拒绝：不新增浮条，让已有浮条晃一次。
    /// 已超时收起的需处理条重新露出来——用户得看见是什么占住了队列。
    public mutating func rejectQueueFull(now: Double) {
        shakeCount += 1
        for (id, track) in tracks where track.state == .attention && Self.isExpired(track.state, since: track.since, now: now) {
            tracks[id]?.since = now
        }
    }

    /// 按队列当前状态推导录音条。队列里消失的项：已输入的保留到收起，其他（取消、
    /// 丢弃、空录音出队）立即移除。
    public mutating func sync(queue: [InputQueue.Item], now: Double) {
        var next: [Int: Track] = [:]
        for (index, item) in queue.enumerated() {
            let state = Self.state(for: item.phase, polishing: polishing.contains(item.id))
            let fallback = Self.defaultMessage(for: item.phase, waiting: index > 0)
            if var track = tracks[item.id], track.state == state {
                if !track.custom { track.message = fallback }
                next[item.id] = track
            } else {
                next[item.id] = Track(state: state, message: fallback, custom: false, since: now)
            }
        }
        let ids = Set(queue.map(\.id))
        for (id, track) in tracks where !ids.contains(id) && track.state == .inserted
            && !Self.isExpired(track.state, since: track.since, now: now) {
            next[id] = track
        }
        tracks = next
        polishing.formIntersection(ids)
        if let current = notice, Self.isExpired(current.state, since: current.since, now: now) {
            notice = nil
        }
    }

    // MARK: - 查询

    /// 此刻应显示的浮条：提示条（若有）在前，录音条按录制先后，至多两条。
    public func entries(now: Double) -> [FloatEntry] {
        var recordings = tracks
            .filter { !Self.isExpired($0.value.state, since: $0.value.since, now: now) }
            .sorted { $0.key < $1.key }
            .map { FloatEntry(kind: .recording($0.key), state: $0.value.state, message: $0.value.message) }
        // 超过上限（上一句已输入还没收起，又来了新录音）：先让出最早的已输入条。
        while recordings.count > Self.maxRecordingBars {
            if let index = recordings.firstIndex(where: { $0.state == .inserted }) {
                recordings.remove(at: index)
            } else {
                recordings.removeFirst()
            }
        }
        var result: [FloatEntry] = []
        if let notice, !Self.isExpired(notice.state, since: notice.since, now: now) {
            result.append(FloatEntry(kind: .notice, state: notice.state, message: notice.message))
        }
        return result + recordings
    }

    /// 下一个会让列表变化的时刻（某条到点收起）。协调器据此排一次刷新。
    public func nextDeadline(after now: Double) -> Double? {
        var deadlines = tracks.values.compactMap { track in
            track.state.hideDelay.map { track.since + $0 }
        }
        if let notice, let delay = notice.state.hideDelay {
            deadlines.append(notice.since + delay)
        }
        return deadlines.filter { $0 > now }.min()
    }

    // MARK: - 规则

    private static func isExpired(_ state: FloatState, since: Double, now: Double) -> Bool {
        guard let delay = state.hideDelay else { return false }
        return now >= since + delay
    }

    /// 队列阶段 → 浮条状态。已有文字等待输入的项仍算进行中（转写圈），改写时为改写中。
    static func state(for phase: InputQueue.Phase, polishing: Bool) -> FloatState {
        switch phase {
        case .listening: return .listening
        case .transcribing: return .transcribing
        case .ready: return polishing ? .polishing : .transcribing
        case .needsAttention: return .attention
        }
    }

    /// 队列阶段的默认文案；空串让界面用状态默认指引。
    static func defaultMessage(for phase: InputQueue.Phase, waiting: Bool) -> String {
        switch phase {
        case .listening, .transcribing: return ""
        case .ready: return waiting ? "转写完成，等前一句处理完再输入" : ""
        case .needsAttention(.transcriptionFailed): return "转写失败，可在菜单里重试"
        case .needsAttention(.targetLost): return "焦点已改变，请选好输入框后点「输入到这里」"
        case .needsAttention(.injectionFailed): return "输入失败，文字已保留，请在菜单里处理"
        }
    }
}
