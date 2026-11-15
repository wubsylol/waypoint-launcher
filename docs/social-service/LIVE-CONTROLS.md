# Read-only social controls — 2026-11-14

User confirmed WoW was closed before testing. All work remains on
`experiment/battlenet-friends`; `main` is untouched. No other Waypoint/download
process was stopped or modified. Probe app processes alone were restarted.

| Probe | Controlled difference | Observed result |
| --- | --- | --- |
| 5 | Modern GetFriends method0x40000005 instead of5; auth/hash/body unchanged | Authentication succeeds; matching friends response3011 INVALID_METHOD |
| 6 | Inspect optional metadata and query existing session state | Generic failure; no usable report |
| 7 | Classify failure stages with no new request | Format failure during authentication; optional metadata assumptions too strict |
| 8 | Observe optional fields/categories rather than treating them as singular desktop types | Authentication succeeds; existing-session query7 INVALID_ARGS |
| 9 | Include server-provided connection identity in session-query Header.client_id13 | Identity included; session query still7 |
| 10 | Include same kind of identity header in original raw GetFriends method5 | Authentication succeeds; friends response still3025 METHOD_DISABLED |

Probe5 was briefly reported as3025 by the user, then corrected to3011; the
current version5 window was independently observed as3011. Results are not
combined across versions. Probe10 was already running when its window was
inspected, so no second lookup was triggered. It was observed and confirmed by
the user as3025. No friends or connection identifiers were captured in this log.

## Metadata observations, not values

The server did not explicitly report bindless acceptance. A connection identity
field was present. Logon fields1/6 were numeric and2/3/4/5/7 length-delimited.
No values, lengths or repetition counts were recorded. In particular, the
presence of field3 is not sufficient to claim it is a valid BattleTag, nor does
field5 presence establish the semantics of a session key.

The optional reader initially used a singular getter on metadata that can be
repeated (desktop schema game_account2 is repeated). That diagnostic bug must
not be interpreted as failed credentials or a demonstrated server-schema
incompatibility. Required owner/status/framing checks stayed strict throughout.

Status7 on the session query leaves session existence unknown. It does not
prove no sessions are active or identify which argument/lifecycle step is
missing. CIID-to-header-client_id was a hypothesis; its lack of effect does not
justify inventing another identifier or replacing an existing session.

## Keychain prompt

UI inspection timed out during the version6 attempt. The user reported entering
credentials and choosing Always Allow without reading the prompt. Its exact
text was not observed, so it is recorded as likely rather than verified system
Keychain permission. The test app contains no password input and its only
credential retrieval path is the existing Keychain token read. Afterward the
probe was responsive and showed its failure status. No passwords, tokens or
private identifiers were requested in chat, printed or written by the probe.

## What remains open

The current owner-verified game logon does not provide friends access through
the tested calls. This is narrower than proving that Battle.net social cannot
be implemented, or that a separate application login will definitely fix it.

Before more live attempts, investigate and implement the proper SDK application
session lifecycle and social rights. Distinguish connection/authentication from
registered application/game sessions, validate callback identity and lifetime,
and design cleanup/coexistence before any CreateSession experiment. Creating a
session may affect another client; do not do it as an unannounced fallback.
No explicit CreateSession/RestoreSession/DestroySession/MarkSessionAlive request
was sent in this test round. No messages, friend mutations, presence updates,
message history or typing/read signals were requested. Normal authentication
may itself have server-side effects; those are not ruled out by this log.

## Validation

28 targeted native/probe checks pass after these changes. Packet parity tests
prove only the intended header/method control changes, and test owner mismatch,
refused queries, unknown-session reporting, variant metadata and cancellation.
Each source change received independent review before its live control. The
probe bundle builds and passes strict ad-hoc signature verification. These are
experimental checks, not Windows gameplay or social-feature acceptance.

## Application credential issuance — version 0.0.14 (2026-11-15)

User confirmed all Blizzard games closed on both Macs before the test. A single
probe action was initiated. UI inspection timed out while it was pending; the
button was not clicked again. The user then reported a matching-owner
credential returned for the App request, discarded without saving. The
completed version-14 window was subsequently observed showing the same result.

This confirms issuance/owner validation for the requested App title, not actual
target scope, application authentication, session lifecycle or friends access.
No target logon, friends call or explicit session lifecycle RPC was sent.

## Application authentication — version 0.0.15 (2026-11-15)

After successful issuance, the authentication-only control requested a fresh
credential, closed the WoW source connection and performed only Connect/Logon
as App with Mc64 and the current public bna build. The user reported successful
owner-verified application authentication with both connections closed; the
completed version-15 window was subsequently observed showing the same result.

This establishes acceptance of this App authentication control, not friends
permission or explicit application-session lifecycle. No friends request,
subscription or explicit Create/Restore/DestroySession was sent in version15.

## First successful friends response — version 0.0.16 (2026-11-15)

The user started the application-authenticated friends check. When inspected,
the button was already disabled and status was pending; no additional click or
retry was sent. The completed version-16 window was observed reporting a
successful application-authenticated friends response with45 records. The user
independently reported the same result. No names or IDs were displayed/captured.
Both source and target connections closed; no saved credentials were written.

Working tested sequence: owner-verified WoW authentication → GenerateAuthToken
for App → close source → authenticate the fresh credential as App with public
bna build/Mc64 → raw v2 GetFriends5 using owner-verified logon client context →
bounded parsing → close. No explicit session lifecycle or subscription request
was needed for this lookup. This establishes successful access and45 parsed
records for the selected account, not expected friend-name correctness,
completeness against the official list, presence, live updates, messaging,
credential lifetime or game/launcher coexistence. It does not isolate which
individual application-login parameter caused earlier refusals to disappear.

Next: show the returned BattleTags only in a local opt-in viewer so the user
can validate expected friends without exporting a list. Then investigate
presence/ongoing refresh independently. Keep all social work off personal main
until explicitly promoted. Messaging, read/typing signals and friendship
mutations remain outside this read experiment.

## Local viewer — version 0.0.17 (2026-11-15)

User reported all entries displayed BattleTag unavailable. No actual friends
list or identifiers were inspected. This establishes that the current UI had
no usable BattleTag strings, not whether response field3 was absent or empty.

Offline schema review found GetFriendsRequest.options1 contains
GetFriendsOptions.fetch_names1 (bool). Previous controls omitted options and
therefore did not explicitly request names. This is a concrete missing request
field and the next controlled change; it is not yet a demonstrated live fix.

## BattleTags returned — version 0.0.18 (2026-11-15)

User reported that BattleTags now appear in the opt-in local viewer after the
fetch_names option was enabled. No friend names, raw IDs or screenshots were
requested or inspected by the operator. This confirms usable BattleTag strings
for the tested snapshot and resolves the all-placeholder version17 result.
The user did not explicitly confirm completeness or absence of every remaining
placeholder, so those remain unverified. No presence, live update, messaging or
game/official-launcher coexistence test was performed.

Working friends-snapshot baseline: temporary same-owner App credential, source
connection closure, owner-verified App authentication, authenticated callback
client context, raw GetFriends5 with options.fetch_names enabled on every page,
bounded parsing, local opt-in BattleTag display, and connection closure. No
explicit session lifecycle or social mutation was needed for this snapshot.

## Presence schema check1 (2026-11-15)

User reported: application login and friends lookup succeeded; presence query
returned7. No presence fields, status values or game/activity conclusions were
returned. No automatic retry/fallback was performed. Saved login data unchanged.
The request was the v2 Query5 control with INCLUDE_ALL_GAME_ACCOUNTS, four fixed
candidate keys and the owner-verified authenticated App client context.

Follow-up inspection: modern presence Query declares INSTANCE_ID routing, unlike
friends' BATTLE_NET_ACCOUNT routing. This may matter for app-session setup, but
does not establish that creation is required or justify inventing a client ID.
The key schema also defines optional unique_id4. The first probe omitted it;
public client update examples include explicit zero. The next isolated control
adds only unique_id=0 to the same keys, keeping other request fields and auth
unchanged. No claim is made that optional protobuf presence is server-required.

## Explicit-zero presence key control2 (2026-11-15)

User again reported successful application login/friends lookup followed by
presence status7. Encoding unique_id=0 explicitly did not resolve the refusal.
No fields/status/game activity were returned. The report does not isolate the
failing validation or establish a need for session creation.

Next read-only control: GetSessionState under App authentication, using the
fresh same-owner App credential and the App logon callback client context.
Earlier existing-session status7 controls were authenticated as WoW. Since App
authentication changed friends-service access, repeating this distinct session
query under the working App identity is useful before considering any lifecycle
mutation. No Create/Restore/DestroySession call is implemented by this control.

## Existing App-session check3 (2026-11-15)

User reported GetSessionState under App authentication returned7; owner-verified
session identity remained unknown. No Create/Restore/DestroySession request was
sent. This extends the earlier WoW-authenticated session-state refusals to the
working App identity; it does not prove absence of a session or that explicit
creation will resolve presence. Stop field-argument variations here and seek
SDK lifecycle/routing evidence before another live attempt.

## App handle check4 (2026-11-15)

User reported successful owner-verified App authentication, one Americas App
handle, and authenticated callback context present. No request followed App
login. This establishes availability of the classified own-login metadata, not
session creation rights, routing equivalence or cleanup/coexistence behavior.

A separate single-attempt lifecycle test is now prepared but NOT RUN. It binds
to the App handle from that login, verifies response/callback owner/binding,
and requests same-context destruction, with explicit unconfirmed-cleanup states.
See tools/session-lifecycle-probe/README.md. Explicit risk consent and closed
clients on both Macs are required before running it. The working friends
viewer and mainline launcher remain separate and unchanged.

## App session lifecycle test1 (2026-11-15)

After explicit consent and confirmation that Blizzard games and official launchers
were closed on both Macs, the user ran the single-attempt probe. Observed report:
creation response owner/binding verified; creation callback verified; instance
matched authentication context; Destroy request accepted; no matching destruction
callback observed; no refusal code reported. Saved login unchanged.

Source inspection confirms this version returns immediately after the Destroy RPC
acknowledgment, then closes the connection. It does not wait for a later destruction
notification. Therefore callback absence is inconclusive, rather than evidence of
server cleanup failure. The acknowledged request is verified; a matching destruction
event and final server-side state are not. Do not reconnect or blindly retry cleanup.
No presence query or message was made. Mainline remains unchanged.

## App session lifecycle observation control2 (2026-11-15)

Following fresh explicit consent and closed-client confirmation on both Macs,
the second probe ran once. The UI reported creation response owner/binding
verified, creation callback verified, instance matching authentication context,
Destroy request accepted, and matching destruction callback observed. No refusal
code was reported. Both connections closed and saved login remained unchanged.

This verifies the bounded create/acknowledge/destroy/notification cycle for this
account and connection context. It does not establish other-client coexistence,
presence authorization or messaging. No friends/presence request or message was
sent. Next investigation may evaluate presence within the verified session, with
the same identity checks and cleanup behavior, before a separately approved test.

## Presence-in-session control3 (2026-11-15)

Live single attempt: verified creation response/callback and matching context;
fresh friends lookup succeeded, presence Query5 refused3. Destroy acknowledged
and matching destruction callback verified. No sample returned or data persisted.
This differs from pre-session7 but does not prove the reason or an access grant.

Static desktop core17986 inspection identifies QueryImpl at0x71a980 using
QueryRequest constructor0x1689b50. For account entities it explicitly sets
query_behavior2 to numeric0 at0x71a9d9/0x71a9e0, sets account_id1 at0x71a9f2/
0x71a9f9, copies provided keys, and uses SDK identity getter0x739e70 at0x71ac5c.
RTTI QueryRequest at0x23cf8d6 -> typeinfo0x278adf8 -> vtable0x278abc8,
destructor0x168b4e0, validates the constructor/copy/destructor family. Our
previous sample used behavior2 INCLUDE_ALL_GAME_ACCOUNTS. Next controlled test
uses the desktop account-only behavior0, keeping session/header/keys unchanged.
This is a bounded format alignment, not an attempt to override server refusal.
