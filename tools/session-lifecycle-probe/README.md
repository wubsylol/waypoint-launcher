# Explicit App session lifecycle test — not run without user consent

This is a consequential experiment, separate from the working read-only friends
viewer and live Waypoint. Build with tools/session-lifecycle-probe/build.sh.
Building/opening the UI performs no authentication. Do not click its create
button until the user explicitly agrees to this concrete test and confirms all
Blizzard games and official Battle.net launchers closed on both Macs.

## Single-attempt plan

1. Read selected owner and saved WoW token, fetch public game/desktop builds.
2. Owner-verified WoW authentication and fresh App token issuance; close source.
3. Owner-verified App login. Require exactly one explicit Americas App handle
   from this login and a bounded authenticated callback context.
4. CreateSession (0x7b37d770, method1) with only that canonical App handle in
   request.game_account1. No hardware fingerprint, invented ID or game licence.
5. Validate creation response and SessionCreated callback: owner, App handle,
   region, instance and any callback context. Support callback-before-reply and
   reply-before-callback. Never expose identifiers/session keys.
6. Once both agree, send only DestroySession method3, empty body, with the SAME
   authenticated App context. Do not substitute the returned session instance
   string as a routing ID. Report its equality with the auth context as a
   boolean only; the mapping remains an experimental observation.
7. Report creation/cleanup acknowledgments separately, then close connection.

There are no friends/presence queries, subscriptions, presence updates,
heartbeat loops, messaging, saved-login/preference writes or automatic retry/
reconnect. One attempt per process. The local guard checks WoW and official
Battle.net process names only; it cannot confirm every client on both machines.
Waypoint downloads are not stopped by this test.

## Ownership and failure boundary

Destruction is attempted only for a validated creation response in the same
still-open, noncancelled context, with no identity/parse conflict. Outgoing
context is rechecked before every lifecycle call; unexpected repeated logon
completion is refused. Malformed/foreign callback context, changed identity,
owner mismatch and codec failures invalidate cleanup eligibility. A refusal
before verified creation does not trigger destruction. A destruction failure
never triggers a second attempt.

The test cannot guarantee server cleanup if interrupted, timed out, refused,
disconnected or unable to validate the returned identity. It reports cleanup
unconfirmed rather than reconnecting to target a guessed session. A successful
Destroy RPC acknowledgment is reported separately from an observed matching
SessionDestroyed callback; it is not a general guarantee about other sessions.
Stop/close during a running test cancels the connection and keeps the outcome
visible. Force quit/crash can prevent even that report from being shown.

Creating the App session may affect another client or visible availability.
Static client analysis does not prove coexistence or replacement semantics.
A successful create/destroy cycle would establish this lifecycle control only,
not that it resolves presence, is production-safe, or supports background chat.

## Provenance

See docs/social-service/DESKTOP-LIFECYCLE-17986.md. The desktop CreateSession path
populates a GameAccountHandle. Create and destroy wrappers obtain their SDK
identity string through the same accessor (0x739e70, called at0x73cd17 and
0x73d234). This supports same-context dispatch, not server-side safety proof.

Known static BGSServiceOptions.descriptor_name fields, not inferred bgs package
names, establish original hashes by FNV1a:

- bnet.protocol.friends.v2.client.FriendsService → 0x5869be8c (crosscheck)
- bnet.protocol.session.v2.client.SessionService → 0x7b37d770
- bnet.protocol.session.v2.client.SessionListener → 0xbca72135

Public17986 embedded descriptor offsets: session_service.proto0x23d0ca0;
session_listener.proto0x23d04ec. Only the known descriptor_name1 string inside
service options90000 was decoded, constrained to protocol-style identifiers.
No raw descriptors/binary/private values are included in this repository.

61 targeted native/probe tests pass. Lifecycle-specific cases cover both
callback orders; exact own-handle/context Create/Destroy-only wire dispatch;
missing/ambiguous handles; foreign owner/handle/region/instance; missing/malformed
callback context; changed auth identity; creation refusal; no destruction after
identity conflicts; and interrupted cleanup with no reconnection. Independent
review found and then verified the identity-conflict cleanup fix. Earlier
friends/presence/auth controls remain passing. Live lifecycle test NOT RUN.
