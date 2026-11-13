# Development feature: WoW account picker

Branch: `investigate/silent-account-discovery`. No upstream PR submitted.

## Behavior

- Right-click an installed native WoW title (or use More) and choose **Select account…**.
- The saved WoW game authorization is used for native game-service discovery. No account portal is loaded and no second website login is requested. The owner is verified at logon and for every resolved licence name.
- The picker displays the native service's WoW licence names for the selected region. It does not receive subscription status. It does not claim a licence has access to a particular edition; Blizzard's game servers enforce entitlement.
- **Use account** remembers the choice for Battle.net owner + product/edition UID + play region. Cancelling preserves the old choice. The context menu shows the remembered name.
- Play uses the remembered choice; if none exists, it presents the picker before launching. It writes the selected licence name to `Launch Options/WoW/GAME_ACCOUNT` together with the owner-matched token, region and locale.
- Changing Battle.net identity or region cannot reuse a choice from another scope. Signing out forgets that owner's choices. A saved choice may become obsolete on the server; use Select account to refresh/change it if the game rejects it.
- The toolbar install '+' is removed. Available Games and the empty-library Install a Game button still provide installation. Available Games is the public installation catalog, not a verified account entitlement list.

## Limits

The user verified the native picker and launch handoff in Forever on 2026-11-13: selecting licence A, changing to B, and changing back to A each reached the correct account in-game. This confirms real distinct-licence selection for the tested setup; the user also confirmed that quitting/reopening Waypoint retained the Forever selection and launched the correct account without another login. The user then selected different licences for Retail and Forever and confirmed each title reached its own selected account.

Only native WoW account selection is implemented. The native backend currently supports Americas only, the region verified live. Other regions are explicitly unsupported until tested. Unrelated titles keep their original launch behavior. Discovery uses an independently implemented native TLS/protobuf exchange and may need revision if Blizzard changes its protocol. It checks for library-known open WoW clients before every attempt, including Retry. Unknown external installations cannot be guarded reliably. Saved names/IDs are local account preferences, never logged by this feature. No game data, installations or subscriptions are changed by discovery/selection itself; actual Play updates normal launch preferences.

The existing startup handoff guard now reserves the signing phase before the first await and blocks other launches during the launching phase. Its four-second startup wait is not proof that the client has consumed shared launch preferences. Avoid simultaneous independent launchers/startups during live validation.

## Validation

33 selected tests passed, covering the bounded protobuf codec, existing native/Windows launch planning and handoff helpers, licence parsing, owner/edition/region isolation, replacement, preference reload, sign-out cleanup and encrypted token/account/region handoff in an isolated preference domain. Test code does not write real net.battle login values.

Independent review covered protocol parity, owner verification, cancellation/time limits, UI cancellation and retry races. No game-content or credential migration is introduced. Both the standalone diagnostic and exact Swift backend completed owner-verified discovery against Blizzard. The integrated native picker then loaded the list in the development app without a portal or another login. The toolbar has no redundant '+'.

The development app built and passed deep signature verification. The earlier external-folder startup stall was a macOS permission prompt, not evidence of a broken drive. Distinct-licence launches passed the user-confirmed A → B → A test. Remembered choice after restart also passed without another login. Independent Retail/Forever choices also passed. Cancel acceptance also passed: highlighting a different licence and cancelling preserved the saved choice on the next Forever launch. Connection-failure recovery still requires live acceptance; see [acceptance-tests.md](acceptance-tests.md).

## Live test

1. Close WoW and the official launcher/Agent. Open the updated review build.
2. Verify that the toolbar has no '+', and that Available Games still expands.
3. Right-click Forever, Select account, choose a known licence and Use account.
4. Reopen the picker and restart the review app to confirm that the same choice is selected. Cancel should leave it intact.
5. Launch Forever and confirm the expected licence/character list. Close the game, select a second licence, relaunch and confirm that its character list changes accordingly.
6. Set Retail independently and confirm its remembered choice does not overwrite Forever's preference. The single shared launch field will intentionally reflect whichever title was most recently launched.

Do not post real account names/IDs, cookies or game tickets in a PR or test fixture. Record only success/failure and the scenario.
