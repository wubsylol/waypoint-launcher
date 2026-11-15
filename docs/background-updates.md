# Updates and native background behavior

Automatic game version checks run at Waypoint startup, then only for the selected game each time Play is requested. Checks run alongside the launch flow and never gate authentication or playing on network availability. The existing off-main installation scan refreshes metadata first. There are no timer, wake or activation-triggered version checks. Manual Check for Updates is an explicit all-games action. Download/install planning still fetches required metadata when the user requests those operations.

Concurrent requests retain their game scope: a queued one-game launch check never becomes an all-game check. Completed downloads clear the cached update indication and delivered alert without performing another automatic version query. Enabling notifications can announce already-known results without a network check.

Native notifications stay opt-in. Notification Center is initialized only when notifications are enabled or Settings is opened. Login-item status and notification permission queries are limited to Settings; returning to the library does not query system services. Sparkle's upstream behavior is preserved; personal builds have no self-update feed.

Hide Dock Icon When Windows Are Closed leaves the normal Dock icon/app menu present while the library or Settings is open, then returns to accessory mode when the last of those windows closes. The menu-bar icon remains opt-in; hiding the Dock enables it and removing it restores regular Dock presence. Left-click toggles the library; right/Control-click opens quick actions. Closing a window does not quit.

Finder/Spotlight/manual launches show the library regardless of the Dock setting. The open-application Apple event's login-item marker is checked as a best-effort hint for quiet login startup, without querying SMAppService to classify launch. Unknown launches show the window. A real logout/login remains unverified; failure to receive the hint opens a harmless library window.

The app remains AppKit/Swift, with no SwiftUI additions or new dependencies. Native services are unavailable in an unbundled development run. Bundle identity and saved credentials are unchanged.
