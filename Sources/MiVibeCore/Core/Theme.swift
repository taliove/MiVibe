import Foundation

/// 品牌主题色板（epic #1 子任务 A，设计依据 .scratch/mivibe/design/design-system-v3.html）。
///
/// 纯数据层，不依赖 SwiftUI/AppKit：MiVibeCore 的规则是无界面依赖，
/// 动态颜色桥接在 MiVibe/UI/Brand.swift。
///
/// 取值分两侧：
/// - 浅色侧（accent / accentStrong / accentSoft）：图标、描边、文字链接、着色背景。
/// - 深色侧（accentDark / accentSoftDark / onAccentDark）：深色下的对应角色。
/// 填充面上的文字必须 ≥ 4.5:1（WCAG AA）：浅色填充用 accentStrong 配白字，
/// 深色填充用 accentDark 配墨绿字（白字压在深色 accent 上只有 1.4–2.9:1，不合格）。

/// 8 位 RGB。`hex` 形如 0x0C98A8。
public struct RGB: Equatable, Sendable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(hex: UInt32) {
        self.init(
            r: UInt8((hex >> 16) & 0xFF),
            g: UInt8((hex >> 8) & 0xFF),
            b: UInt8(hex & 0xFF)
        )
    }
}

/// 可选主题。rawValue 同时是配置里的持久化值，不得改名。
public enum ThemeID: String, CaseIterable, Sendable {
    case tide      // 潮汐青（默认）
    case indigo    // 靛蓝
    case coral     // 珊瑚
    case orchid    // 兰紫
    case rose      // 玫瑰
    case graphite  // 石墨
}

/// 外观模式。rawValue 同时是配置里的持久化值，不得改名。
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// 一套主题的完整色值。
public struct ThemePalette: Sendable {
    public let id: ThemeID
    /// 中文名，设置界面直接展示。
    public let displayName: String
    /// 浅色：图标、指示点、描边。
    public let accent: RGB
    /// 浅色：填充面（配白字）、文字链接。
    public let accentStrong: RGB
    /// 浅色：着色背景（推荐标签、选中行、品牌横幅）。
    public let accentSoft: RGB
    /// 深色：图标、指示点、填充面（配 onAccentDark 墨绿字）。
    public let accentDark: RGB
    /// 深色：着色背景。
    public let accentSoftDark: RGB
    /// 深色填充面上的文字色（全部主题统一 #13201F）。
    public let onAccentDark: RGB
    /// 应用图标渐变两端。
    public let iconTop: RGB
    public let iconBottom: RGB

    public init(
        id: ThemeID,
        displayName: String,
        accent: RGB,
        accentStrong: RGB,
        accentSoft: RGB,
        accentDark: RGB,
        accentSoftDark: RGB,
        onAccentDark: RGB,
        iconTop: RGB,
        iconBottom: RGB
    ) {
        self.id = id
        self.displayName = displayName
        self.accent = accent
        self.accentStrong = accentStrong
        self.accentSoft = accentSoft
        self.accentDark = accentDark
        self.accentSoftDark = accentSoftDark
        self.onAccentDark = onAccentDark
        self.iconTop = iconTop
        self.iconBottom = iconBottom
    }

    /// 深色填充面文字色，六套主题共用。
    private static let inkOnDarkAccent = RGB(hex: 0x13201F)

    public static func palette(_ id: ThemeID) -> ThemePalette {
        switch id {
        case .tide:
            return ThemePalette(
                id: .tide, displayName: "潮汐青",
                accent: RGB(hex: 0x0C98A8), accentStrong: RGB(hex: 0x08717F),
                accentSoft: RGB(hex: 0xD7F1F2), accentDark: RGB(hex: 0x22B8C6),
                accentSoftDark: RGB(hex: 0x0F3439), onAccentDark: inkOnDarkAccent,
                iconTop: RGB(hex: 0x16B4C2), iconBottom: RGB(hex: 0x086978)
            )
        case .indigo:
            return ThemePalette(
                id: .indigo, displayName: "靛蓝",
                accent: RGB(hex: 0x4F5BD5), accentStrong: RGB(hex: 0x3A44B0),
                accentSoft: RGB(hex: 0xE3E5FB), accentDark: RGB(hex: 0x8591F5),
                accentSoftDark: RGB(hex: 0x1E2350), onAccentDark: inkOnDarkAccent,
                iconTop: RGB(hex: 0x6272F0), iconBottom: RGB(hex: 0x3B3FB8)
            )
        case .coral:
            return ThemePalette(
                id: .coral, displayName: "珊瑚",
                accent: RGB(hex: 0xE0503A), accentStrong: RGB(hex: 0xB83A27),
                accentSoft: RGB(hex: 0xFBE3DE), accentDark: RGB(hex: 0xFF7A62),
                accentSoftDark: RGB(hex: 0x43201A), onAccentDark: inkOnDarkAccent,
                iconTop: RGB(hex: 0xFF7157), iconBottom: RGB(hex: 0xC9362A)
            )
        case .orchid:
            return ThemePalette(
                id: .orchid, displayName: "兰紫",
                accent: RGB(hex: 0x8A4FD6), accentStrong: RGB(hex: 0x6C38B3),
                accentSoft: RGB(hex: 0xEEE3FB), accentDark: RGB(hex: 0xB48AF5),
                accentSoftDark: RGB(hex: 0x2E1D4A), onAccentDark: inkOnDarkAccent,
                iconTop: RGB(hex: 0xA56BF0), iconBottom: RGB(hex: 0x6A33B8)
            )
        case .rose:
            return ThemePalette(
                id: .rose, displayName: "玫瑰",
                accent: RGB(hex: 0xD2457A), accentStrong: RGB(hex: 0xA93360),
                accentSoft: RGB(hex: 0xFADFE9), accentDark: RGB(hex: 0xF27AA6),
                accentSoftDark: RGB(hex: 0x45192B), onAccentDark: inkOnDarkAccent,
                iconTop: RGB(hex: 0xEC5F93), iconBottom: RGB(hex: 0xB02F63)
            )
        case .graphite:
            return ThemePalette(
                id: .graphite, displayName: "石墨",
                accent: RGB(hex: 0x2E3A40), accentStrong: RGB(hex: 0x2E3A40),
                accentSoft: RGB(hex: 0xE1E6E8), accentDark: RGB(hex: 0xD5DEE1),
                accentSoftDark: RGB(hex: 0x222C31), onAccentDark: inkOnDarkAccent,
                iconTop: RGB(hex: 0x46545B), iconBottom: RGB(hex: 0x1B2327)
            )
        }
    }
}

/// 语义色：表示「结果」，不随主题变化。浮条与链路状态用它们表达成功 / 提示 / 错误。
public enum SemanticPalette {
    public static let success = (light: RGB(hex: 0x1D9A57), dark: RGB(hex: 0x3CC97D))
    public static let attention = (light: RGB(hex: 0xC27400), dark: RGB(hex: 0xF0A43A))
    public static let error = (light: RGB(hex: 0xD93A2B), dark: RGB(hex: 0xFF6B5C))
    public static let notice = (light: RGB(hex: 0x6B7A7E), dark: RGB(hex: 0x7F9297))
}

/// WCAG 2.x 相对亮度对比度，(L1 + 0.05) / (L2 + 0.05)。
public enum ContrastRatio {
    public static func between(_ a: RGB, _ b: RGB) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func relativeLuminance(_ c: RGB) -> Double {
        func channel(_ v: UInt8) -> Double {
            let s = Double(v) / 255.0
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }
}

extension ThemePalette {
    /// 深色外观下系统绘制选中控件（分段控件、`.borderedProminent`）的底色。
    /// 这类控件文字固定为白色：一般主题用 accentStrong；石墨的 accentStrong
    /// 在深色窗口上几乎看不见，改用提亮一档的石墨灰。白字对比度由 ThemeTests 守住。
    public var controlFillDark: RGB {
        id == .graphite ? RGB(hex: 0x52636B) : accentStrong
    }
}
