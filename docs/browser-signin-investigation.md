# Browser-based Battle.net sign-in investigation

2026-11-13. No production authentication behavior changed.

## Existing flow and offline check

Waypoint already uses WebKit (WKWebView). Its game-login URL ends by returning a game ticket through `http://localhost:0/`, intercepted by the embedded navigation delegate. A normal external-browser loopback listener cannot receive HTTP on destination port 0. Apple’s installed AuthenticationServices API exposes custom-scheme and associated-HTTPS callback matching, not a generic arbitrary-HTTP callback matcher.

The offline `tools/browser-signin-probe/CallbackCheck.swift` uses synthetic URLs and no browser or credentials. Custom-scheme and HTTPS controls match; the existing launcher callback matches neither a Waypoint custom scheme nor HTTP passed as a custom scheme. This establishes a callback incompatibility for the tested matching API, not proof that all browser integrations are impossible. The unauthenticated public login page and four referenced public scripts did not reveal a configurable game-login return route in the inspected text; absence of a match is not a complete server capability assessment.

## Official “Log in with Battle.net” route

Blizzard’s OAuth samples support a registered application with a configured redirect URI, including a real localhost port. This could enable browser login with the browser’s own password-manager support, then an application callback. It does not establish that the resulting API authorization is accepted as WoW’s game-login ticket.

Public discovery metadata currently advertises authorization-code, device-code, refresh-token, token-exchange, client/server SSO and Blizzard-specific implicit-exchange grants. This is a useful lead for an authorized token bridge, not evidence that a public third-party application may use every advertised grant. It does not advertise PKCE methods or token endpoint authentication methods; that omission is not proof those capabilities are unsupported.

A live proof requires our own registered OAuth client. Never borrow an official launcher client secret. Do not embed a confidential client secret in a distributed Mac binary; determine supported native/public-client protections or use a deliberately designed backend if required. No client was registered or credential exchange attempted during these checks.

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
