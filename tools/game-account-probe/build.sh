#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}/../.."
PROBE_ROOT=$(mktemp -d /private/tmp/waypoint-account-probe.XXXXXX)
PROBE_APP="$PROBE_ROOT/Waypoint Account Probe.app"
mkdir -p "$PROBE_APP/Contents/MacOS"
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$PROBE_ROOT/cache" Sources/WaypointCore/GameAccounts.swift tools/game-account-probe/main.swift -o "$PROBE_APP/Contents/MacOS/Waypoint Account Probe" -framework AppKit -framework WebKit
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string io.wubs.waypoint-account-probe' "$PROBE_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string Waypoint Account Probe' "$PROBE_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string Waypoint Account Probe' "$PROBE_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$PROBE_APP/Contents/Info.plist"
codesign --force --sign - "$PROBE_APP"
codesign --verify --strict "$PROBE_APP"
print "$PROBE_APP"
