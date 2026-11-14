# Read-only Battle.net friends experiment

Branch: `experiment/battlenet-friends`. Do not merge or push this experiment to
`main`. This is a bounded snapshot probe, not a supported social/chat client.

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

It calls only friends v2 `GetFriends` method 5 (original service hash
`0x5869BE8C`; schema name hash is `0x9D059A2F`) after connection/authentication.
Continuation pages are bounded to 20, total friends to 1000, with the existing
35-second native deadline and frame bounds. It does not subscribe, set presence,
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
