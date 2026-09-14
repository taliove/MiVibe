import MiVibeCore
import SwiftUI

/// 快捷键录制控件：点击进入录制态，按下的第一个组合键即成为新映射。
///
/// 用 local event monitor 就够了——录制发生在自己的设置窗口里，事件先到本应用，
/// 不需要全局监听（也不需要对应权限）。录制中按 Esc 取消。
struct ShortcutRecorder: View {
    let shortcut: Shortcut?
    var onRecord: (Shortcut) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "按下快捷键…（Esc 取消）" : (shortcut?.display ?? "点击录制"))
                .frame(minWidth: 120)
        }
        .controlSize(.small)
        .borderlessIfRecording(recording)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
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
