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
