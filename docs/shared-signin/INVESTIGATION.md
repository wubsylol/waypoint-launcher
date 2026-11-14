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

## Real-launch preview (pending game test)

The source branch includes an explicit `WaypointSharedSignInPreview` bundle
flag. Ordinary bundles omit it and keep normal login behavior. Preview bundles
use the WoW→Fen exchange on non-forced Diablo IV Play before considering any
cached Fen ticket; a missing source or failed exchange stops rather than
silently signing in through a different path. Explicit Sign In Again remains
the existing deliberate interactive path and is not a successful shared test.

The preview uses generated authorization only in memory for the normal Windows
launch handoff. It does not adopt the ticket, save it in Keychain, replace the
WoW token or rotate the account web session. A generated ticket's lifetime has
not been measured, so the preview obtains a fresh one on each launch. It is
Americas/WoW→Diablo IV only; general cross-title/region support remains unproven.

Build `tools/shared-signin-probe/build-preview.sh` from a clean, reviewed commit.
It creates an Apple silicon ZIP and checksum in outputs/previews/shared-sign-in,
with the existing runtime metadata and disabled self-updates. It does not install
the preview or merge the experiment into main. The user currently has no Diablo IV
installation available for the real-game test; installation and actual sign-in
acceptance remain pending. See the included PREVIEW-INSTRUCTIONS.md.

## Hearthstone extension

Revision 2 adds Hearthstone as the smaller native cross-game sign-in test.
Target `WTCG` is title 0x57544347; its regional version product is `hsb` and
its probe platform is `Mc64`. The explicit preview allowlist now contains
`WTCG` and `Fen` only; ordinary WoW and all other families retain their existing
login behavior. The diagnostic popup defaults to Hearthstone.

Synthetic tests check issuance title, target Mac platform/build and the preview
allowlist. Hearthstone’s free-to-play availability does not demonstrate paid
ownership; this stage tests only cross-game authorization.

Hearthstone uses the existing encrypted native launch-options handoff, while
Diablo IV uses the existing Windows handoff. Neither generated credential is
cached in the token vault or adopted as the account’s web session. Normal game
handoffs can persist data, so “not cached” does not mean no disk writes.

Live Hearthstone check passed: saved WoW authorization issued an owner-matched
WTCG credential, and a subsequent Hearthstone native Logon using the current
public `hsb` build returned the expected owner. No new sign-in page was required.
The diagnostic discarded its tickets and did not launch or install Hearthstone.
Actual Hearthstone main-menu acceptance remains pending.
