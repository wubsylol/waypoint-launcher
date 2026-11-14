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


## Explicit client-call control (version 0.0.5)

The user returned and confirmed WoW was closed. This mode selects modern v2
GetFriends with method `0x40000005`, keeping endpoint, title, saved token, hash,
and initial body unchanged from the original v2 control. It does not create an
application session or subscribe. A parity test compares actual mock-transport
packets: connection/authentication packets match byte-for-byte; the decoded
social header differs only in method field 2 and the initial bodies are empty.

One bounded lookup is attempted. If a successful response includes continuation,
the existing up-to-20-page/1000-entry bounds still apply; this is not a promise
of exactly one RPC after success. Refusal stops immediately, with no fallback.
The UI displays returned BattleTags or numbered placeholders, not raw friend
IDs. 20 targeted native/probe checks pass. Live outcome is recorded separately.

Live v0.0.5 result: the window and the user both confirmed successful owner-
verified authentication followed by a correlated status3011 (INVALID_METHOD)
for GetFriends with method0x40000005. This differs from the raw method5 refusal
3025. The flag variant is not a fix and should not replace raw methods. No
session was created and no friend list returned. Download processes were left
alone. Stop using flagged methods unless further wire evidence supports them.

## Read-only session diagnostics (version 0.0.6)

After the failed flag control, the next mode returns only metadata-presence
booleans and a correlated GetSessionState status. It records ConnectResponse
bindless acceptance7/CIID9 presence, and owner-verified LogonRecord BattleTag3,
game_account2 and session_key5 presence. It never exposes those actual values.

It then calls only SessionService GetSessionState (original hash0x7B37D770,
raw method5, empty body). No friends RPC, CreateSession, RestoreSession,
DestroySession, MarkSessionAlive, presence update or subscription is requested.
Session-query refusals retain their status and unknown session existence; they
are distinct from authentication/listener failure. If a session ID is returned,
its account owner is checked before any summary is displayed. No identifiers,
keys, account names or raw replies are displayed or written. A query refusal is
not evidence that the user has no other sessions. The transport closes normally.

23 targeted native/probe checks pass, including exact read-only dispatch,
refusal handling and a wrong-owner response. Live result recorded separately.

Version0.0.6 live attempt ended with generic failure after a likely Keychain
permission prompt (the user approved it; exact prompt was not observed). It did
not return a diagnostic report, so no claim about session state follows. No
Create/Restore/DestroySession request was implemented or sent by the probe.

Version0.0.7 adds static failure-stage labels (connection setup, metadata,
authentication, existing-session query, reply parsing). Only protocol service
hash/method may accompany unsupported-callback labels; no payload or private
identifier is included. Underlying localized error strings are not printed.
Only the explicit diagnostics mode uses these labels; ordinary discovery is
unchanged.25 targeted checks pass, including malformed metadata and a callback
at query time. No new RPC is introduced by this diagnostic refinement.

Version0.0.7 live result: Unexpected data format during authentication. The
session-query stage had not started. The metadata reader had imposed desktop
schema field types on optional game-logon fields; those assumptions were not
verified. It did not return a report or modify saved login data.

Version0.0.8 observes optional metadata instead: neutral field2/3/5 presence
flags and at most64 sorted field-number/type-category labels (numeric or
length-delimited). No field values, byte lengths, repetition counts, identifiers
or secrets are included. Desktop names in the UI are explicitly hints, not
assertions about the game reply. An unknown optional boolean is unknown, not
an authentication failure. Required owner/status/frame checks remain strict.
25 native/probe checks pass after the change, including a variant-metadata
fixture. The wire request remains GetSessionState only; no session mutation.

Version0.0.8 live result: authentication and metadata observation completed.
Bindless acceptance was not reported; a connection identity field was present.
Logon fields1/6 were numeric and2/3/4/5/7 length-delimited. No values or repetition
counts were captured. GetSessionState returned correlated status7
(ERROR_INVALID_ARGS); session existence remains unknown. Presence/categories
alone do not validate semantic names or justify assuming a session key/BattleTag.

The optional metadata fix also avoids using a singular getter on fields that
may be repeated (the desktop schema labels logon game_account2 repeated).
The failure of v6/v7 therefore is not evidence that the server uses a different
schema. It was an instrumentation assumption, not proof of failed credentials.
