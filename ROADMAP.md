# Roadmap

TrackpadProMax ships **few features, but solid ones**. Each release is tested on real hardware before it is published.

## v0.1 — Foundation
- [x] Multitouch stream (per-finger position, force, size, velocity)
- [x] Haptic engine (direct actuator + system fallback)
- [x] Pressure visualizer
- [x] Gesture recognizer: 1–4 finger taps / double taps, light / medium / hard presses, corner & edge zones
- [x] Actions: shortcuts, clicks, media & system keys, apps, URLs, Shortcuts, AppleScript
- [x] Modes + per-app profiles, global mode-switch hotkey with HUD
- [x] Settings UI
- [ ] Validation on more MacBook / Magic Trackpad models

## v0.2 — Gesture Discovery HUD
When you switch to an app that has gestures, a small notification-style card with a trackpad icon lists them. Hover a row and a minimal trackpad animation plays the gesture (fingers, taps, press rings), so you can learn what each app supports without opening settings.
- [x] Card on first activation of a freshly launched app, hotkey to show it on demand (`⌃⌥⌘G`)
- [x] Animated trackpad preview on hover, also in the gesture editor
- [x] Auto-dismiss (paused while hovered), "don't show again for this app", scope setting
- [ ] Polish from real-world use

## v0.2 — Mode wheel & surfaces
- [x] Radial mode wheel (four-finger double tap / hotkey), haptic ticks, tap to switch
- [x] Surface modes: on-screen trackpad with edge bars (volume, brightness, keyboard backlight, tracks, scrubbing)
- [x] Music surface with now-playing info
- [x] Output-device bars: hard-press the volume bar, pick a device, set its volume, switch output
- [x] Two-level mode wheel (Normal folder with gesture modes)
- [x] Tools: window tiling, app launcher, timer knob, quick settings
- [ ] More surfaces (numpad, app-specific panels, clipboard history)

## v0.3 — Continuous pressure controls
- Pressure-sensitive scroll and zoom speed
- Scroll detents, a "notched wheel" feel when scrolling

## v0.4 — Haptic notifications
- Haptic alerts for notifications, calendar events and low battery
- Accessibility haptics: feel buttons and window edges under the cursor (opt-in)

## Later
- Suppress the native click / Force Click for bound gestures (event tap)
- Swipe + force combinations, custom haptic waveforms
- Digital scale mode, drawing-tablet (pressure → pen) mode
- Homebrew cask, notarized builds, localization (Turkish first)

Ideas welcome in [Discussions](https://github.com/SerhanEnsar/TrackpadProMax/discussions).
