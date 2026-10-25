# Contributing to TrackpadProMax

Thanks for helping! Bug reports, hardware data, ideas and code are all welcome.

## Reporting bugs
Open an [issue](https://github.com/SerhanEnsar/TrackpadProMax/issues/new/choose) and include your Mac model, macOS version and app version. For gesture problems, the force values the **Pressure Visualizer** shows during the gesture help a lot.

## Development
```sh
scripts/test.sh                # unit tests
scripts/build-app.sh debug     # build dist/TrackpadProMax.app
```
- `Sources/TrackpadCore` holds the logic (no UI). Keep it testable: new recognizers should be pure functions over `TouchFrame`s, with tests in `Tests/TrackpadCoreTests`.
- `Sources/TrackpadProMax` holds the SwiftUI menu bar app.
- Every private API goes through `MultitouchBridge` and must degrade gracefully if a symbol is missing.

Rebuilt ad-hoc-signed apps get a new code signature, so macOS may ask for Accessibility permission again. Remove the old entry in *System Settings › Privacy & Security › Accessibility* and add it again.

## Pull requests
- One topic per PR, with tests for logic changes.
- Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).
- Add a line under **Unreleased** in `CHANGELOG.md` for user-visible changes.
- CI (`swift test` + app build) must pass.

By contributing, you agree that your contributions are licensed under the Apache License 2.0.
