# Browser-based Battle.net sign-in investigation

2026-11-13. No production authentication behavior changed.

## Existing flow and offline check

Waypoint already uses WebKit (WKWebView). Its game-login URL ends by returning a game ticket through `http://localhost:0/`, intercepted by the embedded navigation delegate. A normal external-browser loopback listener cannot receive HTTP on destination port 0. Apple’s installed AuthenticationServices API exposes custom-scheme and associated-HTTPS callback matching, not a generic arbitrary-HTTP callback matcher.

The offline `tools/browser-signin-probe/CallbackCheck.swift` uses synthetic URLs and no browser or credentials. Custom-scheme and HTTPS controls match; the existing launcher callback matches neither a Waypoint custom scheme nor HTTP passed as a custom scheme. This establishes a callback incompatibility for the tested matching API, not proof that all browser integrations are impossible. The unauthenticated public login page and four referenced public scripts did not reveal a configurable game-login return route in the inspected text; absence of a match is not a complete server capability assessment.

## Official “Log in with Battle.net” route

Blizzard’s OAuth samples support a registered application with a configured redirect URI, including a real localhost port. This could enable browser login with the browser’s own password-manager support, then an application callback. It does not establish that the resulting API authorization is accepted as WoW’s game-login ticket.

Public discovery metadata currently advertises authorization-code, device-code, refresh-token, token-exchange, client/server SSO and Blizzard-specific implicit-exchange grants. This is a useful lead for an authorized token bridge, not evidence that a public third-party application may use every advertised grant. It does not advertise PKCE methods or token endpoint authentication methods; that omission is not proof those capabilities are unsupported.

A live proof requires our own registered OAuth client. Never borrow an official launcher client secret. Do not embed a confidential client secret in a distributed Mac binary; determine supported native/public-client protections or use a deliberately designed backend if required. The initial offline stage did not register a client or attempt an exchange; the subsequent live stages below did both.

Acceptance requires both browser sign-in/callback and a real game launch with the resulting authorization. Account/API sign-in success alone must not be presented as game sign-in success. Keep existing saved authorization untouched and make any initial proof separate from the production login path.

## Engine choice

An embedded Chromium runtime is not the user’s installed Chrome profile, and no password-manager integration has been demonstrated for it. CEF extension capabilities vary by runtime/style; an engine replacement should not be described as automatically inheriting extensions or Apple Passwords. Apple documents ASWebAuthenticationSession as using a supporting default browser or Safari on macOS, making it the first option to evaluate once a compatible authorization/callback flow is available. External-browser extension bridging is a separate, higher-maintenance fallback, not implemented here.

## Sources

- https://github.com/Blizzard/oauth-client-sample
- https://oauth.battle.net/.well-known/openid-configuration
- https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession
- https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/customscheme(_:)
- https://developer.apple.com/documentation/authenticationservices/supporting-passkeys/
- https://github.com/chromiumembedded/cef/issues/3859

## Reproducing the offline check

On macOS 14.4 or later with an installed Xcode SDK exposing `ASWebAuthenticationSession.Callback`, run `xcrun swift tools/browser-signin-probe/CallbackCheck.swift` from the repository. The HTTPS control tests only URL-pattern matching; it does not validate app/domain entitlements or exercise a browser callback. All four checks passed on the current Mac.

## Measured official OAuth proof

An own development client was registered with a loopback redirect. The user completed browser sign-in. With separately validated client credentials and Basic authentication only (no duplicate body client_id), the loopback state check, authorization-code exchange and userinfo identity request all succeeded. No refresh token was present. PKCE parameters were included, but enforcement and public-client support were not established. Test secrets/tokens were not incorporated into the application or its Keychain; the production login was not changed.

A subsequent native Logon using the fresh OAuth bearer returned RPC status 0 but requested an external web_auth_url challenge rather than completing owner-verified authentication. This is not a successful game login. An independent no-credential native Logon also returned an official HTTPS web_auth_url challenge, which led to the direct native-browser experiment below. This may avoid the OAuth client-secret requirement if proven; it is not yet production integration.

## Direct native-browser challenge experiment

With all WoW clients closed, the native no-credential Logon returned the standard official WoW login URL with externalChallenge=login. A loopback start page opened that exact URL in Safari without an OAuth secret or saved game ticket. The user completed Blizzard sign-in, but Safari then blocked the returned http://localhost:0/ URL as a restricted network port. The user-provided screenshot showed a game-ticket-shaped return value; that value was not copied into this report or saved by that probe, and no game launch was performed during that experiment.

The waiting native proof stopped on an unimplemented ConnectionService Echo request (original hash 0x65446991, method3), so this run does not establish that every native callback path fails. A separate no-credential inspection confirmed that its web challenge is the same standard externalChallenge=login entry point, not a newly demonstrated configurable callback or direct browser-to-native completion mechanism. No owner-verified completion or generated game ticket was observed in this experiment.

## Current conclusion

The official OAuth browser/identity flow is proven for the own confidential development client, but its authorization has not been converted into a usable WoW launch credential. The native challenge alone did not remove the launcher-style restricted-port return. Replacing WebKit with Chromium does not, by itself, demonstrate password-manager integration or solve this return handoff.

The manual browser-to-game path below has now passed acceptance, while automatic browser handoff remains unimplemented. Keep the working embedded sign-in as the default until an alternative is integrated and accepted. Remaining automatic candidates include a narrowly scoped browser companion (must be prototyped, permission-reviewed and tested) or a supported configurable game-ticket callback/token exchange if one can be established. Production login behavior has not changed.

## Accepted manual browser-to-game proof

The user chose a one-time manual browser return. The separate AppKit test app opened Blizzard’s ordinary WoW login in Safari. The user copied the final localhost return address into a masked local field; it was not pasted into chat or logged. The tool checked the exact return shape, expected active owner, native authorization and saved Forever licence, then enabled an explicit launch button. The user launched Forever and confirmed character selection (2026-11-13).

This proves the manual Safari → game-ticket → native validation → selected-licence → actual game path for the tested setup. It does not prove an OAuth API token can launch WoW. The manual route requires no OAuth client secret. Password-manager controls were visible in Safari; the specific AutoFill/passkey method used was not separately confirmed.

The test source and build script are in `tools/browser-signin-probe/`. The explicit game launch writes the normal shared net.battle handoff, while Waypoint’s saved Keychain authorization and persisted licence choice are not replaced. It remains a separate development tool, not an integrated production sign-in option. An automatic browser return is still unproven, and the manual copy/paste step remains part of this tested route.
