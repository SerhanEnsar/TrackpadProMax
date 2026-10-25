# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- Tiled windows no longer collapse to one with Stage Manager on: it is turned off before tiling, and every tiled window is brought to the front.
- Window tiling lists every open app (it used to miss apps on other desktops or behind a full-screen app) and places all of them: hidden or other-desktop apps are brought over, full-screen windows leave full screen first, and each placement is checked and retried.
- The two-finger confirm in window tiling works when the fingers land or lift a moment apart.
- Back in the middle of surfaces and tools returns to the mode wheel instead of closing everything.
- Surface bars now fill smoothly all the way down to 0 % (they used to stop moving below about 22 %).
- Multi-finger touches no longer trigger surface bars or the middle play/pause tap.

### Added
- Two-level mode wheel: Normal is a folder that opens a wheel of gesture modes; its middle goes back.
- Window tiling tool: pick a 2/3/4 split, drag the dividers, two-finger tap to confirm, drag apps from the left edge onto panes.
- App launcher tool: favourite apps (Dock apps by default) on a wheel.
- Quick settings tool: Dark Mode, Night Shift, Keep Awake, Wi-Fi, Bluetooth, Mute, Mic Off, Lock Screen.
- Output devices on the trackpad: hard-press the volume bar of a surface and your outputs (AirPods, Bluetooth speakers, built-in…) grow into bars. Slide sideways to pick one, up/down for its volume, press hard to route sound there, tap to go back.
- A four-finger tap (single or double) closes any surface or the mode wheel and goes back to Normal, like Esc.
- Each surface chooses what a tap in the middle does: Now Playing (play/pause) or Back (close). Control and Media default to Back; Media keeps showing the playing track.
- Mode wheel: four-finger double tap opens a radial wheel; slide to pick a mode with haptic ticks, tap to switch, tap in the middle to cancel.
- Surface modes: the trackpad turns into an on-screen touch panel. Edge bars set volume, display brightness and keyboard backlight directly, with haptic detents.
- Media mode is now a music surface: now-playing card, scrubbing along the bottom edge, track swipes, tap to play/pause (MediaRemote, with Music/Spotify AppleScript fallback).
- Gesture Discovery HUD: when you open an app, a card lists its trackpad gestures, and hovering a gesture plays it on an animated trackpad. Show it any time with `⌃⌥⌘G`.
- Animated gesture preview in the gesture editor.
- Multitouch stream from the private MultitouchSupport framework, loaded at runtime.
- Haptic engine with direct Taptic Engine actuation and a public-API fallback.
- Gesture recognizer for 1–4 finger taps and double taps, light / medium / hard presses, and corner and edge zones.
- Actions: keyboard shortcuts, mouse clicks, media and brightness keys, Mission Control, Show Desktop, screenshot, lock screen, apps, URLs, Shortcuts and AppleScript.
- Trackpad modes and per-app profiles, switchable with a global hotkey and confirmed by a haptic and an on-screen badge.
- Menu bar app with a pressure visualizer, gesture editor and sensitivity settings.
- Click gate: where a medium or hard press is bound, the system click waits. If the press fires, the click is dropped; if you let go earlier, the click goes through on release; dragging works as usual.
