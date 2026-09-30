## Context

MiVibe's visuals come from three unrelated sources: a stock SF Symbols mic icon on a blue→indigo gradient, the macOS system accent (blue) inside every window, and six hard-coded RGB values for the float bar. The README hero is a Xiaomi product photo. The approved design (`.scratch/mivibe/design/design-system-v3.html`, commit 979cc26) unifies all of it under one brand: a "waveform + text caret" mark, a theme color that marks in-progress voice states, fixed semantic colors for outcomes, and user-selectable themes. This epic lands that design before the next public release, so the first DMG users download already looks like one product.

## Decisions (locked 2026-09-30)

| Topic | Decision |
|---|---|
| Default theme | 潮汐青 (tide) — used for app icon, README, GitHub assets |
| Selectable themes | All six: 潮汐青 / 靛蓝 / 珊瑚 / 兰紫 / 玫瑰 / 石墨 |
| Appearance | 跟随系统 / 浅色 / 深色, applies to **settings window, menu popover and float bar together** (`NSApp.appearance`) |
| Sidebar selection | Custom-drawn rows (native `List(.sidebar)` selection can't take a runtime color; `actool` is unavailable on this machine, so `NSAccentColorName` is not an option) |
| DMG background | Not doing it |
| Color rule | Theme color = listening / transcribing / polishing + selection, toggles, primary buttons, row icons. Semantic colors (success / attention / error / notice) are fixed across themes |
| Motion | Signature bars→arc (420 ms); listening ball becomes the three-bar mark; menu bar animates while listening; attention shakes once + beats 3×; see `motion-v1.html` |
| Text on filled accent | Must reach ≥ 4.5:1. Light mode fills use the theme's `accentStrong` with white text; dark mode fills use the dark accent with ink text `#13201F` (white on dark accents measures 1.37–2.85:1, so the v3 mockups' white-on-dark-accent is corrected here) |

## Child Issues

- [ ] #2 A · theme model
- [ ] #3 B · icons
- [ ] #4 C · float + popover
- [ ] #5 D · settings window
- [ ] #6 E · README / social
- [ ] #7 F · motion


| # | Title | Priority | Effort (human / CC) | Dependencies |
|---|---|---|---|---|
| #2 (A) | Theme model, palette tokens and persisted appearance/theme | Critical | 1d / 40m | — |
| #3 (B) | App icon and menu bar template icons | High | 1d / 40m | A (palette values) |
| #4 (C) | Float bar, mode picker and menu popover on theme tokens | High | 1d / 40m | A |
| #5 (D) | Settings window: theme tint, custom sidebar, 外观 pane, 关于 redesign | High | 2d / 1.5h | A |
| #6 (E) | README hero, badges and GitHub social preview | Medium | 0.5d / 30m | B (icon drawing code) |
| #7 (F) | Motion system: tokens, signature transition, float/picker/menu bar/settings choreography, Reduce Motion | High | 2.5d / 2h | A, B, C, D |

## Dependency Graph

```
#2 A ──> #3 B ──> #6 E
#2 A ──> #4 C
#2 A ──> #5 D
#3 B, #4 C, #5 D ──> #7 F
```

## Sequencing Rationale

A defines the only source of color; B/C/D all read from it, and landing them first would mean hard-coding again. B precedes E because E renders the README hero and social card from the same icon drawing code. C and D are independent of each other and of B. F goes last: it animates the shapes and colors that B, C and D put in place, and doing motion first would mean re-tuning it after every visual change.

## Definition of Done

1. `grep -rnE "accentColor|Color\(red:|\.(orange|green|red|yellow)\b" Sources/MiVibe` returns only the remote illustration's aluminium grays and the brand palette file (today: 16 accentColor + 18 named-color + 6 RGB hits).
2. Switching theme in 外观 recolors the settings window, popover and float bar without relaunch; switching appearance flips all three together.
3. Each scene in the v3 design has a matching real screenshot (settings panes via `MIVIBE_OPEN_SETTINGS`, float via `MIVIBE_FLOAT_DEMO`) in light and dark, for 潮汐青 and 石墨, attached to the child issues.
4. An existing `config.json` without the new fields loads unchanged (API keys, key map, rewrite settings intact).
5. Motion matches `motion-v1.html`: signature within 420 ms ± 1 frame, no continuous redraw in static states, all six states distinct under Reduce Motion.
6. `swift run MiVibeTests` passes; `Scripts/build-app.sh release` and `Scripts/make-dmg.sh` succeed.

## Out of Scope

- DMG window background / Finder layout.
- macOS 26 dark / tinted app icon variants (need Icon Composer + `actool`, unavailable).
- Renaming the app or changing "Mi" in the name.
- Notarization / Developer ID signing.
- Any change to recording, queue, ASR, rewrite or key-routing behavior.

## Related

- Design reference: `.scratch/mivibe/design/design-system-v3.html` (979cc26)
- Motion reference: `.scratch/mivibe/design/motion-v1.html`
