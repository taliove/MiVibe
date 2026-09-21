import AppKit
import Foundation
import IOKit.hid
import MiVibeCore

/// 把遥控器、识别、改写、注入、队列串成一条链路（SPEC §6）。
///
/// 时序：按住语音键 → 抓焦点快照 → 设备自发 AUDIO_START → 收音频 → AUDIO_STOP 收口
/// → 转写 → （可选）改写 → **重新比对焦点** → 一致才注入，不一致就暂存等「输入到这里」。
@MainActor
final class Coordinator: ObservableObject {
    @Published private(set) var link: LinkState = .unpaired
    @Published private(set) var float: FloatState?
    @Published private(set) var queue = InputQueue()
    @Published var lastMessage: String = ""

    /// 二遍识别开关（SPEC §4 默认开）。仅对豆包引擎有意义。
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

    // MARK: - 识别引擎

    /// 当前识别引擎。豆包是历史默认；本地识别需要先下载模型。
    @Published private(set) var asrEngine: ASREngine
    /// 本地识别选用的模型 id。
    @Published private(set) var localModelID: String?

    /// 模型下载管理（设置页观察它的 states 渲染下载进度）。
    let modelStore = ModelStore()

    private let doubao = DoubaoClient()
    private var whisper: LocalWhisperProvider?
    private var whisperModelID: String?

    // MARK: - 改写

    /// 改写配置（当前模式 + 自定义模式 + LLM 服务商）。
    @Published private(set) var rewrite: RewriteConfig

    /// 关键词纠正表（识别与改写共用，见 CONTEXT.md）。
    @Published private(set) var keywords: [KeywordEntry]

    /// 改写结果缓存：键是队列项 id。改写发生在 drain 时（见 `drain()`），
    /// 注入失败重试时会清掉缓存重新改写——改写在当时是哪个模式就用哪个。
    private var rewrittenTexts: [Int: String] = [:]
    private var rewritingIDs: Set<Int> = []

    // MARK: - 模式选单

    struct ModePickerState: Equatable, Sendable {
        struct Item: Equatable, Sendable, Identifiable {
            let id: String
            let name: String
        }
        var items: [Item]
        var highlight: Int
    }

    /// 非 nil 表示选单打开。浮条据此渲染选单界面。
    @Published private(set) var picker: ModePickerState?
    private var pickerHideTimer: Timer?

    /// 实时音量电平外推口（0…1）。浮条监听它驱动那颗球的胀缩。
    /// 音频只在按住期间流出，所以这个回调也只在听音态触发。
    var onAudioLevel: ((Double) -> Void)?

    private let remote = RemoteManager()
    private let keys = KeyReader()
    private var meter = AudioLevelMeter()

    /// 每条录音按下时的焦点快照，注入前用于比对。
    private var snapshots: [Int: TextInjector.Snapshot] = [:]
    private var activeID: Int?

    /// 队列里还有没处理完的内容——菜单栏图标据此显示角标。
    ///
    /// 浮条会在超时后收起，"需处理"的内容却永不丢失；没有这个角标，一条转写文字
    /// 可以静静等你一辈子而屏幕上没有任何提示。
    var hasPendingWork: Bool { !queue.items.isEmpty }

    /// 当前改写模式的显示名（菜单栏弹层用）。
    var currentModeName: String { activeModeResolved.name(custom: rewrite.effectiveCustomModes) }

    var activeModeResolved: RewriteModes.Resolved {
        RewriteModes.resolve(activeID: rewrite.activeMode, custom: rewrite.effectiveCustomModes,
                             overrides: rewrite.effectiveBuiltinPrompts)
    }

    init() {
        let config = Config.load()
        keyMap = config.effectiveKeyMap.pruned()
        keyTakeover = config.effectiveKeyTakeover
        asrEngine = config.effectiveASRProvider
        localModelID = config.localModel
        rewrite = config.effectiveRewrite
        keywords = config.effectiveKeywords
        wireRemote()
        wireKeys()
    }

    func start() {
        remote.connect()
        keys.start(takeover: keyTakeover)
        keyTakeoverActive = keys.isExclusive
        Log.chain.notice("start: takeover=\(self.keyTakeover) exclusive=\(self.keys.isExclusive) asr=\(self.asrEngine.rawValue) mode=\(self.rewrite.effectiveActiveMode)")
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        Log.chain.notice("listenEvent access raw=\(access.rawValue) (0=unknown 1=denied 3=granted)")

        // 接管开着但没输入监控权限：主动发起系统请求，别等用户发现设置页。
        if keyTakeover && !Permissions.hasInputMonitoring() {
            Permissions.requestInputMonitoring()
        }

        // 用户去系统设置授权后回到 MiVibe，趁激活自动重试接管
        //（输入监控是进程启动时快照的权限，但新版 macOS 对运行中进程也会放行——
        // 重试一次就知道，不行用户再重启）。
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.retryTakeover() }
        }
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

            // 本地识别但没下载模型：不开始录音（语音键还按着，音频照样流出，
            // 但我们不收）。明确提示，不静默失败，更不偷偷联网走云端。
            if asrEngine == .local && currentWhisper() == nil {
                float = .attention
                lastMessage = "本地识别需要先下载模型，请到「设置 → 识别」下载"
                Log.chain.notice("AUDIO_START rejected: local engine without model")
                return
            }

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
                // 录音 HUD 常驻显示 引擎 · 改写模式（用户最需要确认"现在走的是哪条路"
                // 的时刻就是说话的那一刻）。
                let engineTag = asrEngine == .local ? "本地" : "豆包"
                lastMessage = "\(engineTag) · \(currentModeName)"
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
            // 再发起一次授权请求：`hasInputMonitoring()` 会被失配的旧 TCC 条目
            // 骗成"已授权"（条目在但身份对不上），启动时的预检因此可能漏弹授权框。
            // 失败这一刻是确凿的反例，补一次请求——系统认为已授权时这是 no-op。
            Permissions.requestInputMonitoring()
        }

        // 独占是持续争取的：设备连上才拿得到。状态变化实时反映给设置页。
        keys.onExclusiveChanged = { [weak self] active in
            guard let self else { return }
            keyTakeoverActive = active
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
            mapping: mapping, hasActiveItem: queue.newestActiveID != nil,
            modePickerOpen: picker != nil
        ) {
        case .cancelNewestActive:
            cancelNewestActive()
        case .synthesize(let shortcut):
            KeySynth.post(shortcut)
        case .performAction(let action):
            perform(action)
        case .pickerMove(let delta):
            pickerMove(delta)
        case .pickerConfirm:
            pickerConfirm()
        case .pickerDismiss:
            closePicker()
        case .passthrough:
            KeySynth.passthrough(key, isDown: isDown)
        case .swallow:
            break
        }
    }

    private func cancelNewestActive() {
        if let cancelled = queue.cancelNewestActive() {
            snapshots[cancelled] = nil
            rewrittenTexts[cancelled] = nil
            if activeID == cancelled { activeID = nil }
            float = nil
            lastMessage = "已取消"
        }
    }

    // MARK: - 应用内动作

    private func perform(_ action: RemoteAction) {
        switch action {
        case .openModePicker:
            openModePicker()
        }
    }

    // MARK: - 模式选单

    /// 全部可选模式：原文直出 + 内置 + 自定义。
    private var modeItems: [ModePickerState.Item] {
        [ModePickerState.Item(id: RewriteModes.rawID, name: "原文直出")]
            + RewriteModes.builtins.map { ModePickerState.Item(id: $0.id, name: $0.name) }
            + rewrite.effectiveCustomModes.map { ModePickerState.Item(id: $0.id, name: $0.name) }
    }

    private func openModePicker() {
        let items = modeItems
        let current = rewrite.effectiveActiveMode
        let highlight = items.firstIndex { $0.id == current } ?? 0
        picker = ModePickerState(items: items, highlight: highlight)
        schedulePickerHide()
    }

    private func pickerMove(_ delta: Int) {
        guard var p = picker else { return }
        let count = p.items.count
        p.highlight = (p.highlight + delta % count + count) % count
        picker = p
        schedulePickerHide()   // 有操作就续命
    }

    private func pickerConfirm() {
        guard let p = picker else { return }
        let item = p.items[p.highlight]
        closePicker()
        selectMode(item.id)
        float = .notice
        lastMessage = "已切换到：\(item.name)"
    }

    func closePicker() {
        picker = nil
        pickerHideTimer?.invalidate()
        pickerHideTimer = nil
    }

    /// 选单 6 秒无操作自动关闭。
    private func schedulePickerHide() {
        pickerHideTimer?.invalidate()
        pickerHideTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.closePicker() }
        }
    }

    // MARK: - 识别引擎与改写配置（设置页入口）

    func setASREngine(_ engine: ASREngine) {
        guard engine != asrEngine else { return }
        asrEngine = engine
        persist()
    }

    func setLocalModel(_ id: String?) {
        guard id != localModelID else { return }
        localModelID = id
        whisper = nil   // 下次转写时按新模型重建
        whisperModelID = nil
        persist()
    }

    /// 当前模式选择（设置页与选单共用）。
    func selectMode(_ id: String) {
        guard id != rewrite.effectiveActiveMode else { return }
        rewrite.activeMode = id
        rewrittenTexts.removeAll()   // 模式变了，缓存的改写结果作废
        persist()
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

    func setLLMProvider(_ provider: LLMProviderConfig?) {
        rewrite.provider = provider
        persist()
    }

    func saveCustomMode(_ mode: RewriteMode) {
        var custom = rewrite.effectiveCustomModes
        if let idx = custom.firstIndex(where: { $0.id == mode.id }) {
            custom[idx] = mode
        } else {
            custom.append(mode)
        }
        rewrite.customModes = custom
        persist()
    }

    func deleteCustomMode(_ id: String) {
        rewrite.customModes = rewrite.effectiveCustomModes.filter { $0.id != id }
        if rewrite.activeMode == id { rewrite.activeMode = RewriteModes.rawID }
        persist()
    }

    /// 内置模式 prompt 的用户覆盖（设置页「查看/调整提示词」入口）。
    func saveBuiltinPrompt(_ id: String, prompt: String) {
        var overrides = rewrite.effectiveBuiltinPrompts
        overrides[id] = prompt
        rewrite.builtinPrompts = overrides
        rewrittenTexts.removeAll()   // 模式语义变了，缓存作废
        persist()
    }

    /// 恢复内置模式的默认 prompt（删掉覆盖）。
    func resetBuiltinPrompt(_ id: String) {
        rewrite.builtinPrompts?.removeValue(forKey: id)
        rewrittenTexts.removeAll()
        persist()
    }

    /// 内置模式当前生效的 prompt（覆盖优先）。
    func effectiveBuiltinPrompt(_ id: String) -> String {
        rewrite.effectiveBuiltinPrompts[id]
            ?? RewriteModes.builtins.first { $0.id == id }?.prompt
            ?? ""
    }

    private func currentWhisper() -> LocalWhisperProvider? {
        guard asrEngine == .local,
              let id = localModelID,
              let model = ModelCatalog.model(id: id),
              modelStore.isDownloaded(model) else { return nil }
        if whisper == nil || whisperModelID != id {
            whisper = LocalWhisperProvider(modelURL: modelStore.url(for: model))
            whisperModelID = id
            whisper?.setVocabularyHint(KeywordCorrections.vocabularyHint(entries: keywords))
        }
        return whisper
    }

    // MARK: - 关键词纠正（设置页入口）

    func addKeyword(from: String, to: String) {
        let from = from.trimmingCharacters(in: .whitespaces)
        let to = to.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty, !to.isEmpty else { return }
        keywords.append(KeywordEntry(from: from, to: to))
        keywordsChanged()
    }

    func deleteKeyword(_ id: String) {
        keywords.removeAll { $0.id == id }
        keywordsChanged()
    }

    private func keywordsChanged() {
        rewrittenTexts.removeAll()   // 纠正表变了，缓存的改写结果作废
        persist()
        // 词表提示同步给本地引擎（还没建实例也没关系，创建时会带上）。
        whisper?.setVocabularyHint(KeywordCorrections.vocabularyHint(entries: keywords))
    }

    // MARK: - 按键映射配置（设置页入口）

    /// 配置/清除某作用范围里一个按键的快捷键映射。`bundleID` 为 nil 表示默认表。
    func setShortcut(_ shortcut: Shortcut?, for button: RemoteButton, in bundleID: String?) {
        mutateKeyMap { $0.updateMapping(forBundleID: bundleID) { $0[button] = shortcut } }
    }

    /// 配置/清除某作用范围里一个按键的应用内动作映射。
    func setAction(_ action: RemoteAction?, for button: RemoteButton, in bundleID: String?) {
        mutateKeyMap { $0.updateMapping(forBundleID: bundleID) { $0[action: button] = action } }
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
        persist()
        keys.stop()
        keys.start(takeover: on)
        keyTakeoverActive = keys.isExclusive
    }

    /// 独占失败后重试接管（用户刚在系统设置里授完权的场景）。
    /// 没权限时直接提示，别重启按键通道白跑一趟（自动重试也因此静默跳过）。
    func retryTakeover() {
        guard keyTakeover, !keys.isExclusive else { return }
        guard Permissions.hasInputMonitoring() else {
            lastMessage = "缺少「输入监控」权限，请先在系统设置中授权"
            return
        }
        keys.stop()
        keys.start(takeover: true)
        keyTakeoverActive = keys.isExclusive
        if keyTakeoverActive { lastMessage = "按键接管已生效" }
    }

    private func mutateKeyMap(_ transform: (inout KeyMapTable) -> Void) {
        transform(&keyMap)
        persist()
    }

    /// 每次改动即写盘。`Config.load()` 失败会返回空配置（连带抹掉 API Key），
    /// 所以这里基于读到的完整配置改写，而不是只写字段碎片。
    private func persist() {
        var config = Config.load()
        config.keyTakeover = keyTakeover
        config.keyMap = keyMap
        config.asrProvider = asrEngine.rawValue
        config.localModel = localModelID
        config.rewrite = rewrite
        config.keywords = keywords
        do {
            try Config.save(config)
        } catch {
            lastMessage = "配置保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 转写、改写与注入

    private func transcribe(id: Int, pcm: Data) {
        let provider: any ASRProvider
        switch asrEngine {
        case .doubao:
            provider = doubao
        case .local:
            guard let w = currentWhisper() else {
                queue.transcriptionFailed(id: id)
                float = .attention
                lastMessage = "本地模型不可用，请到「设置 → 识别」下载"
                return
            }
            provider = w
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                var options = DoubaoClient.Options()
                options.enableNonstream = enableNonstream
                await doubao.setProviderOptions(options)
                let text = try await provider.transcribe(pcm: pcm)
                // 关键词纠正：转写完成后立即做确定性替换（两个引擎都生效）。
                // 队列与待处理列表存的就是纠正后的文本——它是"识别结果"的一部分，
                // 不是改写（改写另由 RewriteEngine 在注入前做）。
                let corrected = KeywordCorrections.apply(text: text, entries: self.keywords)
                if corrected != text {
                    Log.chain.notice("keywords applied id=\(id): \(text)→\(corrected)")
                }
                Log.chain.notice("transcribed id=\(id) engine=\(self.asrEngine.rawValue) chars=\(corrected.count)")
                await MainActor.run {
                    self.queue.transcriptionSucceeded(id: id, text: corrected)
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
    ///
    /// 改写挂在这里而不是转写完成时：改写是注入前的一次性变换，待处理项重试
    /// （「输入到这里」）时会用**当时的**模式重新改写，队列里存的始终是原文。
    private func drain() {
        guard !queue.hasBlocker, let next = queue.injectable else { return }

        guard let saved = snapshots[next.id] else {
            Log.chain.error("drain id=\(next.id): no snapshot (录制时焦点快照失败) → targetLost")
            queue.targetLost(id: next.id)
            float = .attention
            lastMessage = "目标已失效，请选好输入框后点「输入到这里」"
            return
        }

        // 需要改写且还没改写好：先异步改写，完成后回到 drain 重新走一遍校验
        // （改写最多 5 秒，期间焦点可能漂移，必须重新比对，不能省事）。
        if needsRewrite(id: next.id) {
            rewritingIDs.insert(next.id)
            float = .polishing
            let config = rewrite
            let entries = keywords
            let raw = next.text
            let id = next.id
            Task { [weak self] in
                let text = await RewriteEngine.apply(text: raw, config: config, keywords: entries)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.rewritingIDs.remove(id)
                    self.rewrittenTexts[id] = text
                    self.drain()
                }
            }
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

        let text = rewrittenTexts[next.id] ?? next.text
        do {
            let target = try TextInjector.inject(text, into: current)
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
            rewrittenTexts[next.id] = nil
            float = .inserted
            lastMessage = text
            drain()   // 继续下一条
        } catch {
            Log.chain.error("inject failed id=\(next.id): \(error.localizedDescription)")
            queue.injectionFailed(id: next.id, text: next.text)
            rewrittenTexts[next.id] = nil   // 重试时用当时的模式重新改写
            float = .attention
            lastMessage = error.localizedDescription
        }
    }

    /// 是否需要为该项执行改写：当前是 LLM 模式 + 服务商配置完整 + 还没在改写/改写完。
    /// 任一条不满足都按原文直出——用户的话绝不卡在改写这一步。
    private func needsRewrite(id: Int) -> Bool {
        guard activeModeResolved.isRaw == false else { return false }
        guard rewrite.provider?.isComplete == true else { return false }
        return rewrittenTexts[id] == nil && !rewritingIDs.contains(id)
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
        rewrittenTexts[id] = nil
        if queue.items.isEmpty { float = nil }
    }

    func discardAll() {
        queue.discardAll()
        snapshots.removeAll()
        rewrittenTexts.removeAll()
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
