#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}/../.."
PROBE_BUILD=$(mktemp -d /private/tmp/waypoint-sso-probe.XXXXXX)
cp tools/sso-discovery-probe/HTTP.swift "$PROBE_BUILD/main.swift"
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$PROBE_BUILD/cache" Sources/WaypointCore/LaunchOptions.swift "$PROBE_BUILD/main.swift" -o "$PROBE_BUILD/http-probe"
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path "$PROBE_BUILD/cache" Sources/WaypointCore/LaunchOptions.swift tools/sso-discovery-probe/Browser.swift -o "$PROBE_BUILD/browser-probe" -framework AppKit -framework WebKit
print "Built only; no authentication request has been made."
print "Explicit live runs: $PROBE_BUILD/http-probe or $PROBE_BUILD/browser-probe"
