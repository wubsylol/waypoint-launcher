#!/bin/zsh
# Reproducible, local-only fork release. No publishing, account export or notarization.
set -euo pipefail
repo="${0:A:h:h}"
label="1.2.9-wubs.1"
version="1.2.9"
build_number="17"
destination="${DESTINATION:-$repo/dist/local/$label}"
if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
    print -u2 "Commit source changes before building a release."
    exit 1
fi
if [[ -e "$destination/Waypoint.app" || -e "$destination/Waypoint-$label-arm64.zip" ]]; then
    print -u2 "Release destination already contains an artifact; choose a new DESTINATION."
    exit 1
fi
staging="$(mktemp -d /private/tmp/waypoint-local-release.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$destination" "$staging/Waypoint $label"
app="$staging/Waypoint $label/Waypoint.app"
VERSION="$version" BUILD_NUMBER="$build_number" BUNDLE_ID=io.wubs.waypoint-review \
    SIGN_IDENTITY=- SPARKLE_FEED='' WINDOWS_RUNTIME="${WINDOWS_RUNTIME:-$repo/Resources/WindowsRuntime}" WINDOWS_EXPERIMENTAL=0 APP_PATH="$app" \
    "$repo/scripts/bundle.sh"
# The target Mac must not need the build Mac's Xcode toolchain.
python3 - "$app" <<'PY'
import pathlib,subprocess,sys
app=pathlib.Path(sys.argv[1]);binary=app/'Contents/MacOS/Waypoint'
lines=subprocess.check_output(['otool','-l',str(binary)],text=True).splitlines()
for i,line in enumerate(lines):
    if 'cmd LC_RPATH' in line:
        path=lines[i+2].strip().removeprefix('path ').rsplit(' (offset ',1)[0]
        if path.startswith('/') and not path.startswith(('/usr/lib','/System/Library')):
            subprocess.run(['install_name_tool','-delete_rpath',path,str(binary)],check=True)
subprocess.run(['codesign','--force','--sign','-','--preserve-metadata=entitlements',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
assert subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip()=='arm64'
PY
cp "$repo/docs/releases/$label.md" "$staging/Waypoint $label/RELEASE NOTES.md"
cat > "$staging/Waypoint $label/INSTALL.txt" <<'INSTALL'
Quit Waypoint, then replace the old review app with Waypoint.app in Applications
(or your personal Applications folder). Keep only one deployed copy of this fork.
Do not delete your saved settings: this release keeps the review build's identity.
This build is locally signed, not notarized. macOS may require your approval in
System Settings → Privacy & Security. No Xcode or official Battle.net app is needed.
For a fresh setup: add an account, install WoW using Available Games, then Play
and choose your licence. Use Safari… is the optional manual browser-login route.
INSTALL
commit="$(git -C "$repo" rev-parse HEAD)"
cat > "$staging/Waypoint $label/BUILD INFO.txt" <<INFO
Source: $commit
Release: $label
App: $version ($build_number)
Architecture: arm64
Identity: io.wubs.waypoint-review
Signature: ad-hoc; not notarized
Self-update: disabled
INFO
archive="$destination/Waypoint-$label-arm64.zip"
ditto -c -k --norsrc --noextattr --keepParent "$staging/Waypoint $label" "$archive"
mkdir "$staging/check"
ditto -x -k "$archive" "$staging/check"
codesign --verify --deep --strict "$staging/check/Waypoint $label/Waypoint.app"
# Deliver the verified archive. Synced Documents folders can reapply Finder
# attributes to an expanded app after signing; the archive payload is unaffected.
(cd "$destination" && shasum -a 256 "${archive:t}") > "$archive.sha256"
print -r -- "Release built: $archive"
