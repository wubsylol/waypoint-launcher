# Investigation: licence discovery without another login or a visible portal

Date: 2026-11-13. Branch: `investigate/silent-account-discovery`.

## Findings

The current picker uses an account-management website session to discover licences, while normal WoW launches use a saved game ticket. The working game login does not establish that the account-management session is authorized. Rendering the portal and asking for another password is therefore a flaw in our feature's authentication/UX design, not an acceptable finished picker.

The desired flow is a native account menu backed by owner-scoped cached data and background discovery under existing authorization. A hidden web view alone is not a solution if it merely hides a form that still requires interaction.

## Measured tests

The experiments read the current encrypted WoW launch entry through the existing LaunchOptions implementation, decrypt it only in memory, and contact Blizzard's HTTPS SSO/account endpoints. No password was read or submitted. Only the existing shared WoW launch token was read in memory; no launcher client secret or Keychain entry was accessed or persistently exported. Sessions were ephemeral, credentials were not printed, and no subscriptions or account security settings were changed.

1. **HTTP SSO attempt:** request the `/login/sso?token=…&ref=…` handoff found in the installed WoW executable, then follow the account-settings OAuth entry point. SSO and OAuth landing responses were HTTP 200; OAuth settled on a login path. POST `/api/` returned 401, so no owner-verified website session was established. A preliminary request without the OAuth step also returned an unauthenticated state; it is not treated as a complete-flow result.
2. **Invisible WebKit control:** repeat the flow in a non-persistent WKWebView, allowing normal page JavaScript but displaying no window. It settled on a login page, with no silently authenticated account-management result. An initial version entered OAuth immediately after the first completed page; the reviewed version gives that page four seconds to settle, then enters OAuth, with a three-second settled-login check and forty-second overall deadline. The reviewed repeat also settled on login. These finite waits limit coverage of unusually delayed flows.
3. **Game-validity control:** the user then launched Forever using the unchanged saved login entry and confirmed character selection. This rules out simply treating the observed web failure as evidence that all game authorization had expired.

These results apply to the particular ticket and flows tested. They do not prove that every possible SSO exchange is impossible. They do show that we cannot claim direct game-ticket reuse with this web handoff works, and we should not present its resulting login form as part of ordinary licence selection.

## Concrete native alternative

The installed Forever client contains the native method names `GetGameAccounts`, `GetGameAccountLinks`, `GetGameAccountInfo` and `GetSignedAccountState`, plus account SSO handoff URLs. Public reverse-engineered protocol declarations independently describe:

- Account service v2 `GetGameAccountLinksResponse.links`, whose `GameAccountLinks` contains repeated `GameAccountHandle` values.
- `GetGameAccountInfoRequest.game_account` and response `GameAccountInfo`, which includes a name and account ID.
- Authentication messages that accept existing auth/web credentials, and logon results containing game-account identities.

The SSO URL’s token parameter is not proven to accept WEB_TOKEN; it could require a separately generated website SSO credential. This is a plausible native discovery route: authenticate a normal game-service connection with the existing game authorization, request the linked game-account handles, resolve their names, filter by program and region, and bind the resulting catalogue to the authenticated Battle.net owner. It avoids the account-management portal entirely.

**Not yet proven:** that Blizzard's current production service permits these operations for Waypoint's WoW-scoped ticket; the exact current wire/version negotiation, service transport, regional routing and permissions; whether a returned name is accepted as the launch selector for two distinct licences. No native BGS connection or native licence query was performed by these experiments. Message names and an emulator's behavior are not production verification.

Relevant primary sources for their respective implementations:

- Installed WoW client: local executable string inspection; no client patching or memory injection.
- [TrinityCore account service declarations](https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/api/client/v2/account_service.pb.h).
- [TrinityCore account types](https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/api/common/v2/account_types.pb.h): links/handles and game-account info name fields.
- [TrinityCore authentication declarations](https://github.com/TrinityCore/TrinityCore/blob/master/src/server/proto/Client/authentication_service.pb.h): cached web credentials and logon game-account IDs. This is a protocol reference, not evidence of Blizzard's current server behavior.
- [Microsoft's documented Battle.net SSO exchange](https://learn.microsoft.com/en-us/xbox/playfab/identity/player-identity/platform-specific-authentication/battlenet-login) requires a registered title's own client ID/secret and requests `account.basic openid`; it does not establish access to the account-management catalogue. We did not run that exchange, borrow a client secret, or assume its identity token has account-management permissions.

## Implementation direction

1. Replace the visible portal picker with a native list only. Start background discovery after ordinary account sign-in, deduplicate work by owner, and cache verified licence metadata locally per owner/program/region. Persist edition-specific selected account IDs separately from catalogue metadata.
2. Use the native game-service route as the next experimental backend. Establish the transport and confirm owner/region/program and account names against real selected licences. Keep requests read-only and bounded. Do not implement undocumented HTTP routes by guessing or suppress certificate/host validation.
3. Cached lists should appear immediately and identify their refresh age. Background refresh must not silently change an explicit selected account. An unavailable refresh should preserve a known owner-scoped choice, not invent a default or substitute another identity.
4. If an already-authorized account-website cookie session can supply data, it may serve as a hidden fallback. If that session reaches a form/MFA/CAPTCHA, stop rather than expose the portal or attempt a password in the background. It does not solve initial native discovery when the website session is absent.
5. Do not promise unlimited authentication. If the game authorization itself is revoked/expired, an explicit normal sign-in may still be required. That is different from demanding a second account-management login while game authorization remains valid.

The native discovery backend is not implemented on this branch. The previous `feature/game-account-selection` visible-portal build is **not** a completed implementation of this UX and should not be submitted upstream in that form. Merely caching its first successful portal lookup would reduce repeat prompts, but would not solve the first extra login and is not presented as a fix.

## Diagnostic tools

`tools/sso-discovery-probe/build.sh` builds the explicit live HTTP and invisible-browser tests without making requests. The printed executables perform a live test only when run. They output booleans/status categories only, retain no cookie store, never output licence values, and restrict redirects/navigations to battle.net HTTPS hosts. Normal system/server logging is outside that guarantee.

The HTTP helper compiled and ran; the browser helper compiled and ran without displaying a portal. The navigation allowlist does not restrict every ordinary page subresource; Blizzard’s pages may load their normal CDN/telemetry resources. These are experiments, not automated proof of a working discovery feature. No production picker changes, credential migrations, saved-password changes, or upstream PR are included in this investigation branch.
