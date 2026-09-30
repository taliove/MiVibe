Parent: #1 · Depends on: #2

## Context

The settings window follows System Settings' layout (850×640, 210 sidebar, grouped cards) but takes all color from the system accent: 16 `accentColor` and 18 named-color call sites across the settings files. The 关于 pane is two rows and empty space. This issue brands the window on theme tokens, adds the 外观 pane where users pick theme and appearance, and redesigns 关于. Layout, spacing (`DesignSystem.swift`) and control placement stay as they are. Parent: epic. Depends on A.

## Current State (verified 2026-09-30)

- `SettingsSidebar.swift` — native `List(selection:)` `.listStyle(.sidebar)`; device card shows `applicationIconImage` + `link.color` dot.
- `SettingsComponents.swift` — `SettingsRow.iconColor` defaults to `.accentColor`; `NoticeBanner` uses `.orange` + orange 12% background.
- `SettingsView.swift:6-27` — `SettingsPane` has 5 cases; ⌘1–⌘5 in `SettingsWindowController.handleShortcut` map by index.
- `RemoteControlView.swift` — selected/flash fill and bound borders use `accentColor`; body uses grayscale aluminium (`Color(white:)`, 7 sites — keep).
- Named colors: `SettingsRecognition` (red failed model), `SettingsRemote` (green/orange/red status icons, orange "未通过"), `SettingsRewrite` (orange "已调整"), `SettingsKeyMappingSelected` (gray inherited), `SettingsPresetSheet` (yellow 18% conflict), `SettingsKeyMappingList` (accent tags).

## Proposed Change

### Implementation Details

**Tint:** apply `.tint(accent)` at the detail root and sidebar root so Toggle, segmented Picker, `.borderedProminent`, ProgressView and radio visuals follow the theme.

**Sidebar (custom-drawn):** replace `List(selection:)` with a `ScrollView { VStack(spacing: 2) }` of `Button` rows:
- Row: 28pt tall, 10pt horizontal padding, radius 7, SF Symbol in `accent` + title 13.5pt.
- Selected: background `accentFill`, icon + text `onAccentFill`. Hover: `accentSoft` at 60%.
- Keyboard: ⌘1–⌘6 (existing handler, now 6 cases); ↑/↓ moves selection when the sidebar has focus; rows expose `.accessibilityAddTraits(.isSelected)`.
- Device card: app icon 36×36, "MiVibe", status capsule: connected = success dot with 3pt halo + success text; offline = notice; unpaired = attention.
- The 外观 row shows a "新" capsule (accentSoft/accent) until the pane is opened once (store `appearancePaneSeen: Bool?` in `Config.Data`).

**Pane order and shortcuts:** 识别 ⌘1 · 改写 ⌘2 · 按键映射 ⌘3 · 遥控器 ⌘4 · 外观 ⌘5 · 关于 ⌘6. Add `case appearance` to `SettingsPane` (icon `paintpalette`, title "外观").

**Token replacements (every call site):**

| Current | New |
|---|---|
| `SettingsRow` default `iconColor: .accentColor` | `accent` |
| status OK icons `.green` | `success` |
| missing / not-active `.orange`, "未通过" | `attention` |
| failed `.red` (model download, self-check, keyword delete) | `error` |
| `NoticeBanner` orange | `attention` icon + `attention` at 14% background; add a `.brand` style (accentSoft bg, accent icon) used by the preset-undo banner |
| "推荐" capsule, "覆盖" tag, selected list row 12% | `accentSoft` / `accent` |
| "已调整" tag `.orange` | `attention` capsule |
| preset conflict `.yellow` 18% | `attention` 16% |
| remote selected/flash/bound `accentColor` | `accent` (selected fill 80%) |
| primary buttons 保存 / 套用 / 添加 | `.borderedProminent` |
| 遥控器 pane when unpaired: "打开蓝牙设置…" | `.borderedProminent` |
| connection row icon (`link.icon`) | brand mark 16pt: connected success, offline notice, unpaired attention |

**外观 pane (`SettingsAppearance.swift`, new):**
- PageHeader: "选择设置窗口、菜单与浮条的外观和主题色。"
- Group "界面外观": three selectable thumbnails 跟随系统 / 浅色 / 深色 (selected = 2pt accent ring + accent label). Footer: "跟随系统时，设置窗口、菜单与浮条随 macOS 外观自动切换。"
- Group "主题色": row `paintpalette` "主题色", subtitle "<名称> · 用于录音、转写、改写状态与选中项", trailing six 20pt swatches (selected ring). Footer: "已输入、需处理、出错的颜色固定，不随主题改变。应用图标始终使用品牌默认色。"
- Group "预览": a static listening float bar on a split light/dark background, using live tokens.
- Changes apply immediately via `ThemeStore` (A).

**关于 pane (redesign):**
- Hero card: 84pt app icon, "MiVibe" wordmark (system rounded, 26pt bold), tagline "按住说话，松手成文。" (second clause in accent), "版本 x.y.z（build）· Apple Silicon" from bundle.
- Three step cards: "01 · 按住 / 按住语音键 / 光标放进任意输入框，按住遥控器上的语音键。", "02 · 说话 / 正常说话 / 浮条显示正在听；想中途放弃，按返回键。", "03 · 松手 / 文字写入 / 松开后自动转写并写入，不会替你按回车。"
- Group: "项目主页" github.com/taliove/mi-vibe [打开…]; "发布说明" https://github.com/taliove/mi-vibe/releases/latest [打开…]. Footer keeps "通用模式不会自动发送消息。终端场景尚未验证，不在兼容承诺内。"

## Acceptance Criteria

1. After this issue, `grep -rnE "accentColor|\.(orange|green|red|yellow)\b" Sources/MiVibe/UI/Settings*.swift Sources/MiVibe/UI/RemoteControlView.swift` returns 0 lines.
2. Sidebar selection color equals `accentFill` for all six themes (not system blue), verified by screenshot with system accent set to blue.
3. ⌘1–⌘6 switch to the six panes in order; ⌘[ / ⌘] history still works.
4. Selecting a theme swatch recolors sidebar, toggles, segmented controls and buttons immediately; selecting 深色 flips the settings window, an open popover and the float bar together.
5. 关于 shows the version from the bundle (not hard-coded) and both links open in the browser.
6. `MIVIBE_OPEN_SETTINGS=<pane>` screenshots of all six panes, light + dark, tide + graphite (24), compared against v3 mockups 3.1–3.11; plus the two sheets (提示词编辑, 套用预设).
7. Old config without `appearancePaneSeen` shows the "新" capsule; opening 外观 once hides it permanently.

## Testing Plan

| Layer | What | Count |
|---|---|---|
| Unit | `SettingsPane.allCases` order + shortcut index mapping | +1 |
| Unit | `appearancePaneSeen` back-compat decode | +1 |
| Manual | 24 pane screenshots + 2 sheets, per AC 6 | 26 |
| Manual | Keyboard-only sidebar navigation, VoiceOver reads selected row | 1 |

## Rollback Plan

Revert the PR. `appearancePaneSeen` is optional and ignored by older builds.

## Effort Estimate

Custom sidebar 3h · token sweep across 9 files 3h · 外观 pane 3h · 关于 redesign 2h · screenshots + fixes 3h.

## Files Reference

| File | Change |
|---|---|
| `Sources/MiVibe/UI/SettingsSidebar.swift` | Custom rows, device card capsule |
| `Sources/MiVibe/UI/SettingsView.swift:6-27, 180-203` | `.appearance` case, 关于 redesign |
| `Sources/MiVibe/UI/SettingsWindowController.swift` | 6 shortcuts, tint at roots |
| `Sources/MiVibe/UI/SettingsComponents.swift` | Row icon token, banner styles |
| `Sources/MiVibe/UI/SettingsAppearance.swift` | New pane |
| `Sources/MiVibe/UI/SettingsRecognition.swift`, `SettingsRewrite.swift`, `SettingsRemote.swift`, `SettingsKeyMapping*.swift`, `SettingsPresetSheet.swift`, `RemoteControlView.swift` | Token sweep |
| `Sources/MiVibeCore/Core/Config.swift` | `appearancePaneSeen: Bool?` |

## Out of Scope

All motion (sidebar selection slide, theme cross-fade, recorder breathing) — see F. D ships the custom sidebar with instant selection.
Settings layout/spacing changes, new settings beyond 外观, remote illustration body colors.
