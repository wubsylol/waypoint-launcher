#!/bin/zsh
# Isolated read-only UI; no writes to the saved login or account preferences.
set -euo pipefail
repo="${0:A:h:h:h}"
scratch="${SCRATCH_PATH:-/private/tmp/waypoint-friends}"
xcrun swift build --disable-sandbox --package-path "$repo" --product Waypoint --scratch-path "$scratch" --cache-path /private/tmp/waypoint-account-review-cache
bin_dir="$(xcrun swift build --package-path "$repo" --scratch-path "$scratch" --show-bin-path)"
app="${APP_PATH:-/private/tmp/Waypoint Friends Probe.app}"
mkdir -p "$app/Contents/MacOS"
xcrun swiftc -parse-as-library -I "$bin_dir" "$repo/tools/friends-probe/main.swift" "$bin_dir/WaypointCore.o" -o "$app/Contents/MacOS/FriendsProbe"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FriendsProbe</string>
<key>CFBundleIdentifier</key><string>io.wubs.waypoint-friends-probe</string>
<key>CFBundleName</key><string>Waypoint Friends Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
print -r -- "$app"
