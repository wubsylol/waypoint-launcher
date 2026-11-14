# Read-only Battle.net friends experiment

Branch: `experiment/battlenet-friends`. Do not merge or push this experiment to
`main`. This is a bounded social-read probe, not a supported social/chat client.

Build with `tools/friends-probe/build.sh`, then open the printed app path. The
probe makes no connection until **Read friends** is clicked. Close every WoW
client first: it creates a separate game-authentication session and coexistence
with a running game has not been established. It blocks known running WoW
executables, but the user should still close all clients.

The probe reads the selected account from `io.wubs.waypoint-review` preferences
and the corresponding saved WoW token from the existing Keychain service after
the click. It checks selected-account/token identity, fetches public Americas
Forever build metadata and performs native authentication with owner checks.
No saved token, login preference, installation or account selection is modified.
Keychain access may prompt for approval. No new sign-in is requested by this tool.

The core can explicitly select either read-only friends v2 `GetFriends` method
5 (original hash `0x5869BE8C`; name hash `0x9D059A2F`) or legacy friends v1
`GetFriendList` method 13 (original hash `0xA3DDB1BD`). Probe version 0.0.3 explicitly selected the legacy route. Version 0.0.4
selects legacy Subscribe method 1 for its initial response, then disconnects. There is no automatic fallback or retry.
Continuation pages are bounded to 20, total friends to 1000, with the existing
35-second native deadline and frame bounds. Except for the explicit connection-scoped initial-subscription mode described below,
it does not subscribe. It does not set presence,
send/receive chat, add/remove friends or accept invitations. Merely opening an
authentication session is not a proof of no server-side session/presence effects.

Friend account IDs and BattleTags are retained only in the in-memory result and
shown in the local window; missing tags use an ID label. Real names, notes,
emails and raw attributes are discarded by the parser. The tool does not read
the clipboard/browser storage or write the returned list to a log or file.
Cancel clears the displayed list and cancels any pending request. Closing the
window terminates the tool. Numeric service rejection codes may be displayed,
but credentials and raw replies must never be printed.

## Protocol provenance

Independently authored Swift implementation using public wire facts from the
following generated schema metadata, not copied implementation code:

- https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/api/client/v2/friends_service.pb.h
- https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/api/client/v2/friends_service.pb.cc
- https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/api/client/v2/friends_types.pb.h

Request continuation is field 2; response friends are field 1 and continuation
field 2. Friend ID is uint64 field 1; BattleTag is string field 3. Fields for real
names, notes and other attributes are deliberately not exposed.

## Validation and limits

Synthetic tests cover multiple pages, duplicates, repeated continuation, wrong
owner before any social request, minimal read-only request dispatch and malformed
names. Existing native discovery disconnect, deadline and cancellation checks
remain enabled after extracting shared authentication.

Live access, non-empty results and absence of session interference remain
unproven. A service rejection does not prove the whole feature impossible: it
may reflect service routing, permissions, protocol version or login scope.
No change to launcher main, PR submission, or chat transmission is authorized by
this experiment. Account/friend details must not be included in source or docs.


## First live result and diagnostics update

The first user-run probe returned status 3025 and no list. Another Waypoint
instance was downloading on a separate Mac; it was not asked to stop. The first
probe did not label the failing stage, so this does not establish whether native
authentication or the friends RPC was refused. It does not establish a concurrent
session conflict.

Public error metadata maps 3025 (`0xBD1`) to `ERROR_RPC_METHOD_DISABLED`; the
duplicate-session code is a separate value. Reference:
https://github.com/TrinityCore/WowPacketParser/blob/master/WowPacketParser/Enums/BattlenetRpcErrorCode.cs

Diagnostics version 0.0.2 wraps only friends-RPC refusals, distinguishing them
from connection/authentication failures without logging any extra private data.
No new RPC, fallback, subscription or automatic retry is introduced. A synthetic
post-authentication 3025 reply tests this distinction. A fresh live result is
still needed to locate the actual failure stage; keep the other Mac’s download
running during that test.


## Confirmed v2 refusal and legacy test

The user’s diagnostics-2 run reported: authentication succeeded, then the
correlated friends method returned 3025 (`ERROR_RPC_METHOD_DISABLED`). This
establishes that the v2 call is disabled for the tested session, not that the
saved login failed. It does not establish a conflict with the other Mac.

Version 0.0.3 tries the distinct legacy v1 GetFriendList read-only method with
an empty request (its agent_id field is optional). It does not subscribe or
modify friendship state. Public schema references:

- https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/friends_service.pb.h
- https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/friends_service.pb.cc
- https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/friends_types.pb.h
- https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/entity_types.pb.h

The legacy response has repeated Friend entries in field 1, each with an
EntityId in field 1 (optional fixed64 high1/low2). The parser requires nonzero
low and unique full entity references. It does not assume an entity’s high bits
or turn arbitrary attributes into names. The UI shows only a count and generic
friend rows, because this response has no dedicated BattleTag field. Empty
results alone do not prove correct enumeration against the expected account.

18 targeted synthetic/native regression checks pass, including fixed64 legacy
entity parsing and exact read-only dispatch. Legacy live access is still
unproven. Keep the other Mac’s download running; close WoW before any new test.


## Initial-subscription experiment (version 0.0.4)

The user confirmed that the legacy v1 GetFriendList method also returned 3025
after successful authentication. Neither direct snapshot call is usable for
the tested session. No download on the user’s other Mac was stopped.

The next explicit mode calls legacy v1 Subscribe (hash `0xA3DDB1BD`, method 1),
with required object_id field 2 set to connection-local listener object 1;
optional agent_id is omitted. Public SubscribeResponse schema places friends
in field 5, not field 1 (deprecated max_friends). The same bounded entity-only
parser is used and ignores invitation and other fields. The existing native
session defer closes the connection immediately after parsing the initial
response, or on rejection, cancellation, deadline or disconnect.

This mode creates temporary subscription state on that connection. It does not
set presence, modify friendships, send messages or keep a background social
session. Listener-object handling and server acceptance are hypotheses for the
bounded live test, not established facts. Unexpected callbacks still fail closed.

A synthetic response containing both max_friends field 1 and friends field 5
checks the correct field and exact Subscribe dispatch, followed by connection
closure. No automatic fallback to this mode occurs. The UI labels it explicitly.

## Version 0.0.4 live result

One user-authorized read attempt was run through the probe UI. The selected
saved login authenticated, then the correlated legacy Subscribe reply returned
3025 (`ERROR_RPC_METHOD_DISABLED`). No friends list was returned. The connection
closed through the existing deferred cleanup. The other Mac’s download was not
stopped or modified. No messages or friendship mutations were requested.

All three tested methods (v2 GetFriends, v1 GetFriendList and v1 Subscribe) are
therefore disabled for the tested session/routing. This does not prove friends
or messaging are impossible, or identify whether the limitation is client/login
scope, protocol version or service routing. Stop repeated live retries at this
point. Investigate the current social client authentication and service path
before any next network experiment. Running-game coexistence remains untested.

19 targeted synthetic/native regression checks passed for version 0.0.4.


## Offline social/auth investigation

See [the research report](../../docs/social-service/INVESTIGATION.md) and
[metadata inventory](../../docs/social-service/client-17987-metadata.json) for
the installed client’s current protocol/session findings and an ordered live
plan. `offline/inspect_protocol.py` and its tests have no network/authentication
code and do not require a sign-in. No additional live test was run for that
report. In particular, the client-call flag, identity headers and application
session are still unverified hypotheses, not implemented fixes.
