# Bounded presence schema probe

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
