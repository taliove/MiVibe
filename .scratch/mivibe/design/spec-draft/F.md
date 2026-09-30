Parent: #1 · Depends on: #2, #3, #4, #5

## Context

Motion is how MiVibe tells you where your voice is without you looking at the screen. Today it is ad hoc: durations like 0.18 / 0.35 are scattered, only the listening ball is level-driven, the panel appears and disappears with no transition (`orderFrontRegardless` / `orderOut`), and with Reduce Motion on all six states collapse into the same 15pt dot. The approved motion design (`.scratch/mivibe/design/motion-v1.html`) defines tokens, one brand signature transition, and the choreography for every surface. Parent: epic. Depends on A (tokens), B (menu bar frames), C (float colors) and D (custom sidebar).

## Decisions (locked 2026-09-30)

| Topic | Decision |
|---|---|
| Signature | On AUDIO_STOP the three bars converge to a point, then the transcribing arc draws out of it; 420 ms total |
| Listening ball | Replace "core circle + 12 radial ticks" with the brand mark's three bars, level-driven |
| Menu bar | Animates while listening (discrete level frames, ≤ 6 fps) |
| Attention | One horizontal shake (±4 pt, 400 ms) plus three heartbeats, then still |
| Reduce Motion | Every state keeps a recognizable static glyph; only opacity/color change |

## Current State (verified 2026-09-30)

- `Sources/MiVibe/UI/DesignSystem.swift:33-37` — `Motion.select` 0.15, `quickFade` 0.1, `toastFade` 0.4.
- `Sources/MiVibe/UI/FloatPanel.swift:140-148` — `showPanel()` resizes the `NSPanel` and calls `orderFrontRegardless()`; hide is `panel.orderOut(nil)` from a timer (`:156-163`). No entrance or exit animation.
- `FloatPanel.swift:207` — bar content animates `.easeOut(duration: 0.18)` on state change.
- `FloatPanel.swift:325-331` — Reduce Motion renders one 15pt dot for every state.
- `FloatPanel.swift:333` — `TimelineView(.animation)` wraps the ball for **all** states, so inserted/notice redraw every display frame while visible.
- `ListeningBall` (`:355-395`) — core 8–20 pt, glow, 12 radial capsules; `TranscribingBall` 1.2 s rotation; `InsertedBall` 0.35 s check draw; `AttentionBall` double-beat decaying over 22 s.
- Auto-hide: inserted/notice 2.0 s, attention 30 s (`:117-125`).
- Audio level: `AudioLevelMeter` (`Sources/MiVibeCore/Audio/AudioLevel.swift`) floor −50 dB, attack 0.07 s.

## Proposed Change

### Implementation Details

**1. Tokens — replace `Motion` in `DesignSystem.swift`:**

```swift
enum Motion {
    static let instant  = Animation.easeOut(duration: 0.10)                      // press, hover, key flash
    static let quick    = Animation.easeOut(duration: 0.18)                      // color, border, text fade
    static let standard = Animation.spring(response: 0.32, dampingFraction: 0.86) // appear, width, highlight/pill slide
    static let exit     = Animation.easeIn(duration: 0.24)                       // hide, picker close
    static let draw     = Animation.easeOut(duration: 0.35)                      // check, arc draw
    static let theme    = Animation.easeInOut(duration: 0.25)                    // theme recolor
    static let signatureDuration: Double = 0.42
    static let spinPeriod: Double = 1.2
    static let quietBreathHz: Double = 0.5
    static let menuBarMaxFPS: Double = 6
}
```
Pure timing constants that tests need (`signatureDuration`, auto-hide delays, fps) also live in `Sources/MiVibeCore/Core/MotionTiming.swift` so MiVibeTests can assert them; `Motion` reads from there. Update the three existing call sites (`RemoteControlView.swift:117-118`, `SettingsKeyMappingSelected.swift:64`) to `Motion.instant` / `Motion.standard`.

**2. Float panel entrance / exit (FloatPanel.swift):**
- Keep the `NSPanel` at a fixed size while visible (compute max of bar and picker heights for the current picker item count); animate only SwiftUI content. No `setContentSize` during an animation.
- Show: content from `offset(y: 10)`, `scale 0.96`, `opacity 0` → identity with `Motion.standard`.
- Hide: → `offset(y: 6)`, `scale 0.98`, `opacity 0` with `Motion.exit`; call `orderOut` in the animation completion (`withAnimation(_:completionCriteria:_:completion:)`, macOS 14). A new state arriving mid-exit cancels the pending `orderOut` and animates back from the current value.
- Auto-hide delays: inserted **1.6 s** after the check finishes drawing (was 2.0 s from state start; net visible time ≈ 1.95 s, unchanged feel), notice 2.0 s, attention 30 s.

**3. Ball redesign and states:**
- `ListeningBall`: accent-filled 34 pt circle, three white rounded bars in the brand-mark ratio (heights base 0.55 / 1.0 / 0.7). Each bar's scaleY = clamp(0.22…1, (0.25 + 0.75·level·wobble_i)·base_i + 0.1), `wobble_i = 0.78 + 0.22·sin(9t + 2.1i)`. When level ≤ 0.08 use the existing 0.5 Hz quiet breath. Drive with `TimelineView(.animation)` **only in this state**.
- Signature (listening → transcribing), `PhaseAnimator`/keyframes over 420 ms from AUDIO_STOP: 0–200 ms bars translate to center and scaleY → 0.16; 140–260 ms bars fade out; 0–180 ms ball fill accent → accent 18%; 180–420 ms arc trims 0 → 0.28; from 180 ms arc rotates at 1.2 s/turn. Text swaps with 4 pt up-fade / down-fade (`quick`), width springs (`standard`).
- `TranscribingBall`: unchanged shape (arc on 18% accent), `TimelineView` only in this state.
- Polishing: fill animates to full accent (`quick`), arc turns white and keeps spinning, a four-point star scales in and twinkles (scale 1 ↔ 0.78, 1.6 s).
- Inserted: arc trims to full circle (200 ms), fill → success, white check draws (`draw`). No `TimelineView`.
- Notice: soft notice ball, info glyph springs in (scale 0.4 → 1). No `TimelineView`.
- Attention: soft attention ball + exclamation; bar shakes once (keyframes 0 → −4 → 4 → −3 → 2 → 0 pt over 400 ms, starting 220 ms after the state change); ball heartbeats three times (1.4 s period) then rests. `TimelineView` only for the first 5 s.

**4. Mode picker:** open = bar morphs into the picker (height `standard`, corner radius 22 → 16), items fade/rise in with 20 ms stagger starting at 60 ms. Highlight is one shape moved with `matchedGeometryEffect` (`standard`). Confirm = row brightness flash (`instant`, 160 ms), picker collapses back into the bar and shows the existing "已切换：…" notice. Back / 6 s idle = picker exits (`exit`).

**5. Menu bar (MiVibeApp.swift, uses B's frames):** while any item is `.listening`, pick frame by level tier (< 0.30 → 0.45, < 0.65 → 0.75, else 1.0), update at most every 166 ms. Stop on leaving listening and show the static mark. Pending dot pops in (`quick` scale 0 → 1).

**6. Menu popover:** pending rows insert with `.transition(.move(edge: .top).combined(with: .opacity))` and remove with `.opacity.combined(with: .scale(0.98))` under `standard`.

**7. Settings window:** sidebar selection pill uses `matchedGeometryEffect` (`standard`); detail content cross-fades (`quick`) on pane change, no slide; theme change wraps the `ThemeStore` update in `withAnimation(Motion.theme)`; appearance change is left to the system (instant); ShortcutRecorder while recording shows a 4 pt accent ring breathing at 1 Hz; model download completion swaps the progress bar for a check (`quick`).

**8. Reduce Motion (`accessibilityReduceMotion`), per state:**

| Motion | Reduced equivalent |
|---|---|
| Float show / hide | Opacity only |
| Listening | Bars fixed at mid height; group opacity 0.7–1.0 follows level |
| Signature | Cross-fade bars → arc |
| Transcribing / polishing | Static arc / static star |
| Inserted | Check appears fully drawn |
| Attention | No shake, no beat |
| Picker highlight, sidebar pill | Jump, no slide |
| Menu bar | Static full mark |

Delete the current single-dot fallback.

## Acceptance Criteria

1. `grep -rnE "duration: *0\.[0-9]+|\.spring\(" Sources/MiVibe/UI` finds matches only inside `DesignSystem.swift`.
2. Float visible in inserted or notice state: Instruments' SwiftUI instrument / `Self._printChanges()` in DEBUG shows the ball body is not re-evaluated after its one-shot animation completes (no continuous redraw).
3. Float hidden: 0 SwiftUI view updates per second from `FloatBarView` (DEBUG counter logged at `.debug` level).
4. Listening on an M-series Mac: MiVibe CPU ≤ 3% averaged over 10 s (Activity Monitor, release build).
5. AUDIO_STOP → arc spinning within 420 ms ± 1 frame at 60 Hz (screen recording at 60 fps, frame count).
6. A new state arriving during hide never produces a blank frame or a double panel (repeat 20 rapid tap-release cycles under `MIVIBE_FLOAT_DEMO_INTERVAL=0.3`).
7. With Reduce Motion on, each of the six states is visually distinct in a screenshot (six-up comparison) and nothing translates or scales.
8. Menu bar icon changes at most 6 times per second while listening (log timestamps in DEBUG) and returns to the static mark within 1 frame after AUDIO_STOP.
9. Picker highlight slides between rows (no jump) with Reduce Motion off; jumps with it on.
10. `swift run MiVibeTests` passes.

## Testing Plan

| Layer | What | Count |
|---|---|---|
| Unit | `MotionTiming` values (signature 0.42, spin 1.2, fps 6, hide delays 1.6/2.0/30) | +1 |
| Unit | Menu bar tier mapping for levels 0, 0.29, 0.30, 0.64, 0.65, 1.0 and fps throttle | +2 |
| Unit | Bar scale function clamps to 0.22…1 for level −1…2 | +1 |
| Manual | 60 fps screen recording of the signature at 1× and via `MIVIBE_FLOAT_DEMO` | 1 |
| Manual | Reduce Motion six-up screenshots, light + dark | 2 |
| Manual | CPU measurement while listening; rapid-cycle stress (AC 6) | 2 |

Menu bar tier and bar-scale math live as pure functions in `MotionTiming.swift` so they are unit-testable.

## Rollback Plan

Revert the PR. Colors from A–D are unaffected; the old ball implementations come back.

## Effort Estimate

Tokens + call-site sweep 1h · panel entrance/exit with fixed-size panel 3h · ball redesign + signature 4h · attention/inserted/notice 2h · picker morph + highlight 2h · menu bar driving 1.5h · popover + settings motion 2h · Reduce Motion equivalents 1.5h · verification 2h.

## Files Reference

| File | Change |
|---|---|
| `Sources/MiVibe/UI/DesignSystem.swift:33-37` | New `Motion` tokens |
| `Sources/MiVibeCore/Core/MotionTiming.swift` | New pure timing + tier/scale functions |
| `Sources/MiVibe/UI/FloatPanel.swift:100-163` | Fixed-size panel, animated show/hide, hide delays |
| `Sources/MiVibe/UI/FloatPanel.swift:170-511` | Ball redesign, signature, picker morph, Reduce Motion |
| `Sources/MiVibe/UI/MiVibeApp.swift` | Menu bar frame driving, dot pop |
| `Sources/MiVibe/UI/MenuPopover.swift` | Pending row transitions |
| `Sources/MiVibe/UI/SettingsSidebar.swift` | Pill `matchedGeometryEffect` |
| `Sources/MiVibe/UI/SettingsView.swift`, `ShortcutRecorder.swift`, `SettingsRecognition.swift` | Cross-fade, recorder ring, download check |
| `Sources/MiVibe/UI/RemoteControlView.swift:117-118`, `SettingsKeyMappingSelected.swift:64` | Token rename |
| `Tests/MiVibeTests/MotionTimingTests.swift`, `main.swift` | New suite |

## Out of Scope

Haptics, sound effects, onboarding animations, changes to recording or queue timing other than the inserted auto-hide delay.

## Related

- Motion reference: `.scratch/mivibe/design/motion-v1.html`
