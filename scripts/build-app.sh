#!/bin/sh
# Builds TrackpadProMax.app into ./dist and zips it (release: universal binary).
#
#   scripts/build-app.sh            release build
#   scripts/build-app.sh debug      debug build
#
# Signing: SIGN_IDENTITY if set (e.g. "Developer ID Application: …"), else the
# local identity from create-signing-identity.sh if present, else ad hoc.
# Ad-hoc builds lose the Accessibility permission on every rebuild.
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

# Release builds are universal (Apple Silicon + Intel).
ARCHS=""
[ "$CONFIG" = "release" ] && ARCHS="--arch arm64 --arch x86_64"
# shellcheck disable=SC2086
swift build -c "$CONFIG" $ARCHS --product TrackpadProMax
# shellcheck disable=SC2086
BIN="$(swift build -c "$CONFIG" $ARCHS --show-bin-path)/TrackpadProMax"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TrackpadProMax"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [ -z "${SIGN_IDENTITY:-}" ]; then
    LOCAL="TrackpadProMax Local Signing"
    if security find-identity -p codesigning 2>/dev/null | grep -q "$LOCAL"; then
        SIGN_IDENTITY="$LOCAL"
    else
        SIGN_IDENTITY="-"
        echo "warning: signing ad hoc; run scripts/create-signing-identity.sh to keep permissions across rebuilds" >&2
    fi
fi
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"

(cd dist && rm -f "TrackpadProMax-$VERSION.zip" && ditto -c -k --keepParent TrackpadProMax.app "TrackpadProMax-$VERSION.zip")
echo "Built $APP ($VERSION, build $BUILD)"
