import Foundation

/// 遥控器实体按键的身份（HID usage page 0x07，SPEC §2）。
///
/// 纯逻辑：不认识 IOKit、不认识 UI，可脱离硬件测试。之所以从 `KeyReader` 里提出来，
/// 是因为"按键有哪些""哪个能映射""中文叫什么"是产品概念，不是硬件细节——原来的
/// 中文名表被抄在 `RemoteControlView.keyName` 里重复了一份。
public enum RemoteButton: UInt32, CaseIterable, Sendable {
    case up = 0x52
    case down = 0x51
    case left = 0x50
    case right = 0x4F
    case confirm = 0x28
    case back = 0xF1
    case volumeUp = 0x80
    case volumeDown = 0x81
    case home = 0x4A
    case menu = 0x65
    case tv = 0x35
    case voice = 0x3E
    case power = 0x66   // 本机系统无响应，不接管（SPEC §3）

    /// 配置文件里的稳定键名。**一旦发布不得改名**——老配置靠它找回映射，
    /// 改名等于静默丢弃用户配过的所有按键。
    public var id: String {
        switch self {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        case .confirm: return "confirm"
        case .back: return "back"
        case .volumeUp: return "volumeUp"
        case .volumeDown: return "volumeDown"
        case .home: return "home"
        case .menu: return "menu"
        case .tv: return "tv"
        case .voice: return "voice"
        case .power: return "power"
        }
    }

    public var displayName: String {
        switch self {
        case .up: return "上"
        case .down: return "下"
        case .left: return "左"
        case .right: return "右"
        case .confirm: return "确认"
        case .back: return "返回"
        case .volumeUp: return "音量+"
        case .volumeDown: return "音量-"
        case .home: return "主页"
        case .menu: return "菜单"
        case .tv: return "TV"
        case .voice: return "语音"
        case .power: return "电源"
        }
    }

    /// 是否允许用户映射。
    ///
    /// - 语音键：**始终保留给按住说话**（SPEC §1），映射层不得染指。
    /// - 电源键：系统本就无响应，且 SPEC §3 明确不接管。
    ///
    /// 把这条规则做成类型层面的谓词而不是注释，是为了让映射表在构造时就无法包含它们。
    public var isMappable: Bool { self != .voice && self != .power }

    /// 可映射的按键，顺序即设置页的展示顺序。
    public static var mappable: [RemoteButton] { allCases.filter(\.isMappable) }

    /// 从配置里的稳定键名还原。未知名字返回 nil（老配置里可能有已删除的键）。
    public static func from(id: String) -> RemoteButton? {
        allCases.first { $0.id == id }
    }
}
