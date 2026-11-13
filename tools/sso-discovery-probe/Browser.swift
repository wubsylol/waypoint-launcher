import AppKit
import WebKit

@MainActor
final class SilentProbe: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var web: WKWebView!
    var stage = 0
    var done = false
    var ticketOwner = ""
    var checking = false
    func applicationDidFinishLaunching(_ notification:Notification) {
        do {
            guard let value=try LaunchOptions(gameKey:"WoW").storedToken(), let ticket=LoginToken(value) else { finish("No valid game ticket; no request made.");return }
            ticketOwner=ticket.accountID
            let configuration=WKWebViewConfiguration();configuration.websiteDataStore = .nonPersistent()
            configuration.applicationNameForUserAgent="Version/26.0 Safari/605.1.15"
            web=WKWebView(frame:NSRect(x:0,y:0,width:800,height:700),configuration:configuration)
            web.navigationDelegate=self
            var url=URLComponents(string:"https://account.battle.net/login/sso")!
            url.queryItems=[URLQueryItem(name:"token",value:ticket.value),URLQueryItem(name:"ref",value:"https://account.battle.net/games")]
            web.load(URLRequest(url:url.url!))
            Task { try? await Task.sleep(for:.seconds(40)); if !done { finish("Invisible browser test timed out; no authenticated result established.") } }
        } catch { finish("Could not read the current game ticket; no request made.") }
    }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping @MainActor (WKNavigationActionPolicy)->Void) {
        guard let url=navigationAction.request.url, url.scheme == "https", let host=url.host,
              host == "battle.net" || host.hasSuffix(".battle.net") else { decisionHandler(.cancel);return }
        decisionHandler(.allow)
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
        guard !done, let url=webView.url else { return }
        if stage == 0 {
            stage=1
            // Give the SSO page's JavaScript/redirects time to settle before
            // explicitly entering account OAuth. This remains a bounded probe.
            Task {
                try? await Task.sleep(for:.seconds(4))
                guard !done else { return }
                stage=2
                webView.load(URLRequest(url:URL(string:"https://account.battle.net/oauth2/authorization/account-settings")!))
            }
            return
        }
        guard stage == 2 else { return }
        if url.path.contains("/login") {
            Task {
                try? await Task.sleep(for:.seconds(3))
                if !done, webView.url?.path.contains("/login") == true {
                    finish("Invisible browser settled on a login page; game ticket did not silently establish account-website authorization.")
                }
            }
            return
        }
        guard url.host == "account.battle.net", !url.path.hasPrefix("/oauth2"), !url.path.hasPrefix("/callback"), !checking else { return }
        checking=true
        Task {
            defer { checking=false }
            let script="""
            if (location.origin !== 'https://account.battle.net') return {signedIn:false};
            const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),8000);
            try {
              const r=await fetch('/api/',{method:'POST',credentials:'include',signal:controller.signal});
              if (!r.ok) return {signedIn:false};
              const s=await r.json();
              if (!s.authenticated || String(s.accountId) !== owner) return {signedIn:false};
              const c=await fetch('/api/games-and-subs',{credentials:'include',signal:controller.signal});
              const b=c.ok ? await c.json() : {};
              return {signedIn:true,catalogue:Array.isArray(b.gameAccounts)};
            } finally {clearTimeout(timer);}
            """
            do {
                let result=try await webView.callAsyncJavaScript(script,arguments:["owner":ticketOwner],contentWorld:.defaultClient) as? [String:Any]
                if result?["signedIn"] as? Bool == true {
                    finish("Invisible browser authenticated as game-ticket owner. Licence array available: \(result?["catalogue"] as? Bool == true)")
                }
                // A settled unauthenticated page may still redirect into login.
            } catch { /* Never log raw errors or credential-bearing URLs. */ }
        }
    }
    func finish(_ message:String) {
        guard !done else { return };done=true
        web?.stopLoading();web?.navigationDelegate=nil
        print(message);fflush(stdout);NSApp.terminate(nil)
    }
}
@main struct Main {
    @MainActor static func main() {
        let app=NSApplication.shared;let delegate=SilentProbe()
        app.setActivationPolicy(.prohibited);app.delegate=delegate;app.run()
    }
}
