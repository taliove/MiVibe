import CoreGraphics
import Foundation

/// HID usage（键盘页 0x07）→ macOS 虚拟键码。
///
/// **这张表必须来自实测，不能凭记忆写。** 遥控器的每个按键在 HID 里是什么 usage 是
/// 测出来的，而 system 把它当成哪颗键则要进一步确认——`RemoteButton` 的 usage 来自
/// `hid-probe` 的真机采集，键码取自 SDK 的 `HIToolbox/Events.h`。
///
/// 查不到返回 nil。这**不是**异常情况：返回键 `0xF1` 在 HID 键盘页里就不是标准键，
/// 它没有原生等价键，这正是它按下去本来什么都不发生的原因。
public enum HIDKeyCode {
    public static func keyCode(forUsage usage: UInt32) -> CGKeyCode? {
        switch RemoteButton(rawValue: usage) {
        case .up: return 0x7E        // kVK_UpArrow
        case .down: return 0x7D      // kVK_DownArrow
        case .left: return 0x7B      // kVK_LeftArrow
        case .right: return 0x7C     // kVK_RightArrow
        case .confirm: return 0x24   // kVK_Return
        case .home: return 0x73      // kVK_Home
        case .menu: return 0x6E      // kVK_ContextualMenu
        case .tv: return 0x32        // kVK_ANSI_Grave（`~` 键）
        case .volumeUp, .volumeDown:
            // 音量键不是普通键盘键：macOS 把 HID 键盘页的音量 usage 变成
            // NX_SYSDEFINED 媒体事件，而不是 keyDown。转发走 KeySynth.postMediaKey。
            return nil
        case .back, .voice, .power, .none:
            return nil
        }
    }

    /// 该按键是否走媒体键通道（音量键）。
    public static func isMediaKey(_ button: RemoteButton) -> Bool {
        button == .volumeUp || button == .volumeDown
    }
}
