# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Gesture Discovery HUD: when you open an app, a card lists its trackpad gestures, and hovering a gesture plays it on an animated trackpad. Show it any time with `⌃⌥⌘G`.
- Animated gesture preview in the gesture editor.
- Multitouch stream from the private MultitouchSupport framework, loaded at runtime.
- Haptic engine with direct Taptic Engine actuation and a public-API fallback.
- Gesture recognizer for 1–4 finger taps and double taps, light / medium / hard presses, and corner and edge zones.
- Actions: keyboard shortcuts, mouse clicks, media and brightness keys, Mission Control, Show Desktop, screenshot, lock screen, apps, URLs, Shortcuts and AppleScript.
- Trackpad modes and per-app profiles, switchable with a global hotkey and confirmed by a haptic and an on-screen badge.
- Menu bar app with a pressure visualizer, gesture editor and sensitivity settings.
- Click gate: where a medium or hard press is bound, the system click waits. If the press fires, the click is dropped; if you let go earlier, the click goes through on release; dragging works as usual.
