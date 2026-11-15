#!/bin/zsh
# Temporary diagnostic with the installed fork's identity; no app replacement.
set -euo pipefail
repo="${0:A:h:h:h}"
scratch="${SCRATCH_PATH:-/private/tmp/waypoint-native-battletag}"
xcrun swift build --package-path "$repo" --disable-sandbox --scratch-path "$scratch" --product Waypoint
bin_dir="$(xcrun swift build --package-path "$repo" --scratch-path "$scratch" --show-bin-path)"
python3 - "$bin_dir/Waypoint" <<'PY'
import pathlib,subprocess,tempfile,shutil,plistlib,sys
installed=pathlib.Path.home()/'Applications/Waypoint.app'
assert installed.exists(), 'Install the personal Waypoint fork first'
stage=pathlib.Path(tempfile.mkdtemp(prefix='waypoint-shared-signin-',dir='/private/tmp'))
app=stage/'Waypoint Shared Sign-In Check.app'
subprocess.run(['ditto','--norsrc','--noextattr',str(installed),str(app)],check=True)
binary=app/'Contents/MacOS/Waypoint'
shutil.copy2(sys.argv[1],binary)
paths=subprocess.check_output(['otool','-l',str(binary)],text=True)
if 'path @executable_path/../Frameworks ' not in paths:
    subprocess.run(['install_name_tool','-add_rpath','@executable_path/../Frameworks',str(binary)],check=True)
assert (app/'Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle').exists()
plist=app/'Contents/Info.plist'; info=plistlib.loads(plist.read_bytes())
assert info['CFBundleIdentifier']=='io.wubs.waypoint-review', 'Unexpected installed app identity'
info['CFBundleName']='Waypoint Shared Sign-In Check'
info['LSEnvironment']={'WAYPOINT_SHARED_SIGNIN_PROBE':'1'}
for key in ['SUFeedURL','SUEnableAutomaticChecks','SUAutomaticallyUpdate']:
    info.pop(key,None)
plist.write_bytes(plistlib.dumps(info))
subprocess.run(['codesign','--force','--sign','-','--preserve-metadata=entitlements',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
pathlib.Path('/private/tmp/waypoint-shared-probe-path').write_text(str(app))
print(app)
PY
