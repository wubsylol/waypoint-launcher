# Presence/session investigation probes

Current UI: Authenticated App-handle availability control4. Earlier presence query controls below
are historical; see the final section for the current request scope.

Experimental social branch only; not part of live Waypoint. Build with
`tools/presence-probe/build.sh`. No request occurs until Check presence fields.
Close Blizzard games on both Macs first. The local guard detects WoW only.

Uses the existing temporary App credential/authentication flow, then requests
friend IDs without fetch_names. Queries only the first three returned friends,
using PresenceService original hash0x138D200C/raw method5 and the owner-verified
App callback client ID. Request scope INCLUDE_ALL_GAME_ACCOUNTS=2 and fixed keys:
BN1/13, BN1/3, BN2/1, BN2/8. Key meanings are candidates: account status and
online-game-account messages exist in the schema; legacy public code describes
BN2/1 as online and BN2/8 as rich presence. Exact modern per-key semantics remain
unverified. BN1/13 is a status candidate, not a demonstrated status mapping.

No subscription, presence update, message, friendship mutation or explicit
Create/Restore/DestroySession call is sent. Existing page/entry/frame/deadline
bounds remain. A refusal stops immediately; no fallback or automatic retry.
Queries use IDs from this connection's freshly validated friends list, never
user-entered IDs. Returned state owners must match the queried friend. Present
reply context headers must match the authenticated App context.

The report exposes only sample/state counts, candidate key declared-kind categories and
recognised public game-title labels from returned game-account handles. It
excludes account IDs, game-account IDs, key unique IDs, names, status values,
activity strings, blobs, timestamps and raw replies. Titles in returned states
are not called currently played games. Missing states are not treated as
Offline. No files, preferences or saved credentials are written by the probe.

## Provenance

Current installed Forever static descriptors were inspected offline with the
repository's existing `inspect_protocol.inspect(data, files=...)`, explicitly
restricted to these known embedded filenames:

- bgs/low/pb/client/api/client/v2/presence_types.proto
- bgs/low/pb/client/api/client/v2/presence_service.proto
- bgs/low/pb/client/api/common/v2/attribute_types.proto

See docs/social-service/forever-presence-metadata.json for metadata-only output,
source binary hash/size and first descriptor offsets within its universal binary.
No binary, user/runtime data or raw descriptor is included. Field names/numbers,
query/status enums and Variant types corroborate public generated schemas:

- https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/api/client/v2/presence_service.pb.h
- https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/api/client/v2/presence_types.pb.h
- https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/api/common/v2/attribute_types.pb.h

Legacy field meaning reference (not a modern mapping guarantee):
https://github.com/EionRobb/purple-battlenet/blob/d2113e28cdad24317e34886c50e8a6fceaeff53d/libbattlenet.c
No external implementation is copied or executed.

48 targeted native/probe checks pass, including request allowlist/scoping,
identity/privacy/bounds,3-friend cap, exact read-only dispatch, refusal stop and
production-like cancellation. Previously working friends tests pass after
extracting its shared authenticated lookup helper. Native probe builds and
strict signature verification pass. Live result remains untested.

Variant labels report which declared schema fields were present, not validated
status semantics or an assertion about exact wire encoding. Private values are
not interpreted or displayed by this diagnostic.

## Explicit-zero key control2

Initial live query was refused7 after successful App login and friends lookup.
Control2 adds unique_id4=0 on every existing key and changes no query scope,
account ID, key title/group/field, service/method, context source or authentication.
Generated schema confirms the optional member/default0. Public client update
examples show explicit zero, but do not establish that Query requires it:
https://us.forums.blizzard.com/en/d4/t/main-thread-pc-game-client-freezes-at-logging-into-diablo-iv-when-launched-on-certain-nvme-drives/23732?page=14

This is a presence-of-member hypothesis control, not a demonstrated fix. No
since_us, session setup or alternative endpoint is added.49 targeted checks
pass, including an old/new request parity fixture. Status7 remains compatible
with multiple causes; do not infer permission denial, offline state or a need
for a new session from it. Live outcome pending.

## Existing App-session control3

Explicit-zero control2 also returned7. Current UI now performs a distinct,
read-only existing-session query under fresh owner-verified App authentication.
It sends source Connect/WoW Logon/GenerateAuthToken, closes source, then target
Connect/App Logon/GetSessionState5 with the verified target context. No friends
or presence query is sent, and no session lifecycle mutation is added. The
original public sessionDiagnostics route remains WoW-authenticated by default.

Only query status and owner-verified session-identity presence are reported.
Refusal leaves presence unknown, never “no session exists.” A returned identity
must match the authenticated owner.51 targeted tests pass, including the exact
App-control dispatch, empty query body, client-context source, refusal semantics
and wrong-owner response. Live outcome pending.

## Authenticated App-handle availability control4

App GetSessionState control3 also returned7/unknown. Static inspection of the
public current desktop core found a populated game-account handle in its login
CreateSessionRequest path. See DESKTOP-LIFECYCLE-17986.md for bounded evidence
and the important limits on that inference.

Control4 sends no request after App authentication. It classifies optional
owner-verified LogonRecord.game_account2 metadata, bounded to100 entries of128
bytes each. Only explicit nonzero IDs with App title/region1 count as matching;
multiple matches are ambiguous and malformed optional metadata is unrecognized,
not failed login. The UI exposes fixed classification/context-presence only,
never IDs, handles, names or raw values. Nothing is saved. No session creation
is implemented.53 targeted checks pass; native app builds. Live outcome pending.
