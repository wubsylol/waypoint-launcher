# Login presentation and connection recovery

2026-11-13. Development branch `investigate/silent-account-discovery`.

## Login presentation

The form remains Blizzard’s live website in WKWebView. No replacement email/password form was added. AppKit provides a consistent dark window, status spinner, Cancel, and on-demand sign-in help. At the user’s request, the redundant Battle.net heading, explanatory subtitle and origin label were removed; the official page fills the window above the footer. Necessary account-specific notices still appear when supplied by the login flow. Paths and queries are never displayed by native chrome.

The permanent passkey warning moved into Sign-in help. Existing passkey-button handling and account-name prefill remain. Blizzard’s normal 4xx form validation remains on the page. Network errors, HTTP 429 and server errors show a native recovery view; Retry reloads the original sign-in URL in the same store. It does not delete saved game tokens or licence choices. Cancel stops the page, prefill work and watchdog. Each provisional page load gets a 25-second watchdog, canceled on completion, so idle typing does not consume the next navigation’s timeout.

## Native discovery recovery

The protocol logic moved into WaypointCore without changing the production endpoint, TLS trust validation, owner checks or requests. An internal transport interface permits deterministic failures without disabling the user’s network or contacting Blizzard. Each picker Retry creates a fresh native client and rechecks known running WoW clients. Existing per-title selections are only replaced by Use account after complete successful discovery.

Six recovery tests cover fragmented/disconnected replies at multiple protocol stages, fresh-client retry, connect/send failures, stalled-connection timeout, user cancellation of a pending read, and owner mismatch both at logon and when resolving a licence name. They use synthetic account/ticket fixtures; no actual authorization or account IDs are accessed.

## Validation and limits

39 selected codec, account, launch and recovery tests passed. The development app builds and passes deep signature verification. An independent review caught and verified the fix for a watchdog that could have counted typing time against a later navigation.

Visual checks used an isolated harness running the exact window/picker implementations: an injected failed account lookup disabled Use account, Retry loaded the fixture catalogue and retained the remembered selection, and Cancel closed the picker. A deliberately unreachable `.invalid` login destination showed the connection-error panel; repeated Retry and Cancel worked. Help opened and closed correctly. A disabled local layout fixture was used only for initial sizing; it is not the application’s login form.

The final window was separately checked with the actual official `https://us.battle.net` WoW login page, showing Blizzard’s logo, email step and provider controls inside the native window. No credentials were entered and no real account session was replaced. Full interactive password/MFA/social-provider login in the refined window and a physical connection drop against Blizzard remain manual acceptance items. There are no credential, installation or game-content migrations in this change.
