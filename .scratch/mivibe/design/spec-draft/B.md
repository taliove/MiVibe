Parent: #1 · Depends on: #2

## Context

The app icon is a stock SF Symbols mic, and on macOS 26+ its transparent margins get it wrapped in a gray "icon jail" plate, so it sits visibly smaller than neighbors in the Dock and Finder. The menu bar uses `mic.fill` / `mic.slash` / `mic.badge.plus`. Both should become the brand mark. Parent: epic. Depends on A (palette values).

## Current State (verified 2026-09-30)

- `Scripts/make-icon.swift` draws `NSBezierPath(roundedRect:)` inset 9% with a baked shadow, gradient `0.11,0.35,0.85 → 0.28,0.20,0.72`, white `mic.fill`. Output `Sources/MiVibe/Resources/AppIcon.icns` (committed).
- `Sources/MiVibe/UI/MiVibeApp.swift:18` — `Image(systemName: coordinator.link.icon)` plus a red 5×5 pending dot.
- `LinkState.icon` in `AppState.swift:11-17` is also used by `MenuPopover.swift:43`, `SettingsRemote.swift:15`.

## Proposed Change

### Implementation Details

**Mark geometry (100-unit grid, all rounded rects, fill only):** bars `(17,40,9,20)`, `(31,28,9,44)`, `(45,36,9,28)` with radius 4.5; caret stem `(66,21,8,58)` r4; caret serifs `(59,18,22,7)` and `(59,75,22,7)` r3.5. Source of truth: `Sources/MiVibeCore/Core/BrandMark.swift` (CoreGraphics only, so MiVibeTests can reach it; MiVibeCore must not import SwiftUI) with a `static let bars: [CGRect]` table and `static func path(in rect: CGRect) -> CGPath`. `Scripts/make-icon.swift` runs standalone (`swift Scripts/make-icon.swift`) and cannot import the app target, so it carries a verbatim copy of the table under a comment `// Copy of BrandMark.bars — keep identical`. A unit test in MiVibeTests reads the script file as text and asserts it contains each rect literal from `BrandMark.bars`, so the copies cannot drift silently.

**App icon (`Scripts/make-icon.swift`, rewrite):**
- Shape: Apple squircle taken from a compliant system icon's **full, unthresholded alpha** (render `/System/Applications/Calculator.app` via `NSWorkspace.shared.icon(forFile:)` at 1024, use its alpha as mask). Scale content so the squircle's edge sits at **865 px on the 1024 canvas** (84.5%), centered.
- Fill: vertical gradient `iconTop → iconBottom` of the tide palette (`16B4C2 → 086978`). Mark in white, occupying the central 64% of the squircle.
- Generate the full iconset (16…512@2x) and `iconutil -c icns`. The output `.icns` stays committed; CI never runs the script.

**Menu bar (`MiVibeApp.swift`):** replace `Image(systemName:)` with template `NSImage`s drawn from `BrandMark` at 18×18 pt, `isTemplate = true`:

| State | Image |
|---|---|
| connected | full mark |
| listening (any queue item in `.listening`) | 3 pre-rendered level frames (bar height tiers 0.45 / 0.75 / 1.0 of the base mark). B ships the frames and a static full mark; F drives frame selection from the audio level at ≤ 6 fps |
| pairedOffline | mark at 38% alpha |
| unpaired | mark at 38% alpha + solid 34-unit circle bottom-right with a knocked-out plus |

Keep the existing red pending dot. `LinkState.icon` stays as the SF Symbol fallback name for `SettingsRemote` rows until D replaces it.

## Acceptance Criteria

1. `NSWorkspace.shared.icon(forFile: "/Applications/MiVibe.app")` rendered at 1024 has an alpha bounding box of 87.6% ± 0.5% of the canvas (system apps measure 87.6%), and no gray plate is visible (check the corner pixel at (60,60) is fully transparent).
2. `md5` of `build/MiVibe.app/Contents/Resources/AppIcon.icns` equals the committed `Sources/MiVibe/Resources/AppIcon.icns`.
3. Menu bar shows the four states above (listening shows the static full mark until F lands); the three level frames exist as template images.
4. Menu bar icon renders correctly in both light and dark menu bars (template tinting, no hard-coded color).

## Testing Plan

| Layer | What | Count |
|---|---|---|
| Unit | `BrandMark.path` bounds stay within the 64-unit safe area | +1 |
| Unit | `make-icon.swift` contains every `BrandMark.bars` literal | +1 |
| Manual | Icon footprint measurement script (NSWorkspace render + alpha bbox) | 1 |
| Manual | Screenshot menu bar in light/dark, each state (DEBUG toggle via `MIVIBE_FLOAT_DEMO` cycling also drives the menu bar state) | 4 |

## Rollback Plan

Revert; the previous `AppIcon.icns` comes back with it. If Dock shows a stale icon, `killall Dock`.

## Effort Estimate

Mark + BrandMark.swift 1h · icon script with squircle mask 3h · menu bar images + animation 2h · verification 1h.

## Files Reference

| File | Change |
|---|---|
| `Sources/MiVibeCore/Core/BrandMark.swift` | New shared geometry (Core, CoreGraphics only) |
| `Scripts/make-icon.swift` | Rewrite |
| `Sources/MiVibe/Resources/AppIcon.icns` | Regenerated |
| `Sources/MiVibe/UI/MiVibeApp.swift:12-30` | Template images, listening animation |

## Out of Scope

Dark / tinted icon variants (need `actool`). DMG icon layout.
