# Read-only game-account discovery probe

Run `./tools/game-account-probe/build.sh` from the repository root. Open the app at the last printed path, sign in on Blizzard’s page, then click **Read game accounts**. It shows licence names, regions, title IDs and status; it does not launch games or select a game account.

It uses an ephemeral session independent of installed Waypoint. No account data is logged or saved by the probe. Blizzard’s page still uses its normal sign-in/CDN services. Close the app to discard its session. No production launch preferences, subscriptions or game files are changed.

See [the investigation](../../docs/wow-game-account-selection.md) for the unverified launch mapping and proposed production design.
