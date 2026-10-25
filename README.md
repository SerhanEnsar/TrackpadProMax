<div align="center">

# TrackpadProMax

**Make your MacBook's Force Touch trackpad pressure-sensitive and programmable, with haptic feedback.**

Bind light, medium and hard presses, multi-finger taps and corner zones to shortcuts, clicks, apps and scripts.
Switch between trackpad modes with one keyboard shortcut. Feel every action through the Taptic Engine.

[![CI](https://github.com/SerhanEnsar/TrackpadProMax/actions/workflows/ci.yml/badge.svg)](https://github.com/SerhanEnsar/TrackpadProMax/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
[![Latest release](https://img.shields.io/github/v/release/SerhanEnsar/TrackpadProMax?include_prereleases&sort=semver)](https://github.com/SerhanEnsar/TrackpadProMax/releases)

</div>

---

Every MacBook since 2015 has a **Force Touch trackpad**. It measures how hard each finger presses, and a **Taptic Engine** under it fakes the click you feel. macOS only uses a little of this hardware: one click, one "Force Click" for Look Up, and a few haptics.

**TrackpadProMax** is a free, open-source macOS menu bar app that reads the trackpad's raw multitouch and pressure data and lets you turn it into your own input surface.

## Features

| | |
|---|---|
| **Pressure tiers** | Light, medium and hard presses are separate gestures, each with its own action. |
| **Tap gestures** | 1–4 finger taps and double taps, without clicking. |
| **Corner & edge zones** | Hard-press the top-right corner for Mission Control, the left edge for the previous track, and so on. |
| **Mode wheel** | Four-finger double tap opens a radial wheel in the middle of the screen. Slide a finger to point at a mode (each step ticks through the Taptic Engine), tap to switch. **Normal** is a folder: it opens a second wheel with your gesture modes. Also on `⌃⌥⌘T`. |
| **Window tiling** | Split the screen into 2, 3 or 4 windows without touching the cursor: press a corner of the trackpad to pick the split, press and drag the dividers, two-finger tap to confirm, then drag apps from the left edge onto their panes. |
| **App launcher** | Your favourite apps (from the Dock by default) on a wheel: slide to pick, tap to open. |
| **Timer knob** | Circle a finger to set minutes with a haptic tick per minute, tap to start. The menu bar counts down and the trackpad buzzes when time is up. |
| **Quick settings** | A 3×3 grid on the trackpad: Dark Mode, Night Shift, Keep Awake, Wi-Fi, Bluetooth, Mute, Mic Off, Lock Screen. |
| **Surface modes** | The whole trackpad becomes a touch control panel shown on screen. **Control**: slide the right edge for volume, the left for display brightness, the bottom for keyboard backlight. **Media**: now-playing card, scrub the track along the bottom edge, swipe the top for tracks and tap it to play/pause. Every edge is configurable. Hard-press the volume bar to see your **output devices** (AirPods, Bluetooth speakers…): slide to pick, up/down for that device's volume, press hard to switch. A four-finger tap, or a tap in the middle, closes a surface. |
| **Per-app profiles** | Gestures that only apply in Safari, Final Cut, Figma… |
| **Haptic feedback** | Direct Taptic Engine control: confirm each gesture with a tick or a heavy click. |
| **Actions** | Keyboard shortcuts, right/middle click, media and brightness keys, Mission Control, Show Desktop, screenshot, lock screen, open apps or URLs, run **Shortcuts** and **AppleScript**. |
| **Gesture Discovery HUD** | Open an app and a small card lists its trackpad gestures. Hover one to watch it played on an animated trackpad. Press `⌃⌥⌘G` to show it any time. |
| **Pressure visualizer** | Live map of every finger with its force, size and angle. Use it to calibrate your thresholds. |

See the [roadmap](ROADMAP.md) for what's coming, such as pressure sliders for volume and brightness, scroll detents, and haptic notifications.

## Installation

### Download

Grab the latest `TrackpadProMax-x.y.z.zip` from [Releases](https://github.com/SerhanEnsar/TrackpadProMax/releases), unzip it and move **TrackpadProMax.app** to `/Applications`.

The app is not notarized yet, so macOS blocks it on first launch. Right-click it, choose **Open**, then confirm.

### Build from source

Requirements: macOS 15+, Swift 6 (Xcode 16+ or the Command Line Tools).

```sh
git clone https://github.com/SerhanEnsar/TrackpadProMax.git
cd TrackpadProMax
scripts/build-app.sh          # → dist/TrackpadProMax.app
open dist/TrackpadProMax.app
```

Run the tests with `scripts/test.sh` (or `swift test` with Xcode installed).

### Permissions

TrackpadProMax needs **Accessibility** access (*System Settings › Privacy & Security › Accessibility*) to send shortcuts and clicks and to move windows when tiling. Reading the trackpad and playing haptics work without it. macOS asks once for **Automation** when the app first reads Music/Spotify or switches Dark Mode, and for **Bluetooth** the first time you toggle it. The app does no networking, and nothing leaves your Mac.

## Default modes

| Mode | How it works |
|---|---|
| **Normal** | Your gestures. 3-finger tap = middle click; hard press in the top-right / top-left / bottom-right corner = Mission Control / Show Desktop / Screenshot; 4-finger double tap = mode wheel. |
| **Media** | Surface: now playing in the middle (tap = back), top edge swipe = previous/next track and tap = play/pause, bottom edge = scrub the track, right edge = volume. |
| **Control** | Surface: right edge = volume, left = display brightness, bottom = keyboard backlight, top = tracks; tap the middle to go back. |

| **Windows / Apps / Timer / Quick Settings** | Tools, see the feature table. |

Surfaces and tools close with a four-finger tap, Esc, a tap in the middle (Back) or after a few idle seconds. You can change gestures and edge controls in **Settings › Gestures**.

## How it works

```
MultitouchSupport.framework ──► TouchStream ──► GestureRecognizer ──► GestureDispatcher ──► ActionPerformer
   (private, via dlopen)       (~100 Hz frames)   (taps, force tiers,     (mode + app profile       (CGEvent, media keys,
                                                   zones; pure & tested)   → binding, haptic)        Shortcuts, AppleScript)
MTActuator ◄── HapticEngine (falls back to NSHapticFeedbackManager)
```

- **`TrackpadCore`** is a Swift library with no UI: touch stream, haptics, the gesture recognizer, configuration and actions. The recognizer is a pure value type, unit-tested with synthetic touch frames.
- **`TrackpadProMax`** is the SwiftUI menu bar app on top of it.
- Apple's private `MultitouchSupport` framework is loaded at runtime with `dlopen`, so the app never links it. If a future macOS removes it, the app keeps running with reduced features. That's also why the app can't be on the Mac App Store.

Force values are raw sensor units that roughly correspond to grams.

## FAQ

**Is this a BetterTouchTool alternative?**
It overlaps on trackpad gestures, but it focuses on what's unique to Force Touch hardware: pressure levels and haptics. It's free and open source.

**Does it work with the Magic Trackpad?**
Magic Trackpad 2 and newer have Force Touch, and the multitouch stream includes them. Pressure and haptics should work, but only the MacBook built-in trackpad has been tested so far.

**Why does my one-finger tap also click?**
macOS's *Tap to Click* still runs. Bind 3/4-finger taps or corner zones to avoid overlap, or turn off the system gesture. The gesture editor warns you about known conflicts.

**Does a hard press also click the button under the pointer?**
No. Where a medium or hard press is bound, TrackpadProMax holds the system click back. If the press reaches its level, the click is dropped and only your action runs. If you let go before that, the normal click happens on release. Dragging is never delayed.

## Contributing

Bug reports, ideas and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Raw-data reports from other MacBook and Magic Trackpad models are especially valuable.

## Citation

If you use TrackpadProMax in research, please cite it with the metadata in [CITATION.cff](CITATION.cff) (GitHub shows a "Cite this repository" button).

## License

[Apache License 2.0](LICENSE) © 2026 Serhan Ensar.
TrackpadProMax is not affiliated with Apple. *Force Touch*, *Taptic Engine*, *MacBook* and *macOS* are trademarks of Apple Inc.
