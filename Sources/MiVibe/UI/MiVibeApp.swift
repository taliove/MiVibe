import Combine
import MiVibeCore
import SwiftUI

/// 菜单栏图标驱动（epic #1 子任务 F）：正在听时按电平三档（0.45 / 0.75 / 1.0）
/// 切预先绘好的模板帧，每秒至多 6 帧（离散帧而不是平滑动画——菜单栏里平滑动画
/// 显得躁）；离开听音立即回到静态完整标记。帧节流用 `MotionTiming.FrameThrottle`，
/// 电平回调约 66 Hz，真正换帧最多 6 次 / 秒（AC8）。
@MainActor
final class MenuBarIconDriver: ObservableObject {
    /// 正在听时要显示的帧（nil = 静态完整标记，即不在听）。
    @Published private(set) var frame: NSImage?

    private var throttle = MotionTiming.FrameThrottle(fps: MotionTiming.menuBarMaxFPS)
    private var pattern = 0

    /// 推入实时电平 0…1（约 66 Hz）。节流到 ≤ 6 fps：每帧换一个跳动图案，
    /// 音量决定幅度档位——录音期间图标一直在跳，声音越大跳得越高。
    func push(level: Double) {
        guard throttle.shouldAdvance(at: ProcessInfo.processInfo.systemUptime) else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            frame = MenuBarIcon.listening
            return
        }
        let tier = MotionTiming.menuBarFrameIndex(level: level)
        pattern = (pattern + 1) % MotionTiming.menuBarPatterns.count
        frame = MenuBarIcon.levelFrames[tier][pattern]
        #if DEBUG
        Log.motion.debug("menubar frame → tier \(tier) pattern \(self.pattern)")
        #endif
    }

    /// 离开听音：清空帧，回到静态标记，并重置节流（下次开听第一帧立即放行）。
    func rest() {
        frame = nil
        pattern = 0
        throttle.reset()
    }
}

/// 应用入口：菜单栏常驻，无主窗口（Info.plist 设 LSUIElement=1）。
@main
struct MiVibeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var coordinator = Coordinator()
    /// 菜单栏电平帧驱动：AppDelegate.attach 时把电平回调接进来（F）。
    @StateObject private var menuBarDriver = MenuBarIconDriver()

    var body: some Scene {
        MenuBarExtra {
            MenuPopover(coordinator: coordinator)
        } label: {
            // 队列里还有没处理完的内容时挂个角标。浮条超时会自己收起，但内容不会
            // 丢——没有这个角标，用户就无从得知还有文字在等着处理。
            ZStack(alignment: .topTrailing) {
                // 品牌标记模板图标（epic #1 子任务 B）：isTemplate，深浅菜单栏由系统着色。
                // 正在听时按电平三档离散换帧（≤ 6 fps，F），其余状态用静态图。
                Image(nsImage: menuBarDriver.frame ?? MenuBarIcon.image(for: coordinator.link))
                if coordinator.hasPendingWork {
                    Circle()
                        .fill(Color.brandError)
                        .frame(width: 5, height: 5)
                        .offset(x: 2, y: -2)
                        // 待处理角标弹出（F：quick 缩放 0 → 1）。
                        .transition(.scale(scale: 0).combined(with: .opacity))
                }
            }
            .animation(Motion.quick, value: coordinator.hasPendingWork)
            // attach 必须在启动时就发生：它负责连遥控器、启动按键通道、创建浮条。
            // 原先挂在弹窗的 onAppear 上——用户不点开图标，整条语音链路就是死的。
            // label 在启动时即渲染，onAppear 随启动触发。
            .onAppear { AppDelegate.shared.attach(coordinator, menuBarDriver: menuBarDriver) }
        }
        .menuBarExtraStyle(.window)
    }
}

/// 浮条不能挂在 MenuBarExtra 的内容视图上——那个视图只在弹窗打开时存在，
/// 而浮条要在弹窗关闭时照常显示。所以由 AppDelegate 持有并驱动。
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static let shared = AppDelegate()

    /// 主题与外观的唯一入口。启动即创建（早于浮条），颜色扩展靠它维护当前主题。
    @MainActor let themeStore = ThemeStore()

    // 浮条只在 attach 时（主线程）创建，避免主 actor 隔离的默认值出现在
    // nonisolated 的 NSObject 初始化路径上。
    private var panel: FloatPanelController?
    /// 按键提示面板（屏幕中央）。与浮条同样由 AppDelegate 持有，不依赖菜单弹层。
    private var keyHintPanel: KeyHintPanelController?
    private var coordinator: Coordinator?
    private var cancellable: AnyCancellable?
    /// 设置窗口（NSToolbar 分页）。懒创建，关闭不销毁。
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 调试构建（从 .build 裸跑，不是 .app）时给 ggml 指 Metal 内核源码的位置——
        // 打包后内核在 Contents/Resources/kernels/，靠 mainBundle 找到，不需要这个。
        #if DEBUG
        if Bundle.main.bundleURL.pathExtension != "app" {
            setenv("GGML_METAL_PATH_RESOURCES",
                   URL(fileURLWithPath: #filePath)
                       .deletingLastPathComponent()  // UI
                       .deletingLastPathComponent()  // MiVibe
                       .deletingLastPathComponent()  // Sources
                       .deletingLastPathComponent()  // 仓库根
                       .appendingPathComponent("Vendor/whisper.cpp/ggml/src/ggml-metal").path, 1)
        }

        // 开发走查：MIVIBE_OPEN_SETTINGS=<pane> 启动后直接打开对应设置页
        // （值取 SettingsPane.rawValue，如 keyMapping）。仅 DEBUG 生效。
        if let pane = ProcessInfo.processInfo.environment["MIVIBE_OPEN_SETTINGS"] {
            Task { @MainActor in
                // 注意：协调器挂在 AppDelegate.shared 上（MenuBarExtra label 的 onAppear
                // 调的是 shared），不是 NSApplicationDelegateAdaptor 创建的这个实例。
                // attach 时机不定——轮询等它挂上。
                for _ in 0..<50 where AppDelegate.shared.coordinator == nil {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                AppDelegate.shared.showSettings(pane: SettingsPane(rawValue: pane) ?? .recognition)
            }
        }
        #endif
    }

    /// 正常退出：撤销遥控器重映射。系统调用的是 NSApplicationDelegateAdaptor 创建的
    /// 实例，协调器挂在 `shared` 上，所以转过去。
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppDelegate.shared.coordinator?.shutdown() }
    }

    /// SIGTERM（`pkill`、部署脚本、登出）不走 `applicationWillTerminate`，默认直接杀进程，
    /// 会把遥控器留在重映射状态——接住信号，撤销后再退出。
    @MainActor private var signalSources: [DispatchSourceSignal] = []

    @MainActor
    private func installTerminationSignalHandlers() {
        for sig in [SIGTERM, SIGHUP, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.coordinator?.shutdown() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    #if DEBUG
    /// 开发走查：MIVIBE_FLOAT_DEMO=1 启动后只轮播浮条各状态，**不挂协调器**——
    /// 不连遥控器、不写按键重映射，可与已安装的 MiVibe 同时运行。
    @MainActor private var demoPanel: FloatPanelController?

    @MainActor
    private func runFloatDemo() {
        let panel = FloatPanelController()
        demoPanel = panel
        // MIVIBE_FLOAT_DEMO=dark / light 强制外观（仅本次运行，不落盘），其他值跟随系统。
        switch ProcessInfo.processInfo.environment["MIVIBE_FLOAT_DEMO"] {
        case "dark": themeStore.set(appearance: .dark, persist: false)
        case "light": themeStore.set(appearance: .light, persist: false)
        default: break
        }
        // MIVIBE_FLOAT_DEMO=picker：复现「提示收起 → 打开选单 → 返回关闭 → 再次打开」，走查关闭时不闪旧浮条、再开时可见。
        // MIVIBE_FLOAT_DEMO=stack：两条录音交错、一条先收起、提示条、第三条被拒绝晃动。
        switch ProcessInfo.processInfo.environment["MIVIBE_FLOAT_DEMO"] {
        case "picker": FloatDemo.runPicker(panel)
        case "stack": FloatDemo.runStack(panel)
        default: FloatDemo.runCarousel(panel)
        }
    }

    @MainActor private var demoKeyHint: KeyHintPanelController?

    @MainActor
    private func runKeyHintDemo() {
        let panel = KeyHintPanelController()
        demoKeyHint = panel
        let interval = Double(ProcessInfo.processInfo.environment["MIVIBE_KEYHINT_DEMO_INTERVAL"] ?? "") ?? 2.0
        let samples = [
            KeyHint(title: "确认", detail: "⌘↩"),
            KeyHint(title: "菜单", detail: "模式选单"),
            KeyHint(title: "返回", detail: "Esc"),
            KeyHint(title: "返回", detail: KeyHint.cancelText),
            KeyHint(title: "确认", detail: KeyHint.systemHandledText),
        ]
        // 单次按键：每个样例之间留足时间让提示淡出。
        var script: [(Double, KeyHint)] = samples.map { (interval, $0) }
        // 连发：按住 ↓ 约 1 秒（每 80 ms 一次），提示应原地停留而不重播入场。
        let hold = KeyHint(title: "↓", detail: KeyHint.passthroughText)
        script.append((interval, hold))
        script += Array(repeating: (0.08, hold), count: 12)
        func run(_ index: Int) {
            guard index < script.count else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + script[index].0) {
                MainActor.assumeIsolated { panel.show(script[index].1) }
                run(index + 1)
            }
        }
        run(0)
    }

    @MainActor private var popoverPreview: NSWindow?

    @MainActor
    private func showPopoverPreview(_ coordinator: Coordinator) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: MenuPopover(coordinator: coordinator))
        window.center()
        window.orderFrontRegardless()
        popoverPreview = window
    }

    @MainActor private var menuBarDemoTimer: Timer?

    @MainActor
    private func runMenuBarDemo(_ driver: MenuBarIconDriver) {
        // 约 66 Hz 推入起伏的合成电平，与真实录音的回调频率一致。
        var t = 0.0
        menuBarDemoTimer = Timer.scheduledTimer(withTimeInterval: 0.015, repeats: true) { _ in
            t += 0.015
            let level = 0.5 + 0.5 * sin(t * 5.3) * sin(t * 1.7)
            MainActor.assumeIsolated { driver.push(level: level) }
        }
    }
    #endif

    /// 挂上协调器并开始驱动浮条。多次调用只生效一次。
    @MainActor
    func attach(_ coordinator: Coordinator, menuBarDriver: MenuBarIconDriver? = nil) {
        #if DEBUG
        // 开发走查：MIVIBE_KEYHINT_DEMO=1 只轮播按键提示（含一段连发），不挂协调器。
        if ProcessInfo.processInfo.environment["MIVIBE_KEYHINT_DEMO"] != nil {
            if demoKeyHint == nil { runKeyHintDemo() }
            return
        }
        if ProcessInfo.processInfo.environment["MIVIBE_FLOAT_DEMO"] != nil {
            if demoPanel == nil { runFloatDemo() }
            return
        }
        // 开发走查：MIVIBE_POPOVER_PREVIEW=1 把菜单弹层内容放进普通窗口，便于截图核对
        // （脚本点不开菜单栏弹层）。协调器照常挂接。
        if ProcessInfo.processInfo.environment["MIVIBE_POPOVER_PREVIEW"] != nil {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.showPopoverPreview(coordinator) }
            }
        }
        // 开发走查：MIVIBE_MENUBAR_DEMO=1 只用合成电平驱动菜单栏图标，不挂协调器。
        if ProcessInfo.processInfo.environment["MIVIBE_MENUBAR_DEMO"] != nil {
            if let menuBarDriver { runMenuBarDemo(menuBarDriver) }
            return
        }
        #endif
        guard self.coordinator == nil else { return }
        self.coordinator = coordinator
        let panel = FloatPanelController()
        self.panel = panel
        coordinator.onAudioLevel = { [weak panel, weak menuBarDriver] level in
            panel?.setLevel(level)
            menuBarDriver?.push(level: level)
        }
        coordinator.onPickerConfirmFlash = { [weak panel] in panel?.flashPickerConfirm() }
        let keyHintPanel = KeyHintPanelController()
        self.keyHintPanel = keyHintPanel
        coordinator.onKeyHint = { [weak keyHintPanel] hint in keyHintPanel?.show(hint) }
        installTerminationSignalHandlers()
        coordinator.start()

        // 事件驱动，不轮询。`objectWillChange` 在属性写入**之前**触发，所以推到
        // 下一个 run loop 回合再读：同一回合里连续改的队列与浮条列表会
        // 合并成一次刷新，也就读不到中间态。
        cancellable = coordinator.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self, weak coordinator, weak menuBarDriver] _ in
                guard let self, let coordinator else { return }
                self.panel?.update(entries: coordinator.floats)
                self.panel?.update(shakeCount: coordinator.floatShakeCount)
                self.panel?.update(picker: coordinator.picker)
                // 离开听音立即回到静态标记（AC8：1 帧内归位）。
                if !coordinator.isListening { menuBarDriver?.rest() }
            }
    }

    /// 打开设置窗口并激活 App。弹层「设置…」与 ⌘, 都走这里。
    @MainActor
    func showSettings(pane: SettingsPane? = nil) {
        guard let coordinator else { return }
        if settingsController == nil {
            settingsController = SettingsWindowController(coordinator: coordinator, themeStore: themeStore)
        }
        settingsController?.show(pane: pane)
        NSApp.activate(ignoringOtherApps: true)
    }
}
