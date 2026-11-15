# Friends investigation resumed — 2026-11-15

User requested returning to the parked friends-list project. Worktree restored on `experiment/battlenet-friends`; personal mainline remains separate at release 1.2.16. No authentication, Keychain retrieval, session API or social RPC was run in this resumption pass.

## Revalidated starting point

The preserved source authenticates specifically as WoW title 5730135 with the saved WoW ticket. The prior correlated refusals remain the last live evidence: friends 3025; flagged-method control 3011; session-state query 7. Header/context variants did not resolve them. No claim of functional friends access.

All nine offline protocol-inspector tests pass again. The original static metadata is retained with its binary hash; this is historical client-schema evidence, not a current server contract.

## Session gate

Inspection of the saved descriptors confirms:

- CreateSessionRequest: optional game_account and CreateOptions.
- CreateOptions: mac_address only; no documented nonreplacement option in this schema.
- DestroySessionRequest: no fields. There is no explicit target session ID in its body.
- SessionId includes owner, game-account, instance and region; creation has both response and listener paths.

Therefore an ownership-checked CreateSession/DestroySession implementation alone does not establish safe coexistence. Do not infer that an empty destroy body targets only a probe-created session, or that an empty creation request cannot replace an existing game session. Client-context semantics, callback ordering and cancellation/cleanup behavior require evidence first.

## Next research target

Trace the desktop application's application-login/session lifecycle and social service authorization before another live control. Keep application identity, game identity, request routing and developer OAuth scopes distinct. A successful game login is not proof of social authorization, and another title's public implementation is not proof of the desktop service behavior.

A newly inspected public reference, ncarrillo/Superiority, contains separate SC2 friends/session schemas and chat-session bootstrapping. The examined SC2 code does not establish a fix for our modern desktop/WoW endpoint, so no implementation is imported and it is not treated as successful evidence for this route.

Before any future live authentication/session experiment, confirm Blizzard games are closed on both Macs. Keep saved launcher credentials unchanged and avoid automatic retries, friendship mutations, presence updates or messaging. No new test app is ready from this pass.
