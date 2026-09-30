import AppKit
import MiVibeCore
import SwiftUI

// MARK: - 按键提示（issue #2、SPEC §13）
//
// 实体按键按下时在光标所在屏幕正中短暂显示「键名 → 实际结果」。独立面板，不与浮条
// 共用：浮条在屏幕底部跟随录音，按键提示在中央跟随按键，两者生命周期互不相干。
// 文案由 `KeyHint.make`（MiVibeCore，纯逻辑）决定，这里只负责显示与计时。

/// 按键提示的显示模型。
@MainActor
final class KeyHintModel: ObservableObject {
    @Published var hint: KeyHint?
    /// 显隐相位：false → true 播入场，true → false 播退场。连发只换文字，不动相位。
    @Published var visible = false
    /// 只观察不写入：主题切换时立刻重绘（同 FloatPanelModel）。
    let themeStore = AppDelegate.shared.themeStore
}

/// 不抢焦点、点击穿透、所有桌面与全屏应用可见的透明面板。
final class KeyHintPanel: NSPanel {
    static let size = NSSize(width: 360, height: 200)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // 阴影由 SwiftUI 表面画
        hidesOnDeactivate = false
        isMovable = false
        ignoresMouseEvents = true  // 点击穿透
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 居中到光标所在的屏幕（多屏时提示出现在用户正在看的那块）。
    func centerOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2))
    }
}

/// 按键提示控制器：由 AppDelegate 持有，`Coordinator.onKeyHint` 接到 `show(_:)`。
@MainActor
final class KeyHintPanelController {
    private let panel = KeyHintPanel()
    private let model = KeyHintModel()
    private var hideTimer: Timer?
    private var orderOutTimer: Timer?

    init() {
        panel.contentView = NSHostingView(rootView: KeyHintView(model: model))
    }

    /// 显示一次提示。已可见（含按住连发）时原地换字并续命，不叠加、不重播入场。
    func show(_ hint: KeyHint) {
        orderOutTimer?.invalidate()
        orderOutTimer = nil
        // 换字不带动画：连发时文字就地更新，不闪不跳。
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.hint = hint }

        if !panel.isVisible {
            panel.centerOnMouseScreen()
            panel.orderFrontRegardless()
            // 先渲染一帧隐藏初值，再在动画里推到可见，入场才播得出来。
            DispatchQueue.main.async { [model] in
                withAnimation(Motion.standard) { model.visible = true }
            }
        } else if !model.visible {
            // 退场途中又按键：从当前值反向回场。
            withAnimation(Motion.standard) { model.visible = true }
        }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: MotionTiming.keyHintHideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.hide() }
        }
    }

    private func hide() {
        withAnimation(Motion.exit) { model.visible = false }
        // withAnimation 的 completion 在 macOS 14 上不可靠，用等长定时器兜底收尾。
        orderOutTimer?.invalidate()
        orderOutTimer = Timer.scheduledTimer(withTimeInterval: MotionTiming.exitSettle, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.model.visible else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}

/// 提示内容：大字键名 + 小字「→ 结果」，沿用浮条的毛玻璃表面。
struct KeyHintView: View {
    @ObservedObject var model: KeyHintModel
    @ObservedObject private var themeStore: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: KeyHintModel) {
        self.model = model
        self._themeStore = ObservedObject(wrappedValue: model.themeStore)
    }

    var body: some View {
        ZStack {
            if let hint = model.hint {
                VStack(spacing: 6) {
                    Text(hint.title)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text("→").foregroundStyle(.secondary)
                        Text(hint.detail).foregroundStyle(Color.brandAccent)
                    }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                }
                .lineLimit(1)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .frame(minWidth: 132)
                .floatSurface(tint: nil, cornerRadius: 20)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(width: KeyHintPanel.size.width, height: KeyHintPanel.size.height)
        // 减弱动态效果时只淡入淡出；否则带一点缩放落位。
        .opacity(model.visible ? 1 : 0)
        .scaleEffect(model.visible || reduceMotion ? 1 : 0.94)
    }
}
