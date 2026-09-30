import AppKit
import Combine
import MiVibeCore
import SwiftUI

extension Notification.Name {
    /// 详情页看过外观页后发此通知，侧栏收到即隐藏「新」胶囊。
    static let settingsAppearancePaneSeen = Notification.Name("MiVibeSettingsAppearancePaneSeen")
}

/// 设置窗口控制器：侧栏分页（设备状态卡 + 导航）+ 详情列。
///
/// SPEC §7 的基线曾是「工具栏分页」，后改为侧栏（导航项多了以后工具栏放不下，
/// 侧栏还能常驻设备连接状态）。窗口外观对齐系统设置：`NSSplitViewController`
/// 的 sidebar 项配合全尺寸内容区，侧栏贯通到标题栏、红绿灯落在侧栏里，
/// 与详情列不再是上下两截（macOS 26 上侧栏自动成为悬浮玻璃面板）。
///
/// 工具栏：显示当前页名，页名左侧是前进 / 后退导航按钮（落在详情列区域，
/// 与系统设置一致）；页名与按钮可用性跟随 `SettingsPaneModel` 的导航历史。
///
/// 高度：各页共用同一窗口高度，切页不伸缩；内容超出由详情列滚动。窗口只允许
/// 纵向拉伸（宽度固定避免详情列重排），尺寸与位置按 autosave 名记住。
///
/// 控制器由 `AppDelegate` 懒创建并常驻持有，关闭窗口只是 `orderOut`，状态不丢。
@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate {
    /// 详情列固定内容宽。
    static let contentWidth: CGFloat = 640
    /// 侧栏列宽（macOS 26 玻璃侧栏四周有内缩，比旧版纯色侧栏略宽）。
    static let sidebarWidth: CGFloat = 210
    /// 默认内容高度与可拉伸下限。
    private static let defaultHeight: CGFloat = 640
    private static let minHeight: CGFloat = 460
    private static let autosaveName = "MiVibeSettingsWindow"

    private let window: NSWindow
    private let paneModel: SettingsPaneModel
    /// 侧栏视图（「新」胶囊显隐由详情页状态回流更新）。
    private weak var sidebarController: NSHostingController<SettingsSidebar>?
    /// ⌘数字切页、⌘[ / ⌘] 前进后退。只在窗口是 key 时响应；控制器与 App 同寿命，
    /// monitor 一次安装、deinit 移除，不存在重复注册。
    /// nonisolated(unsafe)：deinit 非隔离，需要能读到它。
    private nonisolated(unsafe) var keyMonitor: Any?
    /// 前进 / 后退两段式按钮（每段 enabled 跟随 paneModel 的历史状态）。
    private weak var navigationControl: NSSegmentedControl?
    /// paneModel 的订阅（页名与导航可用性）。
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: Coordinator, themeStore: ThemeStore) {
        let paneModel = SettingsPaneModel()
        self.paneModel = paneModel

        let sidebar = NSHostingController(rootView: SettingsSidebar(
            coordinator: coordinator, paneModel: paneModel,
            showAppearanceNewBadge: Config.load().appearancePaneSeen != true))
        let detail = NSHostingController(rootView: SettingsView(
            coordinator: coordinator, paneModel: paneModel, themeStore: themeStore))
        sidebarController = sidebar
        // 尺寸由窗口决定，不让 SwiftUI 的理想尺寸反向约束窗口（否则切页又会伸缩）。
        sidebar.sizingOptions = []
        detail.sizingOptions = []

        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = Self.contentWidth
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)

        let totalWidth = Self.sidebarWidth + Self.contentWidth
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: totalWidth, height: Self.defaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // 页名显示在工具栏（系统设置同款：unified 样式下标题落在导航按钮右侧）。
        window.title = paneModel.pane.title
        window.titleVisibility = .visible
        // 工具栏保留材质背景：详情列内容上滚时从它下面穿过，不与页名叠字。
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.contentViewController = split
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: totalWidth, height: Self.defaultHeight))
        window.contentMinSize = NSSize(width: totalWidth, height: Self.minHeight)
        window.contentMaxSize = NSSize(width: totalWidth, height: .greatestFiniteMagnitude)
        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
        self.window = window
        super.init()

        // delegate 必须在挂到窗口之前设好：工具栏在挂上窗口时加载默认项，
        // 之后才设 delegate 的话导航按钮永远不会出现。
        let toolbar = NSToolbar(identifier: "MiVibeSettings")
        toolbar.delegate = self
        // 只显示图标：系统设置的导航按钮下方没有文字标签。
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        // 页名与导航可用性跟随选中页。
        paneModel.$pane
            .map(\.title)
            .removeDuplicates()
            .sink { [weak self] title in self?.window.title = title }
            .store(in: &cancellables)
        // 「新」胶囊：详情页一旦看过外观页（appearancePaneSeen 回流为 true），侧栏立即隐藏。
        NotificationCenter.default.publisher(for: .settingsAppearancePaneSeen)
            .sink { [weak self] _ in
                guard let self, var root = self.sidebarController?.rootView else { return }
                root.showAppearanceNewBadge = false
                self.sidebarController?.rootView = root
            }
            .store(in: &cancellables)
        paneModel.$canGoBack
            .removeDuplicates()
            .sink { [weak self] in self?.navigationControl?.setEnabled($0, forSegment: Segment.back) }
            .store(in: &cancellables)
        paneModel.$canGoForward
            .removeDuplicates()
            .sink { [weak self] in self?.navigationControl?.setEnabled($0, forSegment: Segment.forward) }
            .store(in: &cancellables)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 这里只做纯值判断（修饰键 + 字符），NSEvent 不跨隔离域。
            guard let self,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  let chars = event.charactersIgnoringModifiers,
                  chars.count == 1, let char = chars.first
            else { return event }
            // local monitor 在主线程回调：同步判断，设置窗不是 key 时原样放行，
            // 不吞掉其他窗口（弹层、浮条）的 ⌘ 组合键。
            let handled = MainActor.assumeIsolated {
                self.window.isKeyWindow && self.handleShortcut(char)
            }
            return handled ? nil : event
        }
    }

    /// ⌘[ 后退、⌘] 前进、⌘数字切页。返回是否已处理（已处理的事件被吞掉）。
    private func handleShortcut(_ char: Character) -> Bool {
        switch char {
        case "[":
            paneModel.goBack()
            return true
        case "]":
            paneModel.goForward()
            return true
        default:
            guard let digit = Int(String(char)),
                  let pane = SettingsPane.pane(forShortcutDigit: digit)
            else { return false }
            paneModel.pane = pane
            return true
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    /// 显示窗口并置于最前；可选先切到指定页。多次调用幂等。
    func show(pane: SettingsPane? = nil) {
        if let pane { paneModel.pane = pane }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSToolbarDelegate

    /// 工具栏项：侧栏分隔线之后放一个导航组（落在详情列、页名左侧）。
    private enum ToolbarItem {
        static let navigation = NSToolbarItem.Identifier("MiVibeSettings.navigation")
    }

    /// 导航分段序号。
    private enum Segment {
        static let back = 0
        static let forward = 1
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == ToolbarItem.navigation else { return nil }
        let images = [("chevron.left", "后退"), ("chevron.right", "前进")].compactMap {
            NSImage(systemSymbolName: $0.0, accessibilityDescription: $0.1)
        }
        let control = NSSegmentedControl(images: images, trackingMode: .momentary,
                                         target: self, action: #selector(navigationClicked(_:)))
        control.setToolTip("后退", forSegment: Segment.back)
        control.setToolTip("前进", forSegment: Segment.forward)
        control.setEnabled(paneModel.canGoBack, forSegment: Segment.back)
        control.setEnabled(paneModel.canGoForward, forSegment: Segment.forward)
        navigationControl = control

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "后退 / 前进"
        item.paletteLabel = "后退 / 前进"
        item.view = control
        item.isNavigational = true
        return item
    }

    @objc private func navigationClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == Segment.back { paneModel.goBack() } else { paneModel.goForward() }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, ToolbarItem.navigation]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, ToolbarItem.navigation]
    }
}
