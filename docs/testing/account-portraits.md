# Account portrait test build

Experimental branch: `experiment/account-portraits`. No mainline release or installed-app replacement.

Account menu → Choose Portrait… offers four WoW race-face icons and seven Diablo III class-face icons. Selection applies immediately to the account named in the picker and survives restart/reauthentication. Use Default Icon clears it. Done/close only dismisses the picker; it is not a cancellation action.

Images download anonymously from fixed Blizzard CDN URLs. This is a curated local collection, not synchronization with the Battle.net profile avatar. Small processed thumbnails are cached for offline use; missing/failed images fall back to the existing account symbol. Retry Images retries failures. No art files are bundled or copied from GitHub.

The test app retains `io.wubs.waypoint-review` so it can use existing accounts. Quit other Waypoint copies before testing: the test app shares preferences and existing Keychain item names with the installed fork. Older builds ignore portrait choices and may discard them when rewriting account preferences. The installed app itself is untouched.

Validation: 18 targeted account tests passed, including backward decoding and per-account persistence/reauthentication. Independent source review found no blockers. Live AppKit verification confirmed all 11 CDN images loaded, picker controls fit, and a selected Night Elf rendered inside the existing toolbar bezel. Multi-account UI switching, offline restart, and visual quality on other displays still need user testing.

An initial debug-package launch failed because the executable lacked the bundled Sparkle framework runpath. The repaired tested artifact includes `@executable_path/../Frameworks` and removes build-machine absolute framework paths. Any rebuilt test must use the normal bundling script or preserve this framework configuration.
