import AppKit
import CoreGraphics
import Foundation

/// 按键事件的**执行层**：把 `KeyRouter` 的裁决变成真实的 CGEvent。
///
/// 接管后系统不再响应遥控器的按键（按设备重映射成死键），所有按键都得由这里重新发出去——
/// 包括未映射键的原生行为（转发）。所以本层只回答"怎么发"，不回答"该不该发"。
///
/// 事件投递需要「事件投递」权限（`CGPreflightPostEventAccess`，与文本注入同一项）。
public enum KeySynth {
    /// 合成一条快捷键：按下 + 抬起。修饰键两段都带——
    /// 抬起时清掉修饰会让某些应用把这段事件解读成别的组合。
    public static func post(_ shortcut: Shortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)
        down?.flags = shortcut.cgFlags
        up?.flags = shortcut.cgFlags
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    /// 原样转发未映射键的原生行为（按下与抬起都转，卡键比少一次按键更糟）。
    ///
    /// 音量键不是普通键盘键，走媒体事件通道。查不到键码的键（返回/语音/电源）
    /// 在路由层就不会走到这里；真走到了就什么都不做——没有行为可转发。
    public static func passthrough(_ button: RemoteButton, isDown: Bool) {
        if HIDKeyCode.isMediaKey(button) {
            postMediaKey(button, isDown: isDown)
            return
        }
        guard let keyCode = HIDKeyCode.keyCode(forUsage: button.rawValue) else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
        event?.post(tap: .cgSessionEventTap)
    }

    /// 音量键：macOS 把 HID 键盘页的音量 usage 翻译成 NX_SYSDEFINED 媒体事件
    ///（subtype 8），而不是 keyDown。转发必须照这条路走，否则系统音量不响应。
    public static func postMediaKey(_ button: RemoteButton, isDown: Bool) {
        // NX_KEYTYPE_SOUND_UP/DOWN，见 IOKit `hidsystem/ev_keymap.h`。
        let key: UInt32
        switch button {
        case .volumeUp: key = 0
        case .volumeDown: key = 1
        default: return
        }
        // 0xA00 = 按下，0xB00 = 抬起（data1 高 16 位是键号，低 16 位是标志）。
        let flags: UInt32 = isDown ? 0xA00 : 0xB00
        let data1 = Int((key << 16) | (flags << 8))
        guard let nsEvent = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        nsEvent.cgEvent?.post(tap: .cgSessionEventTap)
    }
}
