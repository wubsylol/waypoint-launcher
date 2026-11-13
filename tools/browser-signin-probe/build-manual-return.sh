#!/bin/zsh
# Isolated development tool; never changes Waypoint's Keychain login.
set -euo pipefail
repo="${0:A:h:h:h}"
xcrun swift build --package-path "$repo" --product Waypoint
bin_dir="$(xcrun swift build --package-path "$repo" --show-bin-path)"
app="${APP_PATH:-$repo/build/Waypoint Browser Return Test.app}"
mkdir -p "$app/Contents/MacOS"
xcrun swiftc -parse-as-library -I "$bin_dir" \
    "$repo/tools/browser-signin-probe/ManualBrowserReturn.swift" \
    "$bin_dir/WaypointCore.o" -o "$app/Contents/MacOS/ManualBrowserReturn"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ManualBrowserReturn</string>
<key>CFBundleIdentifier</key><string>io.wubs.waypoint-browser-return-test</string>
<key>CFBundleName</key><string>Waypoint Browser Return Test</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSRemovableVolumesUsageDescription</key><string>Read the existing WoW installation for this browser login test.</string>
</dict></plist>
PLIST
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
print -r -- "$app"
