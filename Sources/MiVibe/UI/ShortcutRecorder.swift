import MiVibeCore
import SwiftUI

/// 快捷键录制控件：点击进入录制态，按下的第一个组合键即成为新映射。
///
/// 用 local event monitor 就够了——录制发生在自己的设置窗口里，事件先到本应用，
/// 不需要全局监听（也不需要对应权限）。录制中按 Esc 取消。
///
/// 生命周期：monitor 只在录制态存在。视图消失、窗口失焦（用户切去别的 App）
/// 都会主动结束录制并移除 monitor——失焦后按键不再到达本进程，留着 monitor
/// 只会让按钮停在"按下快捷键…"的假录制态。
struct ShortcutRecorder: View {
    let shortcut: Shortcut?
    var onRecord: (Shortcut) -> Void
    /// 外部请求开始录制的令牌：父视图换一个新值（如 `UUID()`）即进入录制态，
    /// 用于「在此应用覆盖」这类一步到位的入口；nil 表示没有待处理的请求。
    var autoRecordToken: Binding<UUID?>?

    @State private var recording = false
    @State private var monitor: Any?
    @FocusState private var focused: Bool

    /// 便捷初始化：不需要外部触发录制时用这个。
    init(shortcut: Shortcut?, onRecord: @escaping (Shortcut) -> Void) {
        self.shortcut = shortcut
        self.onRecord = onRecord
        self.autoRecordToken = nil
    }

    /// 完整初始化：`autoRecordToken` 换新值即进入录制态（见属性注释）。
    init(shortcut: Shortcut?, autoRecordToken: Binding<UUID?>,
         onRecord: @escaping (Shortcut) -> Void) {
        self.shortcut = shortcut
        self.autoRecordToken = autoRecordToken
        self.onRecord = onRecord
    }

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "按下快捷键…（Esc 取消）" : (shortcut?.display ?? "点击录制"))
                .frame(minWidth: 120)
        }
        .controlSize(.small)
        .borderlessIfRecording(recording)
        .focused($focused)
        .onDisappear { stop() }
        // 窗口失焦即取消：录制结果来自本进程事件，失焦后收不到任何键。
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didResignKeyNotification
        )) { _ in stop() }
        .onChange(of: autoRecordToken?.wrappedValue) {
            guard autoRecordToken?.wrappedValue != nil else { return }
            // 消费掉这次请求再开始，避免录制器复用时旧令牌又触发一次。
            autoRecordToken?.wrappedValue = nil
            start()
        }
    }

    private func start() {
        recording = true
        focused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc 取消录制，不落盘。
            if event.keyCode == 0x35 {
                stop()
                return nil
            }
            let shortcut = Shortcut(
                keyCode: event.keyCode,
                flags: Shortcut.flags(from: event.modifierFlags)
            )
            onRecord(shortcut)
            stop()
            return nil   // 吞掉这次按键，别让它在设置窗口里触发别的东西
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

private extension View {
    /// 录制态用边框样式提示"正在听键"；常态保持普通按钮。
    @ViewBuilder
    func borderlessIfRecording(_ recording: Bool) -> some View {
        if recording {
            self.buttonStyle(.borderedProminent)
        } else {
            self
        }
    }
}
