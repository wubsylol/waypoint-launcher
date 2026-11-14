# Shared sign-in diagnostic

Run `./tools/shared-signin-probe/build.sh` from this repository. It builds the
AppKit executable and makes a verified temporary app with the installed personal
fork's bundle identity. Quit the installed Waypoint first. The temporary app
opens only the diagnostic when `WAYPOINT_SHARED_SIGNIN_PROBE=1` is set by its
launch configuration; ordinary Waypoint startup is unchanged.

The browser button tries existing owner-scoped cookies without submitting a
password. Native buttons read the selected owner's saved WoW token from its
normal Keychain item, authenticate it with Blizzard, then make one credential
issuance request. The separate validation button also authenticates the
result against the Diablo IV title. No returned ticket is saved or launched.

Close all Blizzard games on all Macs first. If macOS asks for Keychain access,
verify the requested service is the personal Waypoint Battle.net login-token
item; approve it yourself. Never paste credentials into chat or diagnostic logs.
See `docs/shared-signin/INVESTIGATION.md` for the evidence and limits.
