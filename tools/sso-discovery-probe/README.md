# Explicit live SSO investigation probes

These are **read-only experiments**, not a supported authentication bridge and not part of the shipping launcher. Build with `./tools/sso-discovery-probe/build.sh`. Building makes no network request. Running either printed executable is an explicit live test against Blizzard.

They decrypt the current user's existing `net.battle` WoW login entry in memory, then try the game's documented-by-binary-string `/login/sso?token=…&ref=…` URL followed by the account-settings OAuth entry point. There is no password entry, Keychain export, raw response export, cookie copying, game patch or TLS bypass. HTTP redirects and browser navigations are restricted to HTTPS on battle.net or its subdomains. The HTTP session is ephemeral; the browser uses a non-persistent WebKit store and creates no window.

Only outcome booleans and HTTP status codes are printed. Raw errors and credential-bearing URLs are deliberately not printed by the probes. Normal system/network/server logging is outside this guarantee. The account catalogue is queried only after verifying that the authenticated account-page owner matches the ticket's owner; no licence values are output.

Do not post game tickets, cookie stores or request traces containing credentials. Do not interpret a token-shaped value as proof that a ticket is still accepted: use a normal game login as the validity control. Do not repeatedly run these experiments or treat a failed exchange as a reason to request/replay a password automatically.

Observed results and limits are in `docs/silent-account-discovery.md`.
