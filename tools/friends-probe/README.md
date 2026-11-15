# Battle.net friends experiment

Current mode: version0.0.18, opt-in local BattleTag viewer. Refresh Friends
uses the version16 backend with the schema’s fetch_names option enabled.
Names remain hidden until Show Friends;
no list is exported or saved. The previous count-only live result returned45
records. Name correctness/completeness remains user-verified only; presence and
messaging are untested. Older modes below are historical. Temporary credential
issuance means this is not an entirely read-only RPC sequence.

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

## Connection identity header control (version0.0.9)

Explicit includeConnectionIdentity=true reads only current ConnectResponse9 as
a bounded512-byte nonemptyUTF8/no-control string. It stays private in memory.
Only the existing-session query gets Header.client_id13; connection/authentication
packets, raw query method5, hash/body and cleanup are unchanged. No identifier is
guessed and no application session is created/restored by a request. Default is
false; missing/malformed CID stops before authentication/query in this mode.

The mapping of ConnectResponse.ciid to Header.client_id is a hypothesis, not an
established SDK behavior. The DTO/UI exposes only a boolean that it was included.
27 targeted checks pass, including header-only parity and a missing-ID stop.
No other call kind receives this header. Live result recorded separately.

Version0.0.9 live result: identity field was present and included in the query
header; the correlated GetSessionState status remained7. Session existence is
still unknown. This rules out that particular session-query-header control as
a fix, not Header.client_id for every social method. Authentication completed;
no new session-creation/restoration/destruction request was sent.

## Direct friends identity-header control (version0.0.10)

The existing-session query stayed7 with or without CIID. That did not test
whether the same header affects friends routing. Version10 therefore selects
raw v2 GetFriends method5/hash0x5869BE8C with explicitincludeConnectionIdentity.
Only Header.client_id13 carries the bounded server-provided current connection
identity. Connect/auth packets, initial body and raw method remain identical.
No session query, creation, restoration, subscription or mutation is requested
by this UI mode. Defaults remain without header. Names, if returned, appear only
in the local UI; CID and raw friend IDs are not displayed. One bounded lookup
allows the existing page/count/deadline limits, with immediate stop on refusal.

28 targeted checks pass, including full packet parity for original v2 with
and without the header. The mapping remains a hypothesis. Result follows.

Version0.0.10 live result: the window and the user confirmed owner-verified
sign-in followed by correlated GetFriends status3025 with the identity header.
No list returned. Adding current connection identity is therefore not sufficient
for the tested social route. It does not show that Header.client_id is never
used or that no other authorized service exists.

Pause additional live parameter variants here. Current flags and CIID-header
controls did not restore social access; proper SDK session setup/routing and
social authorization need further implementation/evidence. Do not turn the next
step into an unattended CreateSession request. No explicit Create/Restore/
DestroySession request, messaging or friendship mutation was tested in this
round. The user-approved system Keychain prompt was not visually inspected;
the probe itself has no password-entry form and only reads the existing item.

## Authentication logical-client inspection (version0.0.11)

SDK descriptors mark authentication, friends and session services use_client_id.
The transport CIID is not established as the logical authentication client ID.
Before any CreateSession experiment, this mode inspects whether successful
correlated authentication replies and owner-verified logon notifications carry
Header.client_id13. It reports only presence and optional equality of two
bounded nonempty length-delimited values. Neither actual ID leaves the backend.
No request is sent after authentication; no header is added to Connect/Logon.
No friends/subscription/session query or creation/restoration/mutation occurs.

30 targeted checks pass: cases cover absent/equal/different IDs, owner refusal
and exact two-request Connect/Logon lifetime. The user confirmed all WoW clients
closed on both Macs before the live test. Other downloads remain untouched.

Version0.0.11 live result: connection identity field present, immediate auth
reply Header.client_id absent, owner-verified logon notification Header.client_id
present. Comparison is unknown because only one auth header supplied the field.
No values were displayed, logged or persisted. Exactly connection/authentication
was requested, with no post-auth RPC. This reveals a distinct source to test:
the authenticated callback header, not transport ConnectResponse.ciid.

## Owner-verified logon context control (version0.0.12)

Version11 found Header.client_id on the owner-verified LogonComplete callback.
This explicit mode uses that bounded nonemptyUTF8/no-control identifier on raw
v2 GetFriends method5, rather than transport CIID. No change to Connect/Logon,
hash, initial body or normal defaults. A missing ID prevents any friends RPC;
there is no fallback to the immediate auth response, CIID or invented values.
If a correlated friends reply includes Header.client_id it must match. Replies
without it still rely on authenticatedTLS and request-token correlation, not an
independently present context header. Only friends requests get this identity.

No session creation/query/subscription, presence update or message send is
implemented by this mode. Lookup pagination retains existing bounds.33 targeted
checks pass, including correct context vs transport, missing context and wrong
reply context. Actual ID never leaves the backend or appears in a log/UI.

Version0.0.12 live result: successful authentication followed by correlated
friends status3025 using the owner-verified logon callback's Header.client_id.
The user reported the exact status and it was verified in the version12 window.
No friends were returned. A client-context source alone is not sufficient for
this route. No application-session creation request was made. UI inspection
stalled during the attempt; the user supplied the final status, and no duplicate
lookup was initiated while awaiting it.

## Authenticated-context session preflight (version0.0.13)

Before considering session creation, this mode queries existing session state
using the owner-verified logon Header.client_id rather than transport CIID.
Only rawGetSessionState method5/hash0x7B37D770/emptybody is sent after login.
No creation, restoration, destruction, friends or subscription call. Replies
with a context header must match; returned session owner must match. Refusal
leaves existence unknown and is not permission to replace another session.
Defaultfalse preserves older diagnostics. Mixed context sources fail before
network.34 targeted checks pass; the new fixture asserts exact3requests and
correct actualauthcontext vs transport ID, owner-check and closure behavior.

Version0.0.13 live result: correlated GetSessionState status7 using the actual
owner-verified logon client context. Session identity/existence remained unknown.
The user reported the result and it was verified in the version13 window. No
session creation/restoration/destruction request or friends call was sent.

## Parked at the user's request

On2026-11-14 the user asked to preserve this as a side project and return to the
mainline client. Stop live work here. See docs/social-service/PARKED.md for the
restart boundary. No CreateSession experiment was implemented or run. Do not
merge this experimental branch into main as part of returning to the client.

## Application credential issuance preflight (version 0.0.14)

Resumed 2026-11-15. This mode changes the current UI from the historical session
query to a credential-issuance experiment; it is not a read-only RPC. It first
performs the existing owner-verified WoW authentication, then sends v2
AuthenticationService.GenerateAuthToken (original hash 0xc02f8216, method 3)
with title_id 0x417070 (`App`). The credential is bounded, parsed, owner-checked
and discarded in the backend. It never reaches the UI, Keychain or filesystem.
No App login, friends request, Create/Restore/DestroySession, presence update or
friendship/message mutation follows. Saved authorization/preferences are not
written. Normal authentication/token issuance can have server-side effects.

Provenance: the method and request/response fields appear in the preserved
client-17987 metadata and the personal mainline already uses this v2 method
for cross-game credentials. `App` is historical desktop program evidence from
[EionRobb/purple-battlenet](https://github.com/EionRobb/purple-battlenet/blob/d2113e28cdad24317e34886c50e8a6fceaeff53d/libbattlenet.c);
its numeric FourCC and current acceptance are a hypothesis, not a supported
third-party desktop entitlement. No GPL implementation is imported and no old
user agent/version/device identifier is copied.

A matching-owner credential response would establish issuance for the request,
not actual title scope, desktop authentication or social permission. Refusal
is labeled separately from authentication. No automatic retry is made.

34 native/probe tests pass, including exact three-request lifetime, fixed title
and method, invalid/oversized/wrong-owner returned credentials and wrong owner
before issuance. Existing native transport/discovery/social checks also pass.
Independent review found no blocking issues; the UI title was corrected to avoid
calling issuance read-only. Explicit confirmation that Blizzard games on both
Macs are closed is required before the live attempt; the local process check
only detects WoW. Live result is recorded separately after testing.

## Application authentication-only control (version 0.0.15)

After the version-14 matching-owner issuance result, this control requests a
fresh App credential and closes the source WoW connection. A separate native
client then sends only Connect and Logon for title 0x417070 (App), platform Mc64,
using the current Americas `bna` build from Blizzard's public versions service.
The resulting logon must match the expected owner. The temporary credential is
kept only in backend memory; both connections are closed. No social, licence,
session creation/restoration/destruction or presence request follows. No saved
login is replaced and there is no automatic fallback/retry/browser login.

App acceptance of this title/platform/version combination is experimental.
A refusal does not prove which parameter or permission is missing. A successful
owner-verified login would establish acceptance of this control only, not friends
rights, official-client parity, session coexistence or app-session lifecycle.
Target-refusal/owner/unavailable errors are distinct from source auth/issuance.

39 native/probe tests pass, including exact source3/target2 request lifetime,
fresh credential and App build/title on wire, source owner failure before target,
target owner rejection, target refusal stage and production-like cancellation.
Independent review's cancellation-classification finding was fixed before live
testing: task cancellation is checked before mapping a cancelled network read
to an authentication failure. Live outcome recorded separately.

## Application-authenticated friends control (version 0.0.16)

After owner-verified App authentication succeeded in version15, this mode adds
raw v2 GetFriends method5 with the owner-verified App logon callback client ID.
It requests a fresh temporary credential each run, closes the WoW source before
App login, verifies the target owner and requires a valid authenticated context
before sending the social read. Missing context stops without a social request;
there is no CIID/legacy/flag fallback. Returned context headers must match.

This is one bounded lookup attempt: existing limits remain20 pages/1000 records
and35 seconds per native connection. Refusal stops immediately. No session
lifecycle, subscription, message, friendship/presence change or persistent write
is added. Diagnostic UI displays only count, never friend names or IDs. A
successful empty response would establish RPC acceptance, not expected nonempty
list correctness, real-time updates or chat support.

42 native/probe checks pass, including new exact App title/fresh-token/context
wire assertions, missing-context stop and refusal-stage checks. Independent
review found no blockers. Live result recorded separately.

## Local BattleTag viewer (version 0.0.17)

Backend unchanged from version16. Refresh Friends requests a new bounded
application-authenticated snapshot, with all earlier live-test boundaries.
A successful fetch initially shows only its count. Show Friends reveals a local
AppKit table; Hide Friends conceals it again. Filtering is local and sends no
network request. No online status or messaging capability is implied.

The UI retains BattleTag strings only (or a numbered missing-tag placeholder),
not raw friend IDs, real names, notes or attributes. Nothing is exported or
written to preferences/logs. Refresh/Cancel clear the snapshot. Account owner is
rechecked on reveal, filtering and app activation; a different selected account
clears it. The snapshot is labeled with its owning account. Quit closes the
process and its in-memory state. A cancelled network task cannot repopulate it.

The operator should not inspect the UI after Show Friends is clicked: the user
can confirm names/completeness locally without including a friends list in a
transcript. Ask only whether the expected friends appear and whether any
BattleTag placeholders remain. The existing42 backend checks remain the latest
network/parser tests; this UI-only change is built and independently reviewed.

## Explicit names option (version 0.0.18)

User's version17 result: all entries showed BattleTag unavailable. Saved client
metadata defines GetFriendsRequest.options1 -> GetFriendsOptions.fetch_names1
(bool). Version18 enables that option on every application-context lookup page.
All other App credential/auth/context routing, bounds and cleanup are unchanged.
The public WoW/default control continues to omit the option.

This is a general names option; a server may return full_name too. Only friend
ID and BattleTag reach the core result; full_name4 and attributes5 are discarded.
The opt-in local viewer still retains only BattleTag/numbered placeholder strings,
with no names/IDs exported or logged.43 targeted tests pass, including options
on initial/continuation pages and a synthetic private-real-name/attribute fixture
that is discarded. Independent review found no blockers. Live fix unverified.
