# MiVibe

**Turn a Xiaomi Bluetooth voice remote into a Mac-wide voice input and control device.**

Hold the voice key, speak, release — your words are transcribed by Doubao (Volcengine Seed-ASR) and typed straight into whatever text field has focus. The remote's physical keys can be taken over and mapped to per-app keyboard shortcuts, with a built-in preset for coding assistants.

![platform](https://img.shields.io/badge/platform-macOS%2026-blue)
![swift](https://img.shields.io/badge/swift-6.0-orange)
![distribution](https://img.shields.io/badge/distribution-private-lightgrey)

## Features

- **Hold-to-talk voice input** — audio is physically gated by the remote's voice key; release to transcribe and inject at the current focus. No preview, no auto-send.
- **Ordered input queue** — up to 2 recordings in flight; text always lands in spoken order. Failures pause the queue and wait for explicit action, never silently drop.
- **Key takeover & mapping** — seize the remote's HID channel and map any key to any shortcut, globally or per application. Unmapped keys keep their native behavior; the voice key is always reserved for hold-to-talk.
- **Coding assistant preset** — one-tap profile: confirm = send (↩), back = Esc (interrupt), up/down = page up/down.
- **Non-intrusive UI** — menu bar app with a floating status bar (listening / transcribing / inserted / needs attention) that never steals focus.

## Requirements

- macOS 26 (developed and verified on macOS 26.5.2, Apple Silicon)
- Xiaomi Bluetooth Voice Remote (VID `0x2717` / PID `0x32B8`, firmware 2671) — the only model covered by the compatibility promise
- A Doubao speech API key ([console](https://console.volcengine.com/speech/new/setting/apikeys?projectName=default), resource `volc.seedasr.sauc.duration`)

## Install

This machine has no Xcode; the build is pure SwiftPM plus a hand-assembled bundle:

```sh
Scripts/deploy.sh        # build release, sign, install to /Applications, launch
Scripts/build-app.sh     # build + assemble build/MiVibe.app only
```

Signing matters: the scripts sign with the fixed local identity `MiVibe Local Signing`
(`Scripts/setup-signing.sh` creates it once). macOS privacy grants are bound to the
code-signing designated requirement — ad-hoc builds change hash on every recompile and
macOS would treat each build as a brand-new app, re-prompting for every permission.

## Permissions

| Permission | Why |
| --- | --- |
| Accessibility | Write transcribed text into other apps (AX direct write) |
| Event posting | Clipboard-paste fallback (Cmd+V) and synthesized shortcuts |
| Input Monitoring | HID seize for key takeover (requires an app restart after granting) |
| Bluetooth | Receive audio and key events from the remote |

## Usage

1. Pair the remote in System Settings → Bluetooth.
2. Open Settings from the menu bar icon, paste the Doubao API key.
3. Focus any text field, hold the voice key, speak, release.
4. Settings → 按键映射: toggle key takeover, pick a scope (default or per-app), tap a key on the remote diagram and record a shortcut — or apply the coding-assistant preset.

Config lives in `~/.config/mivibe/config.json` (plain JSON, `0600`). Unprocessed
recordings can be kept across restarts as a one-shot lifeline — restored once, then
deleted; no long-term history is kept.

## Development

```sh
swift build                 # all targets
swift run MiVibeTests       # test suite (self-contained harness; no XCTest on CLT-only machines)
swift run MiVibeProbes      # hardware/service diagnostics (HID seize, voice link, injection)
```

Layout: `Sources/MiVibeCore` — pure logic and system integration (ASR codec, ADPCM,
input queue state machine, key routing); `Sources/MiVibe` — SwiftUI/AppKit shell;
`Sources/MiVibeProbes` — diagnostics; `Tests/MiVibeTests` — executable test target.
Product and technical contract: `SPEC.md`; domain language: `CONTEXT.md`.

## Privacy & scope

Personal-use build for a single machine. Not sandboxed (AX is incompatible with the
sandbox), not notarized, not open source. The API key is stored locally in plain text
with owner-only file permissions; audio is streamed to Doubao only while the voice key
is physically held.
