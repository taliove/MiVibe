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
                .onAppear { AppDelegate.shared.attach(coordinator) }
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
        }
        .menuBarExtraStyle(.window)

        Window("设置", id: "settings") {
            SettingsView(coordinator: coordinator)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentSize)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
            }
    }
}
