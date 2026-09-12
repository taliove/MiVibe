import AppKit
import Foundation
import MiVibeCore

/// 把遥控器、识别、注入、队列串成一条链路（SPEC §6）。
///
/// 时序：按住语音键 → 抓焦点快照 → 设备自发 AUDIO_START → 收音频 → AUDIO_STOP 收口
/// → 转写 → **重新比对焦点** → 一致才注入，不一致就暂存等「输入到这里」。
@MainActor
final class Coordinator: ObservableObject {
    @Published private(set) var link: LinkState = .unpaired
    @Published private(set) var float: FloatState?
    @Published private(set) var queue = InputQueue()
    @Published var lastMessage: String = ""

    /// 二遍识别开关（SPEC §4 默认开）。
    @AppStorageBacked("mivibe.enableNonstream", default: true)
    var enableNonstream: Bool

    private let remote = RemoteManager()
    private let keys = KeyReader()
    private let asr = DoubaoClient()

    /// 每条录音按下时的焦点快照，注入前用于比对。
    private var snapshots: [Int: TextInjector.Snapshot] = [:]
    private var activeID: Int?

    init() {
        wireRemote()
        wireKeys()
    }

    func start() {
        remote.connect()
        keys.start()
    }

    // MARK: - 遥控器事件

    private func wireRemote() {
        remote.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .bluetoothUnavailable: link = .unpaired
            case .searching, .connecting: link = .pairedOffline
            case .negotiating, .ready, .recording: link = .connected
            }
        }

        // 设备自发开始录音：用户按住了语音键。
        remote.onRecordingStart = { [weak self] in
            guard let self else { return }
            switch queue.startRecording() {
            case .started(let id):
                activeID = id
                snapshots[id] = TextInjector.snapshotFocus()
                float = .listening
            case .rejectedQueueFull:
                float = .attention
                lastMessage = "已有两条未处理，请先处理"
            }
        }

        remote.onRecordingFinish = { [weak self] recording in
            guard let self, let id = activeID else { return }
            activeID = nil
            queue.finishRecording(id: id)
            float = .transcribing
            transcribe(id: id, pcm: recording.pcm)
        }
    }

    private func wireKeys() {
        keys.onKey = { [weak self] key, isDown in
            guard let self, isDown else { return }
            // 返回键取消最新活动项（SPEC §6）。语音键本身不在此处开录音——
            // 音频受物理门控，一律由设备自发的 AUDIO_START 驱动。
            if key == .back {
                if let cancelled = queue.cancelNewestActive() {
                    snapshots[cancelled] = nil
                    if activeID == cancelled { activeID = nil }
                    float = nil
                    lastMessage = "已取消"
                }
            }
        }
    }

    // MARK: - 转写与注入

    private func transcribe(id: Int, pcm: Data) {
        var options = DoubaoClient.Options()
        options.enableNonstream = enableNonstream

        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await asr.transcribe(pcm: pcm, options: options)
                await MainActor.run {
                    self.queue.transcriptionSucceeded(id: id, text: text)
                    self.drain()
                }
            } catch {
                await MainActor.run {
                    self.queue.transcriptionFailed(id: id)
                    self.float = .attention
                    self.lastMessage = error.localizedDescription
                }
            }
        }
    }

    /// 按序输入队首可注入项。前面有阻塞就停手。
    private func drain() {
        guard !queue.hasBlocker, let next = queue.injectable else { return }

        guard let saved = snapshots[next.id] else {
            queue.targetLost(id: next.id)
            float = .attention
            lastMessage = "目标已失效，请选好输入框后点「输入到这里」"
            return
        }

        // 注入前重新比对焦点：变了就暂存，绝不强写。
        guard let current = TextInjector.snapshotFocus(), current == saved else {
            queue.targetLost(id: next.id)
            float = .attention
            lastMessage = "焦点已改变，请选好输入框后点「输入到这里」"
            return
        }

        do {
            _ = try TextInjector.inject(next.text, into: current)
            queue.injected(id: next.id)
            snapshots[next.id] = nil
            float = .inserted
            lastMessage = next.text
            drain()   // 继续下一条
        } catch {
            queue.injectionFailed(id: next.id, text: next.text)
            float = .attention
            lastMessage = error.localizedDescription
        }
    }

    // MARK: - 用户动作

    /// 「输入到这里」：把待处理文字写入当前焦点。
    func resumeHere(id: Int) {
        guard let snapshot = TextInjector.snapshotFocus() else {
            lastMessage = "找不到输入焦点"
            return
        }
        snapshots[id] = snapshot
        queue.resume(id: id)
        drain()
    }

    func retry(id: Int) {
        queue.retry(id: id)
        lastMessage = "重试功能需保留录音，第一版由下次按键重录代替"
    }

    func discard(id: Int) {
        queue.discard(id: id)
        snapshots[id] = nil
        if queue.items.isEmpty { float = nil }
    }

    func discardAll() {
        queue.discardAll()
        snapshots.removeAll()
        float = nil
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
