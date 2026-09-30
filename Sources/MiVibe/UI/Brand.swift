import AppKit
import Combine
import MiVibeCore
import SwiftUI

/// 品牌主题的运行时桥接（epic #1 子任务 A）。
///
/// 颜色取用约定（给后续 B–E 子任务的界面代码）：
/// - 视图里直接写 `Color.brandAccent` / `.brandAccentFill` / `.brandOnAccentFill` 等
///   静态扩展，无需注入任何环境对象；它们内部读 `BrandColorCurrent` 里的当前主题，
///   并按 resolve 时的外观在浅色 / 深色值之间切换（NSColor dynamicProvider）。
/// - 需要随主题切换**立刻重绘**的视图，观察 `ThemeStore`（@ObservedObject /
///   environmentObject）即可；不观察的视图拿到的颜色值本身总是对的，只是不会
///   因主题切换自动失效重算。
/// - 选「共享当前主题持有器 + Color 静态扩展」而不是 EnvironmentKey：浮条由
///   AppKit 承载（NSPanel），不走 SwiftUI 环境链；静态扩展对 SwiftUI 与
///   AppKit（经 `NSColor.brand*`）两侧都可用。

/// 当前主题的进程级持有器。`ThemeStore` 是唯一写入方；颜色扩展只读。
@MainActor
enum BrandColorCurrent {
    private(set) static var palette = ThemePalette.palette(.tide)

    static func update(_ palette: ThemePalette) {
        self.palette = palette
    }
}

/// 主题与外观的统一入口，由 AppDelegate 在启动时创建（早于浮条）。
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var theme: ThemeID
    @Published private(set) var appearance: AppearanceMode

    init() {
        let config = Config.load()
        var theme = config.effectiveTheme
        var appearance = config.effectiveAppearance
        #if DEBUG
        // 开发走查：MIVIBE_THEME=<ThemeID> / MIVIBE_APPEARANCE=<system|light|dark>
        // 只覆盖本次运行，不写配置（截图对照设计稿用）。
        let env = ProcessInfo.processInfo.environment
        if let raw = env["MIVIBE_THEME"], let id = ThemeID(rawValue: raw) { theme = id }
        if let raw = env["MIVIBE_APPEARANCE"], let mode = AppearanceMode(rawValue: raw) { appearance = mode }
        #endif
        self.theme = theme
        self.appearance = appearance
        BrandColorCurrent.update(ThemePalette.palette(theme))
        Self.applyToApp(appearance)
    }

    /// 当前主题色板。
    var palette: ThemePalette { ThemePalette.palette(theme) }

    func set(theme: ThemeID) {
        guard theme != self.theme else { return }
        self.theme = theme
        BrandColorCurrent.update(ThemePalette.palette(theme))
        persist { $0.theme = theme.rawValue }
    }

    /// persist=false 用于调试走查（MIVIBE_FLOAT_DEMO=dark|light）：只影响本次运行。
    func set(appearance: AppearanceMode, persist: Bool = true) {
        guard appearance != self.appearance else { return }
        self.appearance = appearance
        Self.applyToApp(appearance)
        if persist {
            self.persist { $0.appearance = appearance.rawValue }
        }
    }

    /// 外观对设置窗口、菜单弹层和浮条一起生效（epic 决定），所以设在 App 级。
    private static func applyToApp(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// 与 SettingsView.saveKey() 同一模式：读—改—写整份配置，不丢其他字段。
    private func persist(_ mutate: (inout Config.Data) -> Void) {
        do {
            var config = Config.load()
            mutate(&config)
            try Config.save(config)
        } catch {
            // 失败不吞：记入诊断日志（配置目录权限问题等），界面保持本次选择。
            Log.settings.error("theme config save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - 动态颜色

extension NSColor {
    /// 按 resolve 时的外观在浅色 / 深色之间取值。
    static func dynamic(light: RGB, dark: RGB) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        }
    }

    convenience init(_ rgb: RGB) {
        self.init(
            calibratedRed: CGFloat(rgb.r) / 255,
            green: CGFloat(rgb.g) / 255,
            blue: CGFloat(rgb.b) / 255,
            alpha: 1
        )
    }

    /// 主题色：浅色取 accent，深色取 accentDark。
    @MainActor static var brandAccent: NSColor {
        let p = BrandColorCurrent.palette
        return .dynamic(light: p.accent, dark: p.accentDark)
    }

    /// 填充面：浅色 accentStrong（配白字），深色 accentDark（配墨绿字）。
    @MainActor static var brandAccentFill: NSColor {
        let p = BrandColorCurrent.palette
        return .dynamic(light: p.accentStrong, dark: p.accentDark)
    }

    /// 填充面上的文字：浅色白，深色墨绿。
    @MainActor static var brandOnAccentFill: NSColor {
        let p = BrandColorCurrent.palette
        return .dynamic(light: RGB(hex: 0xFFFFFF), dark: p.onAccentDark)
    }

    /// 着色背景：浅色 accentSoft，深色 accentSoftDark。
    @MainActor static var brandAccentSoft: NSColor {
        let p = BrandColorCurrent.palette
        return .dynamic(light: p.accentSoft, dark: p.accentSoftDark)
    }

    @MainActor static var brandSuccess: NSColor {
        .dynamic(light: SemanticPalette.success.light, dark: SemanticPalette.success.dark)
    }

    @MainActor static var brandAttention: NSColor {
        .dynamic(light: SemanticPalette.attention.light, dark: SemanticPalette.attention.dark)
    }

    @MainActor static var brandError: NSColor {
        .dynamic(light: SemanticPalette.error.light, dark: SemanticPalette.error.dark)
    }

    @MainActor static var brandNotice: NSColor {
        .dynamic(light: SemanticPalette.notice.light, dark: SemanticPalette.notice.dark)
    }
}

extension Color {
    /// 主题色：进行中状态（正在听 / 转写 / 改写）、选中、主按钮。
    @MainActor static var brandAccent: Color { Color(nsColor: .brandAccent) }
    /// 填充面（其上文字用 `brandOnAccentFill`）。
    @MainActor static var brandAccentFill: Color { Color(nsColor: .brandAccentFill) }
    /// 填充面上的文字色。
    @MainActor static var brandOnAccentFill: Color { Color(nsColor: .brandOnAccentFill) }
    /// 着色背景（推荐标签、选中行、品牌横幅）。
    @MainActor static var brandAccentSoft: Color { Color(nsColor: .brandAccentSoft) }
    /// 结果语义色：成功（已输入 / 已连接）。
    @MainActor static var brandSuccess: Color { Color(nsColor: .brandSuccess) }
    /// 结果语义色：需要注意（待处理 / 未配对）。
    @MainActor static var brandAttention: Color { Color(nsColor: .brandAttention) }
    /// 结果语义色：错误。
    @MainActor static var brandError: Color { Color(nsColor: .brandError) }
    /// 结果语义色：中性提示（离线、忽略）。
    @MainActor static var brandNotice: Color { Color(nsColor: .brandNotice) }
}
