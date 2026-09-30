Parent: #1 · Depends on: #2

## Context

The float bar and menu popover are what users see every time they speak. Today the three in-progress states are blue / violet / purple (hues ~20° apart) and outcome colors are system literals. Move both surfaces onto the theme tokens from A. Parent: epic. Depends on A.

## Current State (verified 2026-09-30)

- `Sources/MiVibe/UI/FloatPanel.swift:206` — `.floatSurface(tint: state.color)`; balls at `:328-346` take `state.color`; mode picker highlight `:296` uses `Color.accentColor`.
- `FloatPanel.swift:86` — DEBUG `debugForceAppearance` sets `panel.appearance` directly.
- `Sources/MiVibe/UI/MenuPopover.swift` — header `Image(systemName: coordinator.link.icon)` in `link.color` (`:43-44`); pairing guide and permission notice use `.orange` labels (`:130`, `:147`); pending dots use `FloatState` colors; width 340.

## Proposed Change

### Implementation Details

**Float bar (FloatPanel.swift):**
- listening / transcribing / polishing tint and ball = `accent` (dynamic). Ball shapes and motion stay exactly as implemented; this issue changes color only. New ball shapes and all motion work belong to F.
- inserted = `success` filled ball, white check (unchanged shape).
- notice / attention = soft ball (`color` at 20% fill) with glyph in `color`, matching v3.
- Mode picker: highlighted row fill = `accentFill`, text + icon = `onAccentFill`.
- Remove `debugForceAppearance`; the demo uses `ThemeStore.set(appearance:, persist: false)` from A.
- Border opacity (55%) and surface material unchanged.

**Menu popover (MenuPopover.swift):**
- Header: 28×28 rounded tile (radius 8) — connected: `accentSoft` background + accent mark; offline/unpaired: `attention` 16% + 45%-alpha mark. Title = link text (`.headline`), subtitle (`.caption`, secondary): connected "小米蓝牙语音遥控器 · 接管生效中" / "… · 按键由系统处理" depending on `keys.isExclusive`; offline "遥控器未连接"; unpaired "按说明书让遥控器进入配对状态".
- Pending dots: listening/transcribing → accent; ready → success; any needsAttention → attention.
- Pairing guide + permission notice: label icon/text in `attention`; primary action ("打开蓝牙设置…") uses `.borderedProminent` tinted `accentFill`.
- "输入到这里" becomes `.borderedProminent` (accentFill); "重试" stays bordered.
- Apply `.tint(accent)` at the popover root.

## Acceptance Criteria

1. With `MIVIBE_FLOAT_DEMO=1`, all six float states render with: in-progress = current theme accent, inserted = success, notice/attention = semantic colors; verified for tide and graphite in light and dark (8 screenshots).
2. Mode picker highlight text contrast ≥ 4.5:1 in both appearances for all six themes (guaranteed by A's tokens; spot-check graphite dark).
3. Switching theme while the float bar is visible recolors it within one state change, no relaunch.
4. Popover shows the three header variants (connected / offline / unpaired) with the new tile; pending item "输入到这里" is a filled accent button.
5. No `accentColor`, `.orange`, `.green`, `.red` literals remain in `FloatPanel.swift` or `MenuPopover.swift` (the red pending dot in `MiVibeApp.swift` switches to `error`).

## Testing Plan

| Layer | What | Count |
|---|---|---|
| Unit | `FloatState`→token mapping (from A) covers all 6 states | +1 |
| Manual | Float demo screenshots, 2 themes × 2 appearances | 4 sets |
| Manual | Popover in connected / offline / unpaired, plus one pending item | 4 |

## Rollback Plan

Revert the PR; A's tokens stay, surfaces go back to literals.

## Effort Estimate

Float tokens + ball tweaks 2h · picker 0.5h · popover header/buttons 2h · screenshots 1.5h.

## Files Reference

| File | Change |
|---|---|
| `Sources/MiVibe/UI/FloatPanel.swift:86,206,296,328-346` | Tokens, remove debug appearance |
| `Sources/MiVibe/UI/MenuPopover.swift:40-215` | Header tile, dots, buttons, guides |
| `Sources/MiVibe/UI/MiVibeApp.swift` | Pending dot → `error`, demo appearance via ThemeStore |

## Out of Scope

Float layout, queue behavior, and every motion change (ball redesign, show/hide, signature transition, picker highlight slide) — see F.
