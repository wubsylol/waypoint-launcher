# Development feature: WoW account picker

Branch: `feature/game-account-selection`. No upstream PR submitted.

## Behavior

- Right-click an installed native WoW title (or use More) and choose **Select account…**.
- The existing Battle.net identity's web session is used to read Blizzard's WoW licence list. An account-page sign-in may be needed. The endpoint's authenticated owner must match the requested Battle.net identity before and after reading the list.
- The picker displays that region's WoW licence names and server-reported status. It does not claim a licence has access to a particular edition; Blizzard's game servers enforce entitlement.
- **Use account** remembers the choice for Battle.net owner + product/edition UID + play region. Cancelling preserves the old choice. The context menu shows the remembered name.
- Play uses the remembered choice; if none exists, it presents the picker before launching. It writes the selected licence name to `Launch Options/WoW/GAME_ACCOUNT` together with the owner-matched token, region and locale.
- Changing Battle.net identity or region cannot reuse a choice from another scope. Signing out forgets that owner's choices. A saved choice may become obsolete on the server; use Select account to refresh/change it if the game rejects it.
- The toolbar install '+' is removed. Available Games and the empty-library Install a Game button still provide installation. Available Games is the public installation catalog, not a verified account entitlement list.

## Limits

The new selector handoff has not yet been verified by launching two distinct real licences from this build. Prior investigation found an existing GAME_ACCOUNT matching a discovered licence name, which supports this implementation but is not a substitute for the two-account test.

Only native WoW account selection is implemented. The China account-service flow is explicitly unsupported. Unrelated titles keep their original launch behavior. Discovery uses a private website API and may need revision if Blizzard changes its schema. Saved names/IDs are local account preferences, never logged by this feature. No game data, installations or subscriptions are changed by discovery/selection itself; actual Play updates normal launch preferences.

The existing startup handoff guard now reserves the signing phase before the first await and blocks other launches during the launching phase. Its four-second startup wait is not proof that the client has consumed shared launch preferences. Avoid simultaneous independent launchers/startups during live validation.

## Validation

29 selected tests passed, covering existing native/Windows launch planning and handoff helpers, licence parsing, owner/edition/region isolation, replacement, persistence across preference reload, sign-out cleanup and encrypted token/account/region handoff in an isolated preference domain. Test code does not write real net.battle login values.

Independent review findings addressed: reserve the launch phase before suspending, block overlapping startup handoffs, reject unsafe ID types before coercion, restore the full-size web view for refresh, and isolate preference-domain tests.

The development bundle built and passed deep signature verification. Live UI checking encountered a startup stall while the app was enumerating the external game folder; this is being investigated separately. Account picker layout, live discovery inside the integrated window, remembered selection after restart, toolbar removal in the live UI and actual selected-account game login still require verification.

## Live test

1. Close WoW and the official launcher/Agent. Open the updated review build.
2. Verify that the toolbar has no '+', and that Available Games still expands.
3. Right-click Forever, Select account, choose a known licence and Use account.
4. Reopen the picker and restart the review app to confirm that the same choice is selected. Cancel should leave it intact.
5. Launch Forever and confirm the expected licence/character list. Close the game, select a second licence, relaunch and confirm that its character list changes accordingly.
6. Set Retail independently and confirm its remembered choice does not overwrite Forever's preference. The single shared launch field will intentionally reflect whichever title was most recently launched.

Do not post real account names/IDs, cookies or game tickets in a PR or test fixture. Record only success/failure and the scenario.
