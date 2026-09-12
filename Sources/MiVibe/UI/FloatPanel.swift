import AppKit
import MiVibeCore
import SwiftUI

/// 底部状态浮条：**不抢焦点**。
///
/// `.nonactivatingPanel` + `canBecomeKey/Main = false` 双重保险，原型阶段已实测
/// （浮条轮播期间在 TextEdit 打字不被打断）。这是"松手直接输入"能成立的前提：
/// 浮条一旦抢焦点，目标输入框就没了。
final class FloatPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 56),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // 阴影由 SwiftUI 层画，避免 borderless 的方角阴影
        hidesOnDeactivate = false
        isMovable = false
        ignoresMouseEvents = true  // 纯状态显示，不接受点击
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.minY + 22))
    }
}

struct FloatBarView: View {
    let state: FloatState
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(state.color)
                .frame(width: 9, height: 9)
            Text(state.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(message.isEmpty ? state.hint : message)
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.84))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 560, height: 56)
        .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}

/// 浮条的显示控制器：状态变化时更新内容，无状态时隐藏。
@MainActor
final class FloatPanelController {
    private let panel = FloatPanel()
    private var shown: FloatState?
    private var shownMessage = ""

    func update(state: FloatState?, message: String) {
        guard state != shown || message != shownMessage else { return }
        shown = state
        shownMessage = message

        guard let state else {
            panel.orderOut(nil)
            return
        }
        panel.contentView = NSHostingView(rootView: FloatBarView(state: state, message: message))
        panel.positionBottomCenter()
        panel.orderFrontRegardless()
    }
}
