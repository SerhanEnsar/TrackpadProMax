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
| **Trackpad modes** | Switchable sets of gestures (e.g. *Normal*, *Media*). Cycle them with a global hotkey (default `⌃⌥⌘T`), with a haptic and an on-screen badge. |
| **Per-app profiles** | Gestures that only apply in Safari, Final Cut, Figma… |
| **Haptic feedback** | Direct Taptic Engine control: confirm each gesture with a tick or a heavy click. |
| **Actions** | Keyboard shortcuts, right/middle click, media and brightness keys, Mission Control, Show Desktop, screenshot, lock screen, open apps or URLs, run **Shortcuts** and **AppleScript**. |
| **Pressure visualizer** | Live map of every finger with its force, size and angle. Use it to calibrate your thresholds. |

See the [roadmap](ROADMAP.md) for what's coming, such as the per-app **Gesture Discovery HUD**, pressure sliders for volume and brightness, scroll detents, and haptic notifications.

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

TrackpadProMax needs **Accessibility** access (*System Settings › Privacy & Security › Accessibility*) to send shortcuts and clicks. Reading the trackpad and playing haptics work without it. The app does no networking, and nothing leaves your Mac.

## Default gestures

| Mode | Gesture | Action |
|---|---|---|
| Normal | 3-finger tap | Middle click |
| Normal | Hard press, top-right corner | Mission Control |
| Normal | Hard press, top-left corner | Show Desktop |
| Normal | Hard press, bottom-right corner | Screenshot |
| Media | Hard press, center | Play / Pause |
| Media | Hard press, left / right edge | Previous / Next track |
| Media | Medium press, top / bottom edge | Volume up / down |
| Media | 3-finger tap | Mute |
| Both | 4-finger double tap | Next mode |

You can change all of them in **Settings › Gestures**.

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
