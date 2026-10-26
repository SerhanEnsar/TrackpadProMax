# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- Tapping the middle of the wheel (or any tap that closes an overlay) no longer clicks the window under the cursor.

## [0.1.0] - 2026-10-26

First public release.

### Added

#### Trackpad input
- Raw multitouch stream (per-finger position, force, size) from the private MultitouchSupport framework, loaded at runtime.
- Gesture recognizer: 1–4 finger taps and double taps, light / medium / hard presses, corner and edge zones.
- Click gate: where a deeper press is bound, the system click waits and is delivered as soon as you ease off, so a hard press never also clicks the button under the pointer.
- Haptic engine with direct Taptic Engine actuation and a public-API fallback.

#### Gestures and actions
- Actions: keyboard shortcuts, mouse clicks, media and brightness keys, Mission Control, Show Desktop, screenshot, lock screen, apps, URLs, Shortcuts and AppleScript.
- Gesture modes with per-app profiles.
- Gesture Discovery HUD: opening an app shows a card with its gestures; hovering one plays it on an animated trackpad (`⌃⌥⌘G` shows it any time).

#### Mode wheel
- Four-finger double tap (or `⌃⌥⌘T`) opens a radial wheel. Slide to pick (haptic tick per step), tap to switch.
- Normal is a folder that opens a wheel of gesture modes.
- A tap in the middle goes back; a four-finger tap or Esc closes everything.

#### Surfaces
- **Control**: the trackpad becomes an on-screen panel. Edge bars set volume, display brightness and keyboard backlight directly, with haptic detents.
- **Media**: now-playing card, scrubbing along the bottom edge, track swipes and play/pause on the top edge (MediaRemote, with a Music/Spotify AppleScript fallback).
- Output devices: hard-press the volume bar to see your outputs (AirPods, Bluetooth speakers, built-in…), set each one's volume and switch to it.
- Every edge control and the middle tap are configurable.

#### Tools
- **Windows**: cursor-free window tiling. Pick a 2/3/4 split, drag the dividers, two-finger tap to confirm, then drag apps from the left edge onto panes. Dividers adapt to each app's minimum window size, full-screen windows leave full screen, and Stage Manager is turned off so all windows stay on screen.
- **Apps**: favourite apps (Dock apps by default) on a wheel.
- **Quick Settings**: Dark Mode, Night Shift, Keep Awake, Wi-Fi, Bluetooth, Mute, Mic Off and Lock Screen on a 3×3 grid.

#### App
- Menu bar app with a pressure visualizer, gesture editor, surface and launcher editors, and sensitivity settings.
- Settings are stored as JSON with forward-compatible decoding and migrations.

[Unreleased]: https://github.com/SerhanEnsar/TrackpadProMax/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/SerhanEnsar/TrackpadProMax/releases/tag/v0.1.0
