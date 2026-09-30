import Foundation
import MiVibeCore

/// 主题与外观的验收（spec A，epic #1 子任务 #2）。
///
/// 守的契约：
/// - 六套主题的取值与设计稿 v3 一致，且填充面文字对比度 ≥ 4.5（WCAG AA）。
/// - `Config.Data` 新增 theme/appearance 字段不毁掉老配置（见 Config.swift 头注释：
///   非 Optional 字段会让 load() 返回空配置，连 API Key 一起抹掉）。
/// - 未知字符串一律回落默认主题，而不是让解码失败。
enum ThemeTests {
    static func run() {
        controlFillContrast()
        parsing()
        fallback()
        paletteCompleteness()
        contrastThresholds()
        legacyConfigDecodes()
        unknownThemeFallsBack()
        roundTrip()
    }

    // MARK: - 解析与回落

    static func parsing() {
        Harness.suite("主题与外观：解析") {
            Harness.expectEqual(ThemeID(rawValue: "tide"), .tide, "tide 解析为潮汐青")
            Harness.expectEqual(ThemeID(rawValue: "graphite"), .graphite, "graphite 解析为石墨")
            Harness.expectEqual(AppearanceMode(rawValue: "dark"), .dark, "dark 解析为深色")
            Harness.expectEqual(AppearanceMode(rawValue: "system"), .system, "system 解析为跟随系统")
        }
    }

    static func fallback() {
        Harness.suite("主题与外观：未知值回落") {
            Harness.expectEqual(ThemeID.allCases.count, 6, "共六套主题")
            Harness.expect(ThemeID(rawValue: "purple") == nil, "未知主题字符串解析为 nil")
            Harness.expect(AppearanceMode(rawValue: "auto") == nil, "未知外观字符串解析为 nil")
            Harness.expectEqual(ThemePalette.palette(.tide).id, .tide, "palette 返回对应主题")
        }
    }

    // MARK: - 色板

    static func paletteCompleteness() {
        Harness.suite("色板：六套主题字段完整且取值与 v3 一致") {
            let expected: [ThemeID: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)] = [
                .tide:     (0x0C98A8, 0x08717F, 0xD7F1F2, 0x22B8C6, 0x0F3439, 0x16B4C2, 0x086978),
                .indigo:   (0x4F5BD5, 0x3A44B0, 0xE3E5FB, 0x8591F5, 0x1E2350, 0x6272F0, 0x3B3FB8),
                .coral:    (0xE0503A, 0xB83A27, 0xFBE3DE, 0xFF7A62, 0x43201A, 0xFF7157, 0xC9362A),
                .orchid:   (0x8A4FD6, 0x6C38B3, 0xEEE3FB, 0xB48AF5, 0x2E1D4A, 0xA56BF0, 0x6A33B8),
                .rose:     (0xD2457A, 0xA93360, 0xFADFE9, 0xF27AA6, 0x45192B, 0xEC5F93, 0xB02F63),
                .graphite: (0x2E3A40, 0x2E3A40, 0xE1E6E8, 0xD5DEE1, 0x222C31, 0x46545B, 0x1B2327),
            ]
            for (id, hex) in expected {
                let p = ThemePalette.palette(id)
                Harness.expectEqual(p.accent, RGB(hex: hex.0), "\(id.rawValue) accent")
                Harness.expectEqual(p.accentStrong, RGB(hex: hex.1), "\(id.rawValue) accentStrong")
                Harness.expectEqual(p.accentSoft, RGB(hex: hex.2), "\(id.rawValue) accentSoft")
                Harness.expectEqual(p.accentDark, RGB(hex: hex.3), "\(id.rawValue) accentDark")
                Harness.expectEqual(p.accentSoftDark, RGB(hex: hex.4), "\(id.rawValue) accentSoftDark")
                Harness.expectEqual(p.iconTop, RGB(hex: hex.5), "\(id.rawValue) iconTop")
                Harness.expectEqual(p.iconBottom, RGB(hex: hex.6), "\(id.rawValue) iconBottom")
                Harness.expectEqual(p.onAccentDark, RGB(hex: 0x13201F), "\(id.rawValue) onAccentDark 统一墨绿")
                Harness.expect(!p.displayName.isEmpty, "\(id.rawValue) 有中文名")
            }
            Harness.expectEqual(ThemePalette.palette(.tide).displayName, "潮汐青", "默认主题名为潮汐青")
        }
    }

    static func contrastThresholds() {
        Harness.suite("色板：填充面文字对比度 ≥ 4.5（WCAG AA）") {
            let white = RGB(hex: 0xFFFFFF)
            for id in ThemeID.allCases {
                let p = ThemePalette.palette(id)
                let lightRatio = ContrastRatio.between(p.accentStrong, white)
                Harness.expect(lightRatio >= 4.5,
                    "\(id.rawValue) 浅色填充 accentStrong/白 = \(String(format: "%.2f", lightRatio)):1")
                let darkRatio = ContrastRatio.between(p.accentDark, p.onAccentDark)
                Harness.expect(darkRatio >= 4.5,
                    "\(id.rawValue) 深色填充 accentDark/墨绿 = \(String(format: "%.2f", darkRatio)):1")
            }
            // 算法基准：黑/白 = 21:1，同色 = 1:1。
            Harness.expectEqual(ContrastRatio.between(RGB(hex: 0x000000), white), 21.0, "黑白对比为 21:1")
            Harness.expectEqual(ContrastRatio.between(white, white), 1.0, "同色对比为 1:1")
        }
    }

    // MARK: - 配置兼容

    /// 老配置文件：没有 theme/appearance 键，其余字段（API Key、按键映射等）必须原样存活。
    static func legacyConfigDecodes() {
        Harness.suite("配置兼容：老文件解码不丢字段") {
            let legacy = #"{"doubaoAPIKey":"sk-abcdef","enableNonstream":true,"asrProvider":"doubao"}"#
            guard let data = legacy.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(Config.Data.self, from: data)
            else {
                Harness.expect(false, "没有新字段的老配置应该能解码")
                return
            }
            Harness.expectEqual(decoded.doubaoAPIKey, "sk-abcdef", "API Key 必须存活")
            Harness.expect(decoded.enableNonstream, "既有布尔字段保留")
            Harness.expect(decoded.theme == nil, "缺失的 theme 解码为 nil")
            Harness.expect(decoded.appearance == nil, "缺失的 appearance 解码为 nil")
            Harness.expectEqual(decoded.effectiveTheme, .tide, "无 theme 时回落潮汐青")
            Harness.expectEqual(decoded.effectiveAppearance, .system, "无 appearance 时回落跟随系统")
        }
    }

    static func unknownThemeFallsBack() {
        Harness.suite("配置兼容：未知字符串回落默认") {
            // "purple" 是早期设计稿里的名字，后来改叫 orchid——老文件里可能还躺着它。
            let json = #"{"enableNonstream":true,"theme":"purple","appearance":"auto"}"#
            guard let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(Config.Data.self, from: data)
            else {
                Harness.expect(false, "未知主题/外观字符串不应导致解码失败")
                return
            }
            Harness.expectEqual(decoded.effectiveTheme, .tide, "未知主题回落潮汐青")
            Harness.expectEqual(decoded.effectiveAppearance, .system, "未知外观回落跟随系统")
            Harness.expectEqual(decoded.theme, "purple", "原值保留，下次保存不写丢")
        }
    }

    static func roundTrip() {
        Harness.suite("配置兼容：主题选择往返保存") {
            var cfg = Config.Data()
            cfg.theme = ThemeID.rose.rawValue
            cfg.appearance = AppearanceMode.dark.rawValue
            cfg.doubaoAPIKey = "sk-roundtrip"
            guard let encoded = try? JSONEncoder().encode(cfg),
                  let decoded = try? JSONDecoder().decode(Config.Data.self, from: encoded)
            else {
                Harness.expect(false, "编码后应能解码回来")
                return
            }
            Harness.expectEqual(decoded.effectiveTheme, .rose, "主题选择往返保留")
            Harness.expectEqual(decoded.effectiveAppearance, .dark, "外观选择往返保留")
            Harness.expectEqual(decoded.doubaoAPIKey, "sk-roundtrip", "其他字段往返保留")
        }
    }

    /// 系统绘制的选中控件（白字）在两种外观下都要读得清。
    static func controlFillContrast() {
        Harness.suite("系统选中控件底色配白字 ≥ 4.5") {
            let white = RGB(hex: 0xFFFFFF)
            for id in ThemeID.allCases {
                let p = ThemePalette.palette(id)
                Harness.expect(ContrastRatio.between(p.accentStrong, white) >= 4.5, "\(id) 浅色控件底配白字")
                Harness.expect(ContrastRatio.between(p.controlFillDark, white) >= 4.5, "\(id) 深色控件底配白字")
            }
        }
    }
}
