#!/bin/sh
# Builds TrackpadProMax.app (universal-free, native arch) into ./dist and zips it.
#
#   scripts/build-app.sh            release build
#   scripts/build-app.sh debug      debug build
#
# Signs ad hoc unless SIGN_IDENTITY is set (e.g. "Developer ID Application: …").
set -eu
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="$(cat VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/TrackpadProMax.app"

# Command Line Tools for macOS 27 ship without the SwiftUI macro plugin; the
# 26.x SDK builds fine and the app still runs on newer systems.
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ]; then
    for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk; do
        [ -d "$sdk" ] && export SDKROOT="$sdk"
    done
fi

swift build -c "$CONFIG" --product TrackpadProMax
BIN="$(swift build -c "$CONFIG" --show-bin-path)/TrackpadProMax"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TrackpadProMax"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --options runtime --timestamp=none --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"

(cd dist && rm -f "TrackpadProMax-$VERSION.zip" && ditto -c -k --keepParent TrackpadProMax.app "TrackpadProMax-$VERSION.zip")
echo "Built $APP ($VERSION, build $BUILD)"
