import CoreGraphics
import Foundation

/// 一次按键事件该做什么。
public enum KeyDisposition: Equatable, Sendable {
    /// 未映射：原样转发原生按键（按下与抬起都要转，否则会卡键）。
    case passthrough
    /// 已映射：合成这条快捷键。
    case synthesize(Shortcut)
    /// 已映射为应用内动作（如打开模式选单）。
    case performAction(RemoteAction)
    /// 返回键在录音/转写进行中的优先职责（SPEC §6）。
    case cancelNewestActive
    /// 模式选单打开期间：方向键移动高亮（±1）。
    case pickerMove(Int)
    /// 模式选单打开期间：确认键选定当前高亮项。
    case pickerConfirm
    /// 模式选单打开期间：返回键关闭选单。
    case pickerDismiss
    /// 丢弃：语音/电源键、映射键的抬起、录音中的返回键抬起。
    case swallow
}

/// 按键 → 动作的**全部规则**，集中在这里。
///
/// 纯逻辑：不碰 CGEvent、不碰队列、不读时钟，全部输入都是参数，因此每一条规则都能
/// 写成测试。硬件相关的那一层（占没占住设备、事件怎么发）在别处，这里只回答"该干什么"。
public enum KeyRouter {
    /// 解析一次按键事件。
    ///
    /// - Parameters:
    ///   - isRepeat: 自动重复。实测本机遥控器不自动重复（按住语音键 1.95 秒只有一对
    ///     down/up），但这个参数是防御性的：真重复了也不能让 ⌘Z 连发二十次。
    ///   - hasActiveItem: 队列里是否有正在录音/转写的项——决定返回键听谁的。
    ///   - modePickerOpen: 模式选单是否打开。打开期间方向/确认/返回被临时捕获，
    ///     其余按键一律吞掉（用户正在和选单交互，不该有按键漏进前台应用）。
    public static func disposition(
        for button: RemoteButton,
        isDown: Bool,
        isRepeat: Bool,
        mapping: AppMapping,
        hasActiveItem: Bool,
        modePickerOpen: Bool = false
    ) -> KeyDisposition {
        // 语音键保留给按住说话（SPEC §1），电源键不接管（SPEC §3）。
        // 吞掉而不是转发：HID 键盘页 0x3E 是 F5，转发出去会往前台应用丢一个 F5
        // （在编辑器里是「开始调试」），正是接管要修掉的那个副作用。
        guard button.isMappable else { return .swallow }

        // 选单打开期间模态捕获：↑↓ 移动、确认选定、返回关闭，其它吞掉。
        // 连发放行（按住方向键连续移动是自然的选单手感的）。
        if modePickerOpen {
            guard isDown else { return .swallow }
            switch button {
            case .up: return .pickerMove(-1)
            case .down: return .pickerMove(1)
            case .confirm: return isRepeat ? .swallow : .pickerConfirm
            case .back: return isRepeat ? .swallow : .pickerDismiss
            default: return .swallow
            }
        }

        // 返回键在录音/转写进行中优先取消（SPEC §6）。抬起也要吞，否则会在取消
        // 录音的过程中往前台应用漏一个 Esc。
        if button == .back, hasActiveItem {
            return isDown && !isRepeat ? .cancelNewestActive : .swallow
        }

        // 抬起：映射过的键抬起不能转发，否则用户会收到"按下没发生、抬起发生了"
        // 这种半截事件；未映射的键抬起必须转发，否则目标应用认为键一直按着。
        guard isDown else {
            if mapping[button] != nil || mapping[action: button] != nil { return .swallow }
            // 未映射键里只有真正"转发"的才需要转抬起；返回键的内置默认（合成 Esc）
            // 在按下时已发完 down+up，抬起必须吞掉，否则按一次出两个 Esc。
            return passthroughDisposition(for: button) == .passthrough ? .passthrough : .swallow
        }

        // 应用内动作优先于快捷键（两者互斥，正常不会同时存在；动作胜出让行为可预期）。
        if let action = mapping[action: button] {
            return isRepeat ? .swallow : .performAction(action)
        }

        if let shortcut = mapping[button] {
            // 重复只发一次：按住不放不该让快捷键刷屏。
            return isRepeat ? .swallow : .synthesize(shortcut)
        }

        // 重复的未映射键照常转发，保持原生手感（按住方向键本来就该连移）。
        return passthroughDisposition(for: button)
    }

    /// 未映射按键的默认行为。
    ///
    /// 有原生等价键的（方向、确认、主页、菜单、音量）原样转发——接管不该让遥控器
    /// 变得比接管前更难用。没有原生等价键的（返回、TV）本来就没有行为可保留，
    /// 给内置默认：返回 → Esc（比"什么都不发生"有用），TV → 吞掉。
    public static func passthroughDisposition(for button: RemoteButton) -> KeyDisposition {
        if HIDKeyCode.isMediaKey(button) { return .passthrough }
        if HIDKeyCode.keyCode(forUsage: button.rawValue) != nil { return .passthrough }
        return button == .back ? .synthesize(Shortcut(keyCode: 0x35)) : .swallow  // 0x35 = kVK_Escape
    }
}
