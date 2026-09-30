Parent: #1

## Context

Every color in the app is either the system accent or a literal. Before any screen can be branded, there must be one palette with light/dark values per theme, plus persisted user choices for theme and appearance. Parent: epic.

## Current State (verified 2026-09-30)

- `Sources/MiVibe/UI/AppState.swift:57-66` — six `Color(red:…)` literals for `FloatState`.
- `Sources/MiVibe/UI/AppState.swift:19-25` — `LinkState.color` uses `.orange` / `.secondary` / `.green`.
- `Sources/MiVibeCore/Core/Config.swift:20-60` — `Config.Data`; new fields must be `Optional` (AGENTS.md rule; decode failure returns an empty config and later saves can wipe API keys).
- No theme or appearance concept exists anywhere.

## Proposed Change

### Implementation Details

**1. `Sources/MiVibeCore/Core/Theme.swift` (new, pure, no SwiftUI):**

```swift
public struct RGB: Equatable, Sendable { public let r, g, b: UInt8; public init(hex: UInt32) }
public enum ThemeID: String, CaseIterable, Sendable { case tide, indigo, coral, orchid, rose, graphite }
public enum AppearanceMode: String, CaseIterable, Sendable { case system, light, dark }

public struct ThemePalette: Sendable {
    public let id: ThemeID
    public let displayName: String        // 潮汐青 …
    public let accent: RGB                // light: icons, indicators, borders
    public let accentStrong: RGB          // light: filled surfaces with white text, text links
    public let accentSoft: RGB            // light: tinted backgrounds (推荐, selected row, brand banner)
    public let accentDark: RGB            // dark: icons, indicators, filled surfaces
    public let accentSoftDark: RGB
    public let onAccentDark: RGB          // dark: text on filled accent (#13201F)
    public let iconTop: RGB, iconBottom: RGB  // icon gradient
    public static func palette(_ id: ThemeID) -> ThemePalette
}
public enum SemanticPalette {   // fixed across themes
    public static let success = (light: RGB(hex: 0x1D9A57), dark: RGB(hex: 0x3CC97D))
    public static let attention = (light: RGB(hex: 0xC27400), dark: RGB(hex: 0xF0A43A))
    public static let error = (light: RGB(hex: 0xD93A2B), dark: RGB(hex: 0xFF6B5C))
    public static let notice = (light: RGB(hex: 0x6B7A7E), dark: RGB(hex: 0x7F9297))
}
public enum ContrastRatio { public static func between(_ a: RGB, _ b: RGB) -> Double }  // WCAG 2.x
```

Values (from v3 design):

| Theme | accent | accentStrong | accentSoft | accentDark | accentSoftDark | iconTop / iconBottom |
|---|---|---|---|---|---|---|
| tide | 0C98A8 | 08717F | D7F1F2 | 22B8C6 | 0F3439 | 16B4C2 / 086978 |
| indigo | 4F5BD5 | 3A44B0 | E3E5FB | 8591F5 | 1E2350 | 6272F0 / 3B3FB8 |
| coral | E0503A | B83A27 | FBE3DE | FF7A62 | 43201A | FF7157 / C9362A |
| orchid | 8A4FD6 | 6C38B3 | EEE3FB | B48AF5 | 2E1D4A | A56BF0 / 6A33B8 |
| rose | D2457A | A93360 | FADFE9 | F27AA6 | 45192B | EC5F93 / B02F63 |
| graphite | 2E3A40 | 2E3A40 | E1E6E8 | D5DEE1 | 222C31 | 46545B / 1B2327 |

`onAccentDark` = 13201F for all themes.

**2. `Config.Data` (Sources/MiVibeCore/Core/Config.swift):** add `public var theme: String?` and `public var appearance: String?` (init params default nil). Add `effectiveTheme: ThemeID { ThemeID(rawValue: theme ?? "") ?? .tide }` and `effectiveAppearance: AppearanceMode { … ?? .system }`. Unknown strings fall back to defaults, never fail decode.

**3. `Sources/MiVibe/UI/Brand.swift` (new, SwiftUI/AppKit bridge):**
- `@MainActor final class ThemeStore: ObservableObject` with `@Published theme: ThemeID`, `@Published appearance: AppearanceMode`; loads from `Config.load()`, `set(theme:)` / `set(appearance:)` persist via load-modify-save (same pattern as `SettingsView.saveKey()`).
- On appearance change: `NSApp.appearance = nil / NSAppearance(named: .aqua) / .darkAqua`. This covers settings window, popover and float panel together. Remove the DEBUG `debugForceAppearance` path's conflict by letting `MIVIBE_FLOAT_DEMO=dark|light` call `ThemeStore.set(appearance:)` without persisting.
- Dynamic colors built with `NSColor(name:dynamicProvider:)` choosing light/dark by `appearance.bestMatch(from: [.aqua, .darkAqua])`, exposed as SwiftUI `Color`: `accent`, `accentFill`, `onAccentFill`, `accentSoft`, `success`, `attention`, `error`, `notice`.
  - `accentFill` = light `accentStrong`, dark `accentDark`; `onAccentFill` = light white, dark `onAccentDark`.
- Environment injection: `ThemeStore` owned by `AppDelegate` (same owner as the float panel, per AGENTS.md) and passed to popover, settings and float views.

**4. `AppState.swift`:** `FloatState.color` and `LinkState.color` become functions of the palette (`listening/transcribing/polishing → accent`, `inserted → success`, `notice → notice`, `attention → attention`; `connected → success`, `pairedOffline → notice`, `unpaired → attention`).

## Acceptance Criteria

1. For every `ThemeID`, `ContrastRatio(accentStrong, white) ≥ 4.5` and `ContrastRatio(accentDark, onAccentDark) ≥ 4.5` (measured today: min 5.71 and 5.87).
2. A `config.json` fixture without `theme`/`appearance` decodes with all other fields preserved; `effectiveTheme == .tide`, `effectiveAppearance == .system`.
3. `theme: "purple"` (unknown) decodes and yields `.tide`; round-trip save → load preserves a chosen theme.
4. Changing `ThemeStore.appearance` to `.dark` makes `NSApp.effectiveAppearance` darkAqua; `.system` restores following the OS.
5. `AppState.swift` contains no `Color(red:` and no named colors.
6. `swift run MiVibeTests` passes.

## Testing Plan

| Layer | What | Count |
|---|---|---|
| Unit (MiVibeTests) | `ThemeID`/`AppearanceMode` parsing and fallback | +4 |
| Unit | Palette completeness + contrast thresholds for all 6 themes | +2 |
| Unit | `Config.Data` back-compat decode, unknown values, round-trip | +3 |
| Manual | Toggle appearance in a DEBUG build, confirm popover + float follow | 1 |

Register a new `ThemeTests.run()` in `Tests/MiVibeTests/main.swift`.

## Rollback Plan

Revert the PR. New config keys are optional; older builds ignore them.

## Effort Estimate

Theme.swift + tests 2h · Config fields + tests 1h · Brand.swift/ThemeStore 3h · AppState rewire 1h.

## Files Reference

| File | Change |
|---|---|
| `Sources/MiVibeCore/Core/Theme.swift` | New palette model |
| `Sources/MiVibeCore/Core/Config.swift` | `theme`, `appearance` optional fields + effective getters |
| `Sources/MiVibe/UI/Brand.swift` | New `ThemeStore`, dynamic colors |
| `Sources/MiVibe/UI/AppState.swift:19-66` | Colors from palette |
| `Sources/MiVibe/UI/MiVibeApp.swift` | Own `ThemeStore` on `AppDelegate`, demo appearance path |
| `Tests/MiVibeTests/ThemeTests.swift`, `main.swift` | New suite |

## Out of Scope

Applying tokens to individual screens (children B–E).
