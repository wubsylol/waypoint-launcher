import AuthenticationServices
import Foundation

// Offline API checks only. All URLs/tickets are synthetic; no browser is opened.
let launcherReturn = URL(string: "http://localhost:0/?ST=synthetic")!
let customReturn = URL(string: "waypoint-review://complete?state=synthetic")!
let custom = ASWebAuthenticationSession.Callback.customScheme("waypoint-review")
let http = ASWebAuthenticationSession.Callback.customScheme("http")
let https = ASWebAuthenticationSession.Callback.https(host: "example.invalid", path: "/complete")
let cases = [
    ("custom-scheme control", custom.matchesURL(customReturn), true),
    ("HTTPS matcher control", https.matchesURL(URL(string: "https://example.invalid/complete")!), true),
    ("game return through custom-scheme matcher", custom.matchesURL(launcherReturn), false),
    ("game return through HTTP-as-custom-scheme matcher", http.matchesURL(launcherReturn), false),
]
for (name, observed, expected) in cases {
    print(name + ": " + (observed == expected ? "PASS" : "UNEXPECTED"))
}
if cases.contains(where: { $0.1 != $0.2 }) { exit(1) }
