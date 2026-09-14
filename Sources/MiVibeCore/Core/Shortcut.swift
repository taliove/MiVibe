import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// 一条要合成的键盘快捷键。
///
/// 存的是**键码 + 修饰键位**，不是字符：字符随键盘布局变，键码才是"键盘上那颗物理键"。
/// 用户按下 ⌘Z 时，无论在什么布局下，指的都是同一颗键。
public struct Shortcut: Codable, Equatable, Hashable, Sendable {
    /// 虚拟键码（`CGKeyCode` / `kVK_*`）。
    public var keyCode: UInt16
    /// 事件修饰键的 rawValue。**语义上**是 `CGEventFlags`，不是 `NSEvent.ModifierFlags`。
    ///
    /// 这两套 flag 在我们支持的四个修饰键上**数值恰好相同**（实测：command 都是
    /// 0x100000，shift 都是 0x20000，以此类推），所以从 `NSEvent` 强转过来在常见情况下
    /// 也能跑。但 `NSEvent.ModifierFlags` 还带着 capsLock(0x10000)、
    /// numericPad(0x200000)、function(0x800000) 这些 `CGEventFlags` 里没有对应含义的位——
    /// 强转会把它们一起带进来，正好撞上 `maskAlphaShift`(0x10000)。所以走
    /// `Shortcut.flags(from:)` 显式过滤，而不是强转。
    public var modifiers: UInt

    public init(keyCode: UInt16, modifiers: UInt = 0) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 直接给 `CGEventFlags` 的便捷构造——调用方大多手上就是这个类型。
    public init(keyCode: UInt16, flags: CGEventFlags) {
        self.init(keyCode: keyCode, modifiers: UInt(flags.rawValue))
    }

    public var cgFlags: CGEventFlags { CGEventFlags(rawValue: UInt64(modifiers)) }

    /// 显示串，例如 "⇧⌘P"、"↩"、"⎋"。
    public var display: String {
        Self.modifierSymbols(from: cgFlags) + Self.keyLabel(keyCode)
    }

    // MARK: - 修饰键

    /// `NSEvent.ModifierFlags` → `CGEventFlags` 的**显式**换算。
    ///
    /// 四个支持的修饰键在两套类型里数值相同，但 NSEvent 一侧还带着 capsLock、
    /// numericPad、function 等 `CGEventFlags` 里没有对应含义的位——capsLock(0x10000)
    /// 恰好会撞上 `maskAlphaShift`。所以逐项挑出来，而不是强转 rawValue。
    public static func flags(from eventFlags: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if eventFlags.contains(.command) { flags.insert(.maskCommand) }
        if eventFlags.contains(.shift) { flags.insert(.maskShift) }
        if eventFlags.contains(.option) { flags.insert(.maskAlternate) }
        if eventFlags.contains(.control) { flags.insert(.maskControl) }
        return flags
    }

    /// 只保留我们支持的四个修饰键，顺序固定为 ⌃⌥⇧⌘（Apple 的书写规范）。
    public static func modifierSymbols(from flags: CGEventFlags) -> String {
        var out = ""
        if flags.contains(.maskControl) { out += "⌃" }
        if flags.contains(.maskAlternate) { out += "⌥" }
        if flags.contains(.maskShift) { out += "⇧" }
        if flags.contains(.maskCommand) { out += "⌘" }
        return out
    }

    // MARK: - 键名

    /// 特殊键的可读名字。查不到就走当前键盘布局翻译成字符。
    public static func keyLabel(_ keyCode: UInt16) -> String {
        if let special = specialKeyLabels[keyCode] { return special }
        if let character = character(for: keyCode) { return character.uppercased() }
        return "键码 \(keyCode)"
    }

    /// 与布局无关的特殊键。键码取自 SDK 的 `HIToolbox/Events.h`（`kVK_*`）。
    private static let specialKeyLabels: [UInt16: String] = [
        0x24: "↩",        // Return
        0x4C: "⌤",        // Keypad Enter
        0x30: "⇥",        // Tab
        0x31: "空格",      // Space
        0x33: "⌫",        // Delete
        0x75: "⌦",        // Forward Delete
        0x35: "⎋",        // Escape
        0x73: "↖",        // Home
        0x77: "↘",        // End
        0x74: "⇞",        // Page Up
        0x79: "⇟",        // Page Down
        0x7B: "←",
        0x7C: "→",
        0x7D: "↓",
        0x7E: "↑",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]

    /// 用当前键盘布局把键码翻成字符。取不到就返回 nil，由调用方兜底。
    private static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Foundation.Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return -1
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
