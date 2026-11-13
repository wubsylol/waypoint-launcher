# Browser sign-in development probes

`CallbackCheck.swift` performs offline synthetic URL matcher checks only:

```sh
xcrun swift tools/browser-signin-probe/CallbackCheck.swift
```

The optional manual-return app tests real WoW browser sign-in without altering the main application's saved Keychain login. Build with Xcode's Swift toolchain:

```sh
tools/browser-signin-probe/build-manual-return.sh
```

This is an isolated local development tool, not a production sign-in option. It uses the `io.wubs.waypoint-review` preferences for the expected active account and saved Forever licence, and the tested `/Volumes/External HD/Battle.Net/World of Warcraft` installation. Other setups need those development settings adjusted before use. It requires the SwiftPM/Xcode output containing `WaypointCore.o`.

Close every WoW client. In the test app, open the official login page in Safari, finish sign-in, and copy Safari's final return address into the masked field. Safari's restricted-port error is expected in this manual route. The tool strictly checks the return shape and selected owner, then validates the ticket and saved licence with Blizzard's native service. Only after success does it enable **Launch Forever (test)**.

Launch uses the normal shared `net.battle` handoff and therefore replaces that shared token/selector, including if the later process spawn fails. It does not write TokenVault/Keychain or change the saved licence. It rejects a changed active identity/choice and known running WoW clients. Unknown external installations are not covered by the running-client check.

Never paste return addresses into chat, logs or issues. The input field is cleared before native validation, but that does not erase the browser history or user's clipboard. The test does not automatically import the browser ticket into Waypoint. See `docs/browser-signin-investigation.md` for the separate OAuth results and remaining automatic-handoff limitation.
