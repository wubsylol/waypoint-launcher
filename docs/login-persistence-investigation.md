# Investigation: persistent sign-in and a less intrusive login window

Date: 2026-11-13. Reviewed upstream `e566728c7bc213fdfb31437c1b333c9574d2e106` after fetching upstream. This branch is documentation only: no live credentials, saved tokens, cookies, account preferences or game files were changed. It is separate from the game-account-selection investigation. No upstream PR is submitted.

## Result

Waypoint already reuses game tokens; it is not designed to request credentials at every launch. Several implementation decisions nevertheless create extra prompts when switching games and using Sign In Again, matching the scenario the user reported. There is no verified desktop-session renewal implementation in this code. The comments claiming game tickets last months do not establish a measured lifetime.

The official launcher's keep-me-logged-in behavior does not by itself tell us whether its desktop credential is long-lived, rotated, or exchanged for short-lived game tickets. That distinction is unresolved. A cached web game ticket, a browser cookie, a developer OAuth API token and the desktop client's resumable authorization must not be assumed interchangeable. This investigation did not extract or replay the official launcher's saved secrets or intercept TLS traffic.

## Confirmed source behavior

| Path | What Waypoint currently does | User-visible consequence |
| --- | --- | --- |
| Same Battle.net identity and codename, cached token available | `AppModel.token` returns the Keychain token immediately | Should not show a new web sign-in merely because another identity was selected earlier |
| A game family without a cached token | No normal silent-session attempt; eventually constructs a fresh WebSessionID for LoginWindow | A new interactive login, even though another game already has authorization |
| General account-menu Sign In Again | Signs in to loginTarget (last-played family), then calls TokenVault.removeAll except that family | Other games can ask again when revisited; this deletion is local policy, not proof Blizzard rejected those tokens |
| Per-game Sign In Again and Play | `forceSignIn` bypasses that family's cached token | A deliberate reauthentication, separate from the broader account-menu action |
| Keychain read failure, missing item or malformed saved dictionary | TokenVault.tokens collapses all of these to an empty dictionary | No way to distinguish unavailable saved authorization from an account that needs first-time login |
| Save after an unsuccessful dictionary read | `save` merges into that empty dictionary and updates the account's one Keychain item | If the read failed transiently but the update succeeds, other saved game tokens can be overwritten without being preserved; conditional code risk, not an observed failure on this Mac |
| Token cannot be saved | adopt logs token_save_failed but can still return the in-memory ticket for this launch | Current game may work while the next launch needs credentials again; persistence failure is not clearly presented to the user |
| Game rejects an existing token | App returns it without a server validity check and cannot observe in-game rejection | It cannot transparently recover; user must trigger reauthentication |

### Relevant code

- `Sources/Waypoint/AppModel.swift:1139-1240`: cached token, optional saved-password flow, fresh interactive session.
- `Sources/Waypoint/AppModel.swift:985-1026`: general Sign In Again and deletion of other families' tokens.
- `Sources/Waypoint/AppModel.swift:1088-1112`: adopt saves tokens and replaces the account's web session.
- `Sources/Waypoint/AppModel.swift:149-155`: Keychain services depend on bundle identifier; test builds intentionally use different namespaces.
- `Sources/WaypointCore/Accounts.swift:120-184`: game-token vault and read/merge/write behavior.
- `Sources/Waypoint/WebLogin.swift:60-145`: persistent per-account browser stores exist, but a freshly adopted session replaces the previous one.
- `Sources/Waypoint/WebLogin.swift:146-192`: SilentTokenFetcher exists. Its only caller is the one-time legacy-session adoption in setUpAccounts, not normal Play.
- `Sources/WaypointCore/SavedLogin.swift`: saved-password automation is an explicit Keychain opt-in with retry limits. It is password replay, not a refresh-token protocol.

Retail and other WoW flavours use codename `WoW`, so those editions share a game-token slot for a given Battle.net identity. Switching WoW licences within that identity is the separate GAME_ACCOUNT problem. It should not require a new web token solely because the licence name changes, though actual client acceptance still requires testing. Switching to Hearthstone (`WTCG`), Warcraft III (`W3`) or another family is a different cache slot.

## Why the login window feels clunky

`LoginWindow.run` creates a 480 x 640 window. A permanently displayed passkey warning and optional explanatory notices reduce its usable page area. The window is resizable but has no explicit content minimum. For a known email, the page is made transparent and covered while the first step is submitted, with an eight-second upper bound; this creates a blank/spinner phase before the user sees the password or challenge. There is no explicit login navigation/progress/error state beyond revealing the web page. The "needed only once" message is too absolute when tokens can be revoked, storage can fail, and account-menu reauthentication deliberately removes other tokens.

Passkey buttons are hidden because the current embedded flow cannot complete that path. A system-browser flow could improve passkeys and existing browser sessions, but it cannot be assumed to work with the current callback: the observed web flow redirects a ticket to `http://localhost:0/`. A normal browser cannot simply be swapped in while preserving this web-view interception scheme. Establish a supported callback/handoff first; do not send the user to a dead localhost URL or introduce a token-pasting workflow.

## Recommended sequence

### 1. Remove avoidable reauthentication and persistence ambiguity

- Distinguish Keychain item-not-found from locked/access-denied/corrupt data. A temporary storage failure should offer retry/unlock, not immediately ask for a password.
- Make token dictionary reads throwing for write/merge operations. Never overwrite a dictionary that could not be read. Test error paths with an injected Keychain backend and synthetic values, not the user's vault.
- Show a clear persistence warning if a game signs in successfully but saving its token fails. Keep credentials/tickets out of UI diagnostics.
- Make ordinary per-game reauthentication refresh that family's token. Reserve discarding all families for an explicit reset/security-recovery action, with clear wording. Password or authenticator changes may invalidate other tickets on the server; do not assume every ordinary re-login proves all others are invalid.
- On normal account switching, preserve the owner-scoped cache and avoid clearing sessions merely to change selection. Verify the same account/codename fast path before investigating expiry.
- Keep stable release bundle identifiers and signing identity; explain that an intentionally isolated development build requires its own sign-in. No automatic copying of production Keychain items into test builds.

### 2. Test session reuse before promising silent renewal

- For a selected known account, try a bounded silent flow against its saved per-account browser session when no usable family ticket exists. If it can issue a ticket, verify token.accountID matches the requested identity before adopting or launching.
- If interaction is necessary, continue in the same web view/store rather than discard it and start again. Preserve challenge state; never retry credentials invisibly during MFA/CAPTCHA.
- Make failed network requests, expired browser sessions, missing tickets and rejected tickets distinct states. Do not silently fall back to another Battle.net identity.
- This is an experiment, not a guarantee: the current source comments explicitly claim web sessions cannot reissue these tickets without the form. Measure actual current behavior before adding a silent attempt that just delays every login.

### 3. Improve the interactive fallback

- Use a larger responsive AppKit window/sheet with a sensible minimum size, an account heading, visible loading/error states, retry and cancellation.
- Show the selected identity and allow the user to correct it; preserve region and account context.
- Avoid an unconditional multi-paragraph warning above every page. Explain passkey limitations where relevant, and avoid unsupported buttons without blocking legitimate escape paths.
- Replace "only once" with accurate copy about remembered authorization and occasional reauthentication.
- Continue honoring explicit saved-password opt-in. Do not solve persistence by quietly storing passwords or suppressing MFA.

### 4. Investigate desktop-session parity separately

For the equivalent of the official app's keep-me-logged-in, first establish a legitimately issued resumable credential and exchange protocol for this client. A developer API OAuth refresh grant is not evidence of a game-launch refresh flow. Do not borrow an official client's embedded client secret or copy its persisted login credential and call that native support.

If a supported/discovered flow can be used legitimately, keep its credential in Keychain with stable ownership, expiry/rotation metadata and revocation handling. Deduplicate renewal per account, persist rotated credentials safely, and distinguish transient failures from invalid credentials. Rotate only as the protocol requires; do not invent a lifetime or poll authentication continuously. Until proven, the practical gains above are valuable but not full desktop-session parity.

## Validation plan

Use a stable development build and synthetic isolated Keychain services first. Cover cached same-game launches, two identities sharing a codename, first-time different-family launches, target-only reauthentication preserving unrelated tokens, explicit all-family reset, locked/corrupt Keychain, save failures and account mismatch. For silent recovery, cover immediate redirect, settled form, MFA, CAPTCHA, timeout, cancellation, identity switch during an attempt, and network failure without account deletion.

For real sessions, record only timestamps, app/bundle version, game family, outcome and OSStatus categories. Do not dump Keychain values, cookies, callback URLs or raw web-view errors. Observe repeat launches/restarts over time before claiming a token lifetime. Verify game acceptance, not merely that a window/process started.

No Waypoint diagnostics were found in the expected `~/Library/Logs/Waypoint` directory in this workspace, and no installed Waypoint bundle was located in the top-level system/personal Applications directories. Therefore the installed version and actual cached-token history behind the user's prompts were not independently verified. The user's report of prompts during game/account switching and Sign In Again supports the source-based explanation; it is not evidence for a specific expiry duration.

## Scope of this branch

Documentation and source analysis only. No production login-policy change or refresh implementation is included. No test execution is claimed for proposed behavior, and no stored credentials were accessed or changed. A targeted, tested persistence/error-handling patch should precede speculative desktop protocol work.
