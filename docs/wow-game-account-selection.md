# Investigation: selecting game licences within a Battle.net account

Status: **discovery prototype; no production account picker and no verified launch mapping**.

Reviewed upstream baseline: `e566728c7bc213fdfb31437c1b333c9574d2e106` (2026-11-13).
Fork branch: `investigate/wow-game-account-selection`. No upstream PR submitted.

## Confirmed in Waypoint

- `Sources/WaypointCore/Accounts.swift`: `Account` identifies a Battle.net identity. `TokenVault` stores tokens per identity and game codename. Neither models individual game licences.
- `Sources/Waypoint/AccountMenu.swift`: switches those Battle.net identities. `LibraryCells.swift` builds Play As from the same list.
- `Sources/Waypoint/AppModel.swift`, `play`: resolves the identity and token, then starts the game. There is no licence discovery or selection step.
- `Sources/WaypointCore/LaunchOptions.swift`, `write`: updates WEB_TOKEN, REGION and optionally LOCALE. It never selects, clears or validates GAME_ACCOUNT. Consequently an unrelated previous launcher selection may survive. This is a code finding, not proof of how every client resolves a missing selector.
- The installed Mac WoW clients contain GAME_ACCOUNT launcher-login strings (observed in the preceding investigation). That makes this a concrete handoff field to validate; it does not establish its accepted value format.

## Confirmed from Blizzard's publicly served account website

Public page: https://account.battle.net/games

Bundle inspected: https://bnetaccount.akamaized.net/static/js/app.ef9c39c7f0f3c4404566.js

Its `MyGamesService.getGamesAndSubscriptions` performs `GET /api/games-and-subs`, and the view consumes a top-level `gameAccounts` array. The templates access:

- `titleId`
- `gameAccountUniqueId.gameAccountId`
- `gameAccountName`
- `gameAccountRegion`
- `gameAccountStatus`
- additional subscription and game-time fields, deliberately excluded from this prototype

Waypoint already uses the same account origin through ProfileFetcher: POST `/api/` checks the session identity and GET `/api/details` reads profile metadata. Its existing per-account WebKit sessions are a natural place to make the read-only licence request. This is a private website API, not a documented stable developer API; handle schema changes and reauthentication explicitly. CN account-service discovery is not investigated here.

The JavaScript bundle proves the field accesses, not a current authenticated response for this user's account. The decoder tests use synthetic fixtures. A first authenticated read did not decode successfully; the revised probe reports sanitized request stages and per-row shapes to distinguish authentication/API failures from schema mismatch. No personal account response, cookies, login ticket or preference values are checked into this branch.

## What this branch adds

`Sources/WaypointCore/GameAccounts.swift` decodes a generic licence list. Identity includes title, region and game-account ID; a display name is not treated as identity. Integer IDs retain precision. Malformed rows and duplicate identities fail instead of silently presenting an incomplete list. No game-account field is converted into a launch selector, and no new code is connected to production launching.

`tools/game-account-probe` is a separate AppKit application to validate discovery. It uses its own temporary WebKit session, lets the user sign in on Blizzard's account page, and reads the games endpoint only after a button press. It checks the authenticated owner before and after the request, refuses unsafe JavaScript numeric IDs, and returns only the fields above. It has a 15-second request deadline. Names, regions, titles and statuses are shown in the window; numeric game-account IDs remain in memory. Rows that do not fit the expected shape are counted and reported with product/title and field-type diagnostics. Partial lists are explicitly marked unsuitable for launch selection; they are not silently accepted as complete catalogues. The probe logs and saves no account data; its discovery requests are same-origin. Blizzard’s page may still load its normal CDN, sign-in, telemetry and CAPTCHA services. It does not use Waypoint's existing keychain entries, edit subscriptions, touch game files, or write launch preferences. Close the probe to discard its session.

Build it without fetching Sparkle:

```sh
./tools/game-account-probe/build.sh
```

The last printed path is the locally signed probe app. Open it, sign in yourself, then click **Read game accounts**. Do not post the full account response or credentials in an issue or PR.

## Proposed production design

1. **Discovery:** add a dedicated GameAccountsFetcher using the selected Waypoint Account.session. Verify the account-page owner equals the Battle.net ID belonging to the launch token; checking only that a session stayed consistent is insufficient. Handle signed-out, timeout and schema failures separately, with a Refresh/Sign In action.
2. **Separate identity layers:** keep AccountMenu as the Battle.net identity picker. Add a per-game **Game account** menu containing discovered licences with region and status. Labels such as WoW1/WoW2 help users; they are not identifiers. Other games may have a single licence or no meaningful choice.
3. **Eligibility:** map the selected product/edition to licence title and region using observed entitlement data. Do not assume every WoW-named licence is valid for Forever, Retail and Classic, and do not infer runnable entitlement solely from a subscription status or one shared game icon. Preserve unknown/expired statuses for explanation rather than pretending they are playable.
4. **Persistence:** key selection by Battle.net owner ID, game family, product UID and play region. Validate that a saved selection still appears in a refreshed catalogue. Clear the remembered choice on sign-out; prevent stale asynchronous results from being applied after account or region switches.
5. **Launch:** thread an explicit validated licence through AppModel.play -> GameLauncher.launch -> LaunchOptions.write. Write GAME_ACCOUNT in the same synchronous handoff as WEB_TOKEN/REGION. The exact selector is a separate verified mapping, never a guessed numeric ID or display label. All launch paths (regular Play, Play As, reauthentication, menu-bar launch) must use this resolution step. Do not inherit a stale GAME_ACCOUNT when switching Battle.net identities.
6. **Failure:** if multiple relevant licences exist and discovery/selection is unavailable, explain the problem and require a choice/refresh rather than silently launch an arbitrary subscription. Do not overwrite a running game's shared handoff or race another launch while resolving accounts.

## Decisive live validation still needed

A game-account picker is not functional merely because a menu can show two strings.

1. In the read-only probe, confirm that two expected licences appear, including their region and title. Compare in memory, not in a published fixture.
2. Launch licence A normally through Battle.net; observe only its GAME_ACCOUNT value in memory. Repeat for licence B. Establish whether the accepted value matches a catalogue field or needs another account-service/BGS mapping. Do not change any tokens during this comparison.
3. With a validated selector and an owner-matched Waypoint token, launch each licence from a development build; verify the actual account/character list and not just that the process runs. Repeat after switching Battle.net identities, edition and region.
4. Exercise no licences, one licence, multiple licences, expired/banned/trial statuses, expired web session, stale saved selection and account switching during refresh. Use synthetic fixtures for automated coverage.
5. Confirm unrelated games launch unchanged, and that a prior GAME_ACCOUNT is not silently reused for a different owner.

No client patching, game-data migration or updater changes are required by this approach. No real game-account switching or authenticated discovery has yet been validated by this branch. The isolated probe and decoder are preparation for that test, not a claimed solution.

## Validation performed

- The standalone AppKit probe compiled and its local signature verified.
- `swift test --filter GameAccount` built Waypoint/Core and passed all four new tests.
- The probe window and Blizzard sign-in page were checked visually. The first authenticated read failed; revised diagnostic discovery is pending validation. The user has confirmed the account webpage itself lists their games; that is separate from validating the native decoder.
- Independent pre-commit review found and resolved missing request timeouts and an overly broad network-privacy claim. No production-code integration blockers were asserted because production account selection is deliberately not implemented here.
