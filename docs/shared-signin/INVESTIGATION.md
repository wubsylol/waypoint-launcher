# Shared sign-in investigation

Experimental branch; production login behavior and saved credentials unchanged.
Initial scope: Americas, saved WoW authorization → Diablo IV (`Fen`).

## Evidence so far

- The normal launcher stores game-family tickets separately and does not try
  its existing WebKit session for a new family before presenting a fresh login.
- Browser-only live check: no Battle.net cookies in the selected saved WebKit
  store; Blizzard settled on an interactive sign-in. This is compatible with
  the existing Safari login path: Safari and WKWebView do not share their jars.
- An initial legacy GenerateWebCredentials method-8/fixed32 request returned
  3011 after owner-verified WoW authentication. It used an older protocol and
  does **not** prove that cross-title authorization is denied.
- Installed Forever static descriptors expose AuthenticationService v2:
  GenerateAuthToken method 3, request `title_id` field 1 uint32 (varint), response
  `auth_token` field 1 bytes. Normal WoW Logon already uses this v2 service.
- Corrected live GenerateAuthToken requests returned launch-ticket-shaped,
  matching-owner credentials for BOTH the WoW control and Diablo IV target,
  using the existing saved WoW authorization without another sign-in page.
  Neither returned credential was saved, logged, or used to launch a game.

- The subsequent live Diablo IV native Logon accepted a freshly generated
  credential and returned the expected Battle.net owner. This used the public
  Americas Diablo IV build and Windows platform without an installed Diablo IV
  client or another interactive login. The credential was discarded afterward.

Credential issuance is separate from target authentication, account entitlement
and actual game acceptance. No verified universal login/refresh lifetime is claimed.
The diagnostic includes a separate explicit Diablo IV native Logon check using
its target title, Windows platform and public regional build. It passed live native authentication; a real Diablo IV launch remains required
before claiming an end-to-end game sign-in fix.

## Controls and limits

The probe reads selected account preferences and its existing WebKit store.
The explicit native buttons additionally read only that owner's saved WoW
Keychain token and send it to Blizzard over the existing system-trusted TLS
transport. Owner verification precedes issuance; generated credentials must
match the expected owner. No saved password, client secret, official-launcher
secret, account adoption, licence selection, launch handoff, Keychain write,
friend service or account-security change is involved.

Close all Blizzard games on all devices before native checks; downloads may
continue. Local WoW is checked again after public version lookups. Connections
and HTTP lookups are bounded, native transports close after success or error,
and closing the probe's final window terminates its process. Cross-device
running games cannot be detected automatically.

Synthetic transport tests verify method/title wire fields, source/returned
owner rejection, target Windows platform/build, cancellation and disconnection.
These do not substitute for live authentication or a real launch.

## Build and run

Use `tools/shared-signin-probe/build.sh` on a Mac with this personal fork
installed in `~/Applications/Waypoint.app`. Quit the installed client first.
The script creates a temporary clone with the same identity so its existing
preferences/browser store can be read, sets the explicit diagnostic environment
flag, adds/verifies the bundled framework search path and verifies the ad-hoc
signature. It does not replace the installed app. Keep the temporary app out
of source/download folders and remove it when testing is finished.

An initial manually packaged test omitted the framework search path and
terminated in dyld before authentication; the reproducible build script fixes
that packaging error. No game or saved authorization was affected.

## References

- Older public protocol reference (not current server permission evidence):
  https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/authentication_service.pb.h
- Older method dispatch:
  https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/authentication_service.pb.cc
- Current method and field facts were read only from static authentication
  descriptors in the installed Forever client. No account files, process
  memory, private credential values or official launcher secrets were inspected.
