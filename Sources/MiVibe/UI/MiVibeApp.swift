import Combine
import MiVibeCore
import SwiftUI

/// 应用入口：菜单栏常驻，无主窗口（Info.plist 设 LSUIElement=1）。
@main
struct MiVibeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var coordinator = Coordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuPopover(coordinator: coordinator)
        } label: {
            // 队列里还有没处理完的内容时挂个角标。浮条超时会自己收起，但内容不会
            // 丢——没有这个角标，用户就无从得知还有文字在等着处理。
            ZStack(alignment: .topTrailing) {
                Image(systemName: coordinator.link.icon)
                if coordinator.hasPendingWork {
                    Circle()
                        .fill(.red)
                        .frame(width: 5, height: 5)
                        .offset(x: 2, y: -2)
                }
            }
            // attach 必须在启动时就发生：它负责连遥控器、启动按键通道、创建浮条。
            // 原先挂在弹窗的 onAppear 上——用户不点开图标，整条语音链路就是死的。
            // label 在启动时即渲染，onAppear 随启动触发。
            .onAppear { AppDelegate.shared.attach(coordinator) }
        }
        .menuBarExtraStyle(.window)
    }
}

/// 浮条不能挂在 MenuBarExtra 的内容视图上——那个视图只在弹窗打开时存在，
/// 而浮条要在弹窗关闭时照常显示。所以由 AppDelegate 持有并驱动。
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static let shared = AppDelegate()

    // 浮条只在 attach 时（主线程）创建，避免主 actor 隔离的默认值出现在
    // nonisolated 的 NSObject 初始化路径上。
    private var panel: FloatPanelController?
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

    /// 挂上协调器并开始驱动浮条。多次调用只生效一次。
    @MainActor
    func attach(_ coordinator: Coordinator) {
        guard self.coordinator == nil else { return }
        self.coordinator = coordinator
        let panel = FloatPanelController()
        self.panel = panel
        coordinator.onAudioLevel = { [weak panel] level in panel?.setLevel(level) }
        coordinator.start()

        // 事件驱动，不轮询。`objectWillChange` 在属性写入**之前**触发，所以推到
        // 下一个 run loop 回合再读：同一回合里连续改的 float 与 lastMessage 会
        // 合并成一次刷新，也就读不到中间态。
        cancellable = coordinator.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self, weak coordinator] _ in
                guard let self, let coordinator else { return }
                self.panel?.update(state: coordinator.float, message: coordinator.lastMessage)
                self.panel?.update(picker: coordinator.picker)
            }
    }

    /// 打开设置窗口并激活 App。弹层「设置…」与 ⌘, 都走这里。
    @MainActor
    func showSettings(pane: SettingsPane? = nil) {
        guard let coordinator else { return }
        if settingsController == nil {
            settingsController = SettingsWindowController(coordinator: coordinator)
        }
        settingsController?.show(pane: pane)
        NSApp.activate(ignoringOtherApps: true)
    }
}
