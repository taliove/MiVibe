Parent: #1 · Depends on: #3

## Context

The README hero is `docs/images/mi-remote.png`, a Xiaomi product photo: third-party industrial design, inconsistent with the app's own visuals. Badges use three unrelated colors. GitHub has no social preview. Replace all with brand assets generated from the same drawing code as the icon. Parent: epic. Depends on B.

## Current State (verified 2026-09-30)

- `README.md:2` and `README.en.md:2` — `<img src="docs/images/mi-remote.png" height="200">`.
- Badges: `18181B` (macOS), `F05138` (Swift), `417D65` (ASR).
- Repo description and topics set; no social preview image.

## Proposed Change

### Implementation Details

- **`Scripts/make-brand-images.swift` (new):** renders with AppKit, carrying a verbatim copy of `BrandMark.bars` (B) and the tide palette; extend the drift test from B to also scan this script:
  - `docs/images/hero-light.png` and `hero-dark.png`, 1240×400 @2x: icon 200pt at left, six fading accent bars, a rounded "text field" containing "按住说话，松手成文。" with an accent caret. Light: field white on transparent; dark: field `#1B2528`, text `#E4EDEE`.
  - `docs/images/social-preview.png`, 1280×640: ink `#0E1A1F` background, faint accent bars right, icon, "MiVibe", "按住说话，松手成文。" (second clause in `22B8C6`), "Voice input for macOS with a Bluetooth voice remote".
  - Text uses system fonts (SF Pro / PingFang SC), baked into the PNG, so GitHub needs no fonts.
- **READMEs:** replace the `<img>` with
  ```html
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/hero-dark.png">
    <img src="docs/images/hero-light.png" width="620" alt="MiVibe：按住说话，松手成文">
  </picture>
  ```
  (English alt: "MiVibe: hold to talk, release to write"). Add the line "适用于小米蓝牙语音遥控器（VID 0x2717 / PID 0x32B8）" / English equivalent under the tagline.
- **Badges:** label color `2B3A3F`, value color `0C98A8`; add a release badge `https://img.shields.io/github/v/release/taliove/mi-vibe?style=flat-square&color=0C98A8&labelColor=2B3A3F`.
- Delete `docs/images/mi-remote.png` (no remaining references).
- Social preview upload is manual (GitHub web settings only): deliver the file path in the PR description.

## Acceptance Criteria

1. `grep -rn "mi-remote" .` (excluding `.scratch`) returns 0 lines and the file is deleted.
2. Both READMEs render the light hero on github.com in light mode and the dark hero in dark mode (checked in a browser, both themes).
3. `swift Scripts/make-brand-images.swift` regenerates the three PNGs byte-identically on a second run.
4. Social preview PNG is exactly 1280×640 and under 1 MB.
5. README.md and README.en.md stay content-aligned (AGENTS.md rule).

## Testing Plan

| Layer | What | Count |
|---|---|---|
| Manual | Render check on github.com, light + dark | 2 |
| Manual | `sips -g pixelWidth -g pixelHeight` on outputs | 3 |

## Rollback Plan

Revert the PR (restores mi-remote.png and old README header).

## Effort Estimate

Image script 2h · README edits 0.5h · verification 0.5h.

## Files Reference

| File | Change |
|---|---|
| `Scripts/make-brand-images.swift` | New |
| `docs/images/hero-light.png`, `hero-dark.png`, `social-preview.png` | New |
| `docs/images/mi-remote.png` | Delete |
| `README.md:1-12`, `README.en.md:1-12` | Hero, badges, compatibility line |

## Out of Scope

README body copy, release notes template, DMG visuals.
