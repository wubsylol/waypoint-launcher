# Experimental Friends window

Branch: `experiment/friends-panel`. Mainline and the installed live app are unchanged.
Based on personal mainline 748e79f plus the separately saved social experiment.

The Friends toolbar button beside Account opens one reusable AppKit window.
The library does not change size. The window has search, online/away/busy rows,
game/activity subtitles, a collapsible offline group, a separate unavailable
status group, and manual refresh with an explicit snapshot time/partial label.
Monograms and status dots are local drawing, not guessed Blizzard friend avatars.
Unknown public game codes remain marked as other titles. No messaging controls.

Opening the window makes no social request. Refresh explicitly uses the saved
Americas WoW login to obtain a temporary owner-verified App credential, then the
verified App session lifecycle and fresh friends/presence query. No replacement
login, typing/read receipt, message, presence publication or subscription is sent.
Close Blizzard games and the official launcher on all devices before refreshing.
Only local conflicting processes can be checked by the app.

Rows stay in memory and are cleared on account change. Previous rows remain
explicitly dated while refreshing or on a normal connection failure. Nothing is
logged, exported or persisted. Core returns private rows only after verified
Destroy acknowledgment and matching callback. Unconfirmed cleanup locks further
refreshes for that run and shows a warning, including after account changes.
Safe pre-creation refusal is shown separately. Normal quit waits for refresh;
closing the Friends window allows the bounded cleanup to finish.

Friends refresh shares the existing sign-in/launch busy state. Updates/downloads
can continue. Visible Friends counts for Dock visibility without causing Settings
notification/login-service reads. The bundle ID remains io.wubs.waypoint-review.
Friends has its own frame key; the library retains its existing frame key.

## Verification

- Independent source review covered mainline merge, shared sign-in/profile/platform
  preservation, lifecycle safety, account changes, normal quit and Dock policy.
- 394 core tests passed, including native profile/cross-game credentials and social
  identity, bounded sampling, malformed replies and cleanup-gated private rows.
- AppKit build passes. Fictional debug preview verified toolbar -> separate window,
  top-aligned untruncated rows, search by game, offline expansion and close/reopen.
- `--friends-demo` is debug-only and prevents social refresh. Normal builds do not
  populate fictional friends. No real friend list was captured during visual QA.
- Prior local viewer: user confirmed statuses and games look correct. Integrated
  window live refresh has not yet been validated; snapshot coverage, continuous
  updates, reconnect/coexistence and messaging remain unverified.

The bundled experimental build is ad-hoc signed, Apple silicon only, with no
self-update feed. It is separate from ~/Applications/Waypoint.app and retains the
live build's resource/runtime descriptors. It is a debug test build, not a release.
