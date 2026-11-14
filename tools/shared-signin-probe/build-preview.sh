#!/bin/zsh
# Experimental real-game launch package, separate from the stable release.
set -euo pipefail
repo="${0:A:h:h:h}"
if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
    print -u2 "Commit reviewed source before packaging a preview."
    exit 1
fi
stage="$(mktemp -d /private/tmp/waypoint-shared-preview.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
folder="$stage/Waypoint Shared Sign-In Preview"
app="$folder/Waypoint.app"
mkdir -p "$folder"
VERSION=1.2.5 BUILD_NUMBER=12 BUNDLE_ID=io.wubs.waypoint-review SIGN_IDENTITY=- SPARKLE_FEED='' \
    WINDOWS_RUNTIME="$repo/Resources/WindowsRuntime" WINDOWS_EXPERIMENTAL=0 APP_PATH="$app" "$repo/scripts/bundle.sh"
python3 - "$app" <<'PY'
import pathlib,plistlib,subprocess,sys
app=pathlib.Path(sys.argv[1]); plist=app/'Contents/Info.plist'
info=plistlib.loads(plist.read_bytes());info['WaypointSharedSignInPreview']=True;info['WaypointSharedSignInPreviewRevision']=2
info['CFBundleDisplayName']='Waypoint Shared Sign-In Preview'
plist.write_bytes(plistlib.dumps(info))
binary=app/'Contents/MacOS/Waypoint'
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
cp "$repo/tools/shared-signin-probe/PREVIEW-INSTRUCTIONS.md" "$folder/READ ME.md"
git -C "$repo" rev-parse HEAD > "$folder/SOURCE COMMIT.txt"
destination="${DESTINATION:-$repo/../outputs/previews/shared-sign-in}"
mkdir -p "$destination"
archive="$destination/Waypoint-Shared-Sign-In-Preview-arm64.zip"
[[ ! -e "$archive" ]] || { print -u2 'Preview archive already exists'; exit 1; }
ditto -c -k --norsrc --noextattr --keepParent "$folder" "$archive"
mkdir "$stage/check"
ditto -x -k "$archive" "$stage/check"
codesign --verify --deep --strict "$stage/check/Waypoint Shared Sign-In Preview/Waypoint.app"
(cd "$destination" && shasum -a 256 "${archive:t}") > "$archive.sha256"
print -r -- "Preview built: $archive"
