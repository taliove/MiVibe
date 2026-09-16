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

    /// 每应用按键映射表（含默认兜底）。设置页直接改它，改动即持久化。
    /// 启动时 `pruned()`：老配置里可能有已删除的按键名。
    @Published private(set) var keyMap: KeyMapTable

    /// 是否独占接管遥控器按键。关掉时 `KeyReader` 退回仅监听，
    /// 映射与转发全部停用，只剩返回键取消（原生按键由系统自己处理）。
    @Published private(set) var keyTakeover: Bool

    /// 接管是否真的拿到了设备。用户开着开关但独占失败（权限不足/设备被持有）
    /// 时两者不一致——设置页据此显示"未生效"并提供重试入口。
    @Published private(set) var keyTakeoverActive = false

    /// 实时音量电平外推口（0…1）。浮条监听它驱动那颗球的胀缩。
    /// 音频只在按住期间流出，所以这个回调也只在听音态触发。
    var onAudioLevel: ((Double) -> Void)?

    private let remote = RemoteManager()
    private let keys = KeyReader()
    private let asr = DoubaoClient()
    private var meter = AudioLevelMeter()

    /// 每条录音按下时的焦点快照，注入前用于比对。
    private var snapshots: [Int: TextInjector.Snapshot] = [:]
    private var activeID: Int?

    /// 队列里还有没处理完的内容——菜单栏图标据此显示角标。
    ///
    /// 浮条会在超时后收起，"需处理"的内容却永不丢失；没有这个角标，一条转写文字
    /// 可以静静等你一辈子而屏幕上没有任何提示。
    var hasPendingWork: Bool { !queue.items.isEmpty }

    init() {
        let config = Config.load()
        keyMap = config.effectiveKeyMap.pruned()
        keyTakeover = config.effectiveKeyTakeover
        wireRemote()
        wireKeys()
    }

    func start() {
        remote.connect()
        keys.start(takeover: keyTakeover)
        keyTakeoverActive = keys.isExclusive
        Log.chain.notice("start: takeover=\(self.keyTakeover) exclusive=\(self.keys.isExclusive)")
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
            meter.reset()
            onAudioLevel?(0)
            switch queue.startRecording() {
            case .started(let id):
                activeID = id
                let snapshot = TextInjector.snapshotFocus()
                snapshots[id] = snapshot
                let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
                Log.chain.notice("AUDIO_START id=\(id) snapshot=\(snapshot == nil ? "nil" : "ok", privacy: .public) front=\(frontApp, privacy: .public)")
                float = .listening
            case .rejectedQueueFull:
                Log.chain.notice("AUDIO_START rejected: queue full")
                float = .attention
                lastMessage = "已有两条未处理，请先处理"
            }
        }

        remote.onRecordingFinish = { [weak self] recording in
            guard let self, let id = activeID else { return }
            activeID = nil
            queue.finishRecording(id: id)
            Log.chain.notice("AUDIO_STOP id=\(id) pcm=\(recording.pcm.count)B")
            float = .transcribing
            transcribe(id: id, pcm: recording.pcm)
        }

        // 逐帧音量：BLE 每约 15ms 给一块 480B PCM，折算成电平推给浮条。
        // 只在听音态转发——队列满被拒时浮条显示的是"需处理"，此时不该再驱动球。
        remote.onAudioChunk = { [weak self] pcm in
            guard let self, float == .listening else { return }
            onAudioLevel?(meter.push(pcm: pcm))
        }
    }

    private func wireKeys() {
        keys.onTakeoverFailed = { [weak self] reason in
            guard let self else { return }
            keyTakeoverActive = false
            float = .attention
            lastMessage = "按键接管失败（\(reason)），已退回仅监听"
        }

        keys.onKey = { [weak self] key, isDown, isRepeat in
            guard let self else { return }
            if keys.isExclusive {
                route(key, isDown: isDown, isRepeat: isRepeat)
            } else {
                // 仅监听：原生按键由系统自己处理，这里只做返回键取消（SPEC §6）。
                // 语音键本身不在此处开录音——音频受物理门控，一律由设备自发的
                // AUDIO_START 驱动。
                guard isDown, !isRepeat, key == .back else { return }
                cancelNewestActive()
            }
        }
    }

    /// 独占模式下的按键路由：裁决在 `KeyRouter`（纯逻辑），执行在这里。
    private func route(_ key: RemoteButton, isDown: Bool, isRepeat: Bool) {
        // 前台应用决定用哪张映射表。MiVibe 自身是 accessory 应用，不抢前台，
        // 所以这里拿到的就是用户正在输入的那个应用。
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let mapping = keyMap.mapping(forBundleID: bundleID)
        switch KeyRouter.disposition(
            for: key, isDown: isDown, isRepeat: isRepeat,
            mapping: mapping, hasActiveItem: queue.newestActiveID != nil
        ) {
        case .cancelNewestActive:
            cancelNewestActive()
        case .synthesize(let shortcut):
            KeySynth.post(shortcut)
        case .passthrough:
            KeySynth.passthrough(key, isDown: isDown)
        case .swallow:
            break
        }
    }

    private func cancelNewestActive() {
        if let cancelled = queue.cancelNewestActive() {
            snapshots[cancelled] = nil
            if activeID == cancelled { activeID = nil }
            float = nil
            lastMessage = "已取消"
        }
    }

    // MARK: - 按键映射配置（设置页入口）

    /// 配置/清除某作用范围里一个按键的映射。`bundleID` 为 nil 表示默认表。
    func setShortcut(_ shortcut: Shortcut?, for button: RemoteButton, in bundleID: String?) {
        mutateKeyMap { $0.updateMapping(forBundleID: bundleID) { $0[button] = shortcut } }
    }

    /// 套用预设：把预设里的键写进指定作用范围（合并，不清掉用户已配的其它键）。
    func applyPreset(_ preset: KeyMapPreset, to bundleID: String?) {
        mutateKeyMap {
            $0.updateMapping(forBundleID: bundleID) { mapping in
                for (key, value) in preset.shortcuts { mapping.shortcuts[key] = value }
            }
        }
    }

    /// 确保某应用有专用映射（没有就以默认表为底克隆一份）。设置页「添加应用」用。
    func ensureAppMapping(_ bundleID: String) {
        guard !keyMap.hasMapping(forBundleID: bundleID) else { return }
        mutateKeyMap { $0.updateMapping(forBundleID: bundleID) { _ in } }
    }

    /// 移除某应用的专用映射（回落到默认表）。
    func removeAppMapping(_ bundleID: String) {
        mutateKeyMap { $0.removeMapping(forBundleID: bundleID) }
    }

    /// 开关按键接管：立即重启按键通道生效。
    func setKeyTakeover(_ on: Bool) {
        guard on != keyTakeover else { return }
        keyTakeover = on
        persistKeyConfig()
        keys.stop()
        keys.start(takeover: on)
        keyTakeoverActive = keys.isExclusive
    }

    /// 独占失败后重试接管（用户刚在系统设置里授完权的场景）。
    func retryTakeover() {
        guard keyTakeover, !keys.isExclusive else { return }
        keys.stop()
        keys.start(takeover: true)
        keyTakeoverActive = keys.isExclusive
        if keyTakeoverActive { lastMessage = "按键接管已生效" }
    }

    private func mutateKeyMap(_ transform: (inout KeyMapTable) -> Void) {
        transform(&keyMap)
        persistKeyConfig()
    }

    /// 每次改动即写盘。`Config.load()` 失败会返回空配置（连带抹掉 API Key），
    /// 所以这里基于读到的完整配置改写，而不是只写字段碎片。
    private func persistKeyConfig() {
        var config = Config.load()
        config.keyTakeover = keyTakeover
        config.keyMap = keyMap
        do {
            try Config.save(config)
        } catch {
            lastMessage = "按键配置保存失败：\(error.localizedDescription)"
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
                Log.chain.notice("transcribed id=\(id) chars=\(text.count)")
                await MainActor.run {
                    self.queue.transcriptionSucceeded(id: id, text: text)
                    self.drain()
                }
            } catch {
                Log.chain.error("transcribe failed id=\(id): \(error.localizedDescription)")
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
            Log.chain.error("drain id=\(next.id): no snapshot (录制时焦点快照失败) → targetLost")
            queue.targetLost(id: next.id)
            float = .attention
            lastMessage = "目标已失效，请选好输入框后点「输入到这里」"
            return
        }

        // 注入前重新比对焦点：变了就暂存，绝不强写。
        guard let current = TextInjector.snapshotFocus(), current == saved else {
            Log.chain.error("drain id=\(next.id): focus changed or snapshot now nil → targetLost")
            queue.targetLost(id: next.id)
            float = .attention
            lastMessage = "焦点已改变，请选好输入框后点「输入到这里」"
            return
        }

        do {
            let target = try TextInjector.inject(next.text, into: current)
            let path: String
            switch target {
            case .ax: path = "AX"
            case .paste: path = "paste"
            default: path = "?"
            }
            let targetApp = NSRunningApplication(processIdentifier: current.pid)?.bundleIdentifier ?? "?"
            Log.chain.notice("injected id=\(next.id) via \(path, privacy: .public) into \(targetApp, privacy: .public)")
            queue.injected(id: next.id)
            snapshots[next.id] = nil
            float = .inserted
            lastMessage = next.text
            drain()   // 继续下一条
        } catch {
            Log.chain.error("inject failed id=\(next.id): \(error.localizedDescription)")
            queue.injectionFailed(id: next.id, text: next.text)
            float = .attention
            lastMessage = error.localizedDescription
        }
    }

    // MARK: - 用户动作

    /// 「输入到这里」：把待处理文字写入当前焦点。
    func resumeHere(id: Int) {
        guard let snapshot = TextInjector.snapshotFocus() else {
            Log.chain.error("resumeHere id=\(id): snapshotFocus nil（无权限或无焦点元素）")
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
