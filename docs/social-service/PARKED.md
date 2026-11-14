# Parked Battle.net social prototype

Parked2026-11-14 at the user’s request. Resume only on a new user request.

Source branch: `experiment/battlenet-friends` in `wubsylol/waypoint-launcher`.
Stable mainline remains commit `19e1bcb` (personal release1.2.2-wubs.1).
Do not merge this prototype into main or continue live attempts automatically.

## Last state

- Existing saved WoW authorization authenticates with owner verification.
- Friends methods remain refused with3025, including the actual owner-verified
  logon client context. No working friends-list feature is claimed.
- Copying the SDK method flag onto the wire returned3011 INVALID_METHOD.
- GetSessionState returned7 INVALID_ARGS, with no header, transport identity,
  and finally the owner-verified logical client context. Session existence is
  unknown, not confirmed absent.
- The logon notification includes Header.client_id while the immediate auth
  reply does not. Actual values remain private in backend memory.
- The latest probe is version0.0.13, an authenticated-context session preflight.
-34 targeted native/probe checks pass; the offline inspector has9 checks.
- Changes had independent code review. Findings/provenance are in
  INVESTIGATION.md, LIVE-CONTROLS.md and tools/friends-probe/README.md.

## Explicit boundary

No CreateSession/RestoreSession/DestroySession/MarkSessionAlive experiment was
implemented or executed. A selected-licence lifecycle/cleanup design was being
considered when the user stopped the investigation; it is not functional code
or an approved unattended next step. Establish the correct SDK lifecycle and
cleanup/ownership rules before any future session-creation test, and confirm
that relevant game clients are closed. Other-Mac downloads were left alone.

No messages, friend changes, presence updates, history retrieval or typing/read
signals were requested. No saved login, game-account choice or install path was
changed by the prototype. A user-approved likely Keychain permission prompt was
not visually verified; the probe contains no password-entry form.

The next return to this work should begin with the reports and current source,
not another retry of the disabled methods. Keep its SDK/protocol assumptions
separate from stable launcher work and do not export tokens or private profiles.
