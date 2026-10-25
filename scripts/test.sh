#!/bin/sh
# Runs the test suite. With Command Line Tools only (no Xcode), SwiftPM does not
# find the swift-testing macro plugin on its own, so point it there explicitly.
set -eu
cd "$(dirname "$0")/.."
PLUGIN="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$PLUGIN" ]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGIN" "$@"
fi
exec swift test "$@"
