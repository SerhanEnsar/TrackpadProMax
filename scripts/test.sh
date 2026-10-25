#!/bin/sh
# Runs the test suite.
#
# With Command Line Tools only (no Xcode), two workarounds apply:
# - SwiftPM does not find the swift-testing macro plugin, so pass its path.
# - The macOS 27 SDK in the CLT lacks the SwiftUI macro plugin, so build with 26.x.
set -eu
cd "$(dirname "$0")/.."
DEV="$(xcode-select -p)"
if [ "$DEV" = "/Library/Developer/CommandLineTools" ]; then
    if [ -z "${SDKROOT:-}" ]; then
        for sdk in "$DEV"/SDKs/MacOSX26*.sdk; do
            [ -d "$sdk" ] && export SDKROOT="$sdk"
        done
    fi
    PLUGIN="$DEV/usr/lib/swift/host/plugins/testing"
    if [ -d "$PLUGIN" ]; then
        exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGIN" "$@"
    fi
fi
exec swift test "$@"
