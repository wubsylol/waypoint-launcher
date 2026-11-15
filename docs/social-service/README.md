# Social experiment handoff

Preserved for review on `experiment/friends-panel`; protocol investigation and
standalone probes are also saved on `experiment/battlenet-friends`.
Personal `main` is unchanged. No upstream submission is made by this handoff.

## Working results

- Saved WoW authorization can obtain a same-owner temporary App credential.
- App authentication permits friends lookup; `fetch_names` supplies BattleTags.
- A bounded App-session create/destroy cycle verifies owner, binding, context,
  acknowledgment and matching lifecycle callbacks.
- Account presence fields20/21/22/25 provide online game handles, selected game,
  selected status and rich presence. The user validated the local status/game
  display. Identifiers and raw protocol data are not shown or persisted.
- Integrated AppKit Friends pop-out: toolbar button beside Account, search,
  online/offline/unavailable sections, game-first sorting, client-label suppression,
  catalog backgrounds and right-side game icons. Status remains in dots/tooltips
  and accessibility labels. BSAp is the Battle.net mobile app.

## Source-only final change

Refresh-on-open is compiled and independently source-reviewed, but has NOT been
live-tested, packaged or deployed. The last built test app, friends.2, still uses
manual refresh. The source preserves the refresh button, busy/session-cleanup
locks and local native/Wine game checks. Detection cannot cover other machines
or unknown installations. No additional Blizzard connection was made to save it.

## Validation and boundaries

394 core tests passed at integration; 84 targeted checks passed after game-first
sorting/artwork work. The final refresh-on-open change builds successfully.
Visual checks used fictional friends. The earlier viewer's real-list statuses and
games were confirmed by the user; integrated coverage/coexistence/reconnection and
continuous presence updates are not fully validated. No messaging, message-history,
read-receipt, typing-indicator or presence-publication implementation was added.

The user returned to the official launcher over account-safety concerns. Further
live testing/deployment is stopped. Functional success is not evidence of Blizzard
approval or account safety. Saved authorization is never replaced by the probes.
No credentials, real friend lists or activity dumps are part of this handoff.

## Where to start

- [Friends window behavior and validation](FRIENDS-WINDOW.md)
- [Live control results and static evidence](LIVE-CONTROLS.md)
- [Desktop lifecycle analysis](DESKTOP-LIFECYCLE-17986.md)
- [Historical investigation](INVESTIGATION.md)
- [Isolated lifecycle/presence probe](../../tools/session-lifecycle-probe/README.md)
- UI: `Sources/Waypoint/FriendsViewController.swift`
- Authentication/session coordinator: `Sources/WaypointCore/NativeGameAccounts.swift`
- Presence decoding/presentation: `Sources/WaypointCore/PresenceDiagnostics.swift`
- Lifecycle identity/cleanup model: `Sources/WaypointCore/ApplicationSessionLifecycle.swift`

Do not assume diagnostic descriptor names establish server permission. Preserve
owner/context verification, bounded parsing and explicit cleanup outcomes when
adapting this work. Mainline game authentication, profile lookup and cross-game
credential flows were retained when main was merged into the UI experiment.
