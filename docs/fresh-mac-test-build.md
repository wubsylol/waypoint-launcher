# Fresh Mac end-to-end test build

Version 0.0.4-review (5), Apple silicon arm64, macOS deployment target 14.0.

The deliverable is the full Waypoint application, with its required Sparkle framework, a disabled self-update feed, no Windows runtime, and no user preferences, browser sessions, Keychain items, game installs or OAuth secrets. It uses the isolated development bundle ID `io.wubs.waypoint-review`.

Cold first sign-in now requests WoW authorization instead of Hearthstone when no game is installed. Existing installed-game targeting remains unchanged. The optional **Use Safari…** sheet is available for US WoW sign-in. It parses the user-pasted return strictly, fetches the current public US Forever build metadata, and verifies native game authorization/owner before returning the ticket to the usual account-adoption/Keychain path. It therefore does not require an installed executable, existing Agent records or a saved owner. Other regions/game families retain the embedded page and existing limitations.

The installer is already available without a signed-in account, and uses public catalogue/CDN data. New installs create their own records; old Battle.net files are not prerequisites. Native account selection occurs after the game exists, using its build and the saved WoW ticket.

Required other-Mac acceptance: authenticate → install Forever/Retail → choose licence → reach expected character selection → restart app and repeat. This sequence is not claimed to have passed on a genuinely clean machine until the user reports it. The manually pasted Safari ticket previously reached real Forever character selection on the development Mac.

110 selected parser, native-recovery, launch, account, game-library, installer and metadata tests passed during preparation. Release architecture, minimum OS, dependency paths, signatures and archive contents are checked before delivery. The build is ad-hoc signed, not Developer ID notarized. No upstream PR has been submitted.
