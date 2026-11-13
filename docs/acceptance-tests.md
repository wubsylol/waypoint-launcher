# macOS acceptance tests

The account-selection feature is experimental. A successful game login alone does not validate licence discovery or selection.

| Area | Required behavior | Current evidence |
| --- | --- | --- |
| Saved authorization | Relaunch Forever after quitting Waypoint without another login | User confirmed character selection with Battle.net and Agent stopped |
| WoW editions | Launch Retail after closing Forever using saved authorization | User confirmed character selection |
| Native discovery | Discover owner-verified WoW licences without a portal or second login | Python proof, exact Swift backend and integrated native picker loading passed |
| Licence selection | Select two distinct licences and confirm each in the actual game | User confirmed Forever A → B → A reached the correct account each time (2026-11-13) |
| Selection persistence | Keep each title's explicit choice after app restart | User confirmed Forever retained the selected licence and reached the correct account without login after quitting/reopening Waypoint (2026-11-13) |
| Independent editions | Retail and Forever retain different explicit licence choices | User confirmed both titles reached their separate selected accounts with WoW closed between launches (2026-11-13) |
| Manual browser return | Official Safari game sign-in → masked return paste → native validation → Forever | User confirmed expected account/licence validation and real character selection in the isolated test app (2026-11-13); not integrated into default sign-in |
| Fresh second Mac | Authenticate, install and enter the game without an existing Battle.net/WoW setup | User reported the delivered build worked on the freshly cleared M5 Pro (2026-11-14). Exact login method and restart coverage were not separately specified. |
| Owner isolation | Never use one Battle.net owner's licences or choice for another | Automated coverage; real second-owner test pending |
| Background failure | Preserve an existing choice; show a useful native error for unavailable discovery | User confirmed highlighting a different licence then cancelling preserved the saved choice on launch (2026-11-13); deterministic connect/send/midstream/timeout tests and fixture picker failure → Retry recovery passed; physical network-loss test with Blizzard still pending |
| Expired authorization | Offer an explicit sign-in without silently deleting unrelated game authorization | Pending refinement |
| Sign-in UI | Clear progress, cancellation, keyboard access and actionable errors | Native chrome, help, connection error, Retry and Cancel visually checked; actual official Blizzard page loaded without credential entry. Full interactive password/MFA flow after cleanup pending |
| Installation | Available Games remains accessible; redundant toolbar + removed | Toolbar removal verified in live UI; catalog expansion check pending |
| External storage | Recover cleanly from missing drive and macOS access denial | Permission prompt observed; recovery coverage pending |
| Update/restart | Preserve account metadata and selected licence through app upgrades | Pending migration test |

Never record tickets, cookies, raw account IDs, email addresses or licence names in test reports. Record pass/fail and user-confirmed outcomes. Keep interactive games closed for separate native authentication experiments.
