import AppKit
import WebKit

/// Standalone, read-only discovery harness. Its ephemeral cookie jar is independent
/// of installed Waypoint; no tokens, preferences, subscriptions or game files change.
@MainActor
final class Probe: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var browser: WKWebView!
    var result: NSTextView!
    var button: NSButton!
    var reading = false
    let script = """
    if (location.origin !== 'https://account.battle.net') throw new Error('origin');
    const controller = new AbortController();
    const deadline = setTimeout(() => controller.abort(), 15000);
    try {
    async function identity() {
      const response = await fetch('/api/', {method:'POST', credentials:'include', signal:controller.signal});
      if (!response.ok) throw new Error('auth');
      const state = await response.json();
      if (!state.authenticated || state.accountId == null) throw new Error('signed out');
      if (typeof state.accountId === 'number' && !Number.isSafeInteger(state.accountId)) throw new Error('unsafe identity');
      return String(state.accountId);
    }
    const owner = await identity();
    const response = await fetch('/api/games-and-subs', {credentials:'include', signal:controller.signal});
    if (!response.ok) throw new Error('catalog');
    const body = await response.json();
    if (!Array.isArray(body.gameAccounts)) throw new Error('schema');
    const accounts = body.gameAccounts.map(a => {
      const id = a.gameAccountUniqueId?.gameAccountId;
      if ((typeof id === 'number' && !Number.isSafeInteger(id)) || id == null) throw new Error('unsafe game identity');
      if (typeof a.titleId === 'number' && !Number.isSafeInteger(a.titleId)) throw new Error('unsafe title');
      return {titleId:a.titleId, gameAccountUniqueId:{gameAccountId:String(id)},
              gameAccountName:a.gameAccountName, gameAccountRegion:a.gameAccountRegion,
              gameAccountStatus:a.gameAccountStatus};
    });
    if (owner !== await identity()) throw new Error('identity changed');
    return JSON.stringify({gameAccounts:accounts});
    } finally { clearTimeout(deadline); }
    """
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(); let item = NSMenuItem(); let submenu = NSMenu()
        submenu.addItem(withTitle: "Quit Account Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:900,height:760), styleMask:[.titled,.closable,.resizable], backing:.buffered, defer:false)
        window.title = "Waypoint Account Probe — Read Only"
        let label = NSTextField(wrappingLabelWithString:"Sign in on Blizzard’s page, then click Read game accounts. This only lists licences; it does not launch games or change your account.")
        label.frame = NSRect(x:20,y:699,width:650,height:44); label.autoresizingMask=[.width,.minYMargin]
        button = NSButton(title:"Read game accounts",target:self,action:#selector(read))
        button.frame = NSRect(x:690,y:705,width:190,height:30); button.autoresizingMask=[.minXMargin,.minYMargin]
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        browser = WKWebView(frame:NSRect(x:20,y:205,width:860,height:480),configuration:config)
        browser.autoresizingMask=[.width,.height]; browser.navigationDelegate=self
        let scroll = NSScrollView(frame:NSRect(x:20,y:20,width:860,height:170)); scroll.autoresizingMask=[.width]
        scroll.hasVerticalScroller=true
        result=NSTextView(frame:scroll.bounds); result.isEditable=false; result.isSelectable=true
        result.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        result.string="No account data read yet. Results remain in this window; nothing is saved or logged."
        scroll.documentView=result
        for view in [label,button!,browser!,scroll] { window.contentView!.addSubview(view) }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        browser.load(URLRequest(url:URL(string:"https://account.battle.net/games")!))
    }
    @objc func read() {
        guard !reading else { return }
        guard browser.url?.scheme == "https", browser.url?.host == "account.battle.net" else {
            result.string="Finish signing in on Blizzard’s account page first."; return
        }
        reading=true; button.isEnabled=false
        Task {
            defer { reading=false; button.isEnabled=true }
            do {
                let value = try await browser.callAsyncJavaScript(script, contentWorld:.defaultClient)
                guard let text=value as? String, let data=text.data(using:.utf8) else { throw CocoaError(.coderReadCorrupt) }
                let catalog=try GameAccountCatalog.decode(data)
                result.string = catalog.gameAccounts.isEmpty ? "Blizzard returned an empty game-account list." : catalog.gameAccounts.map {
                    "\($0.name) · \($0.region) · title \($0.titleID) · \($0.status ?? "Unknown status")"
                }.joined(separator:"\n") + "\n\nDiscovery only. Launch selector mapping has not been verified."
            } catch {
                // JavaScript error descriptions can include URLs. Do not log them.
                result.string="Could not read a valid account catalogue. Finish signing in and retry. The API may have changed or be unavailable. No launch settings were changed."
            }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
        let url=navigationAction.request.url
        decisionHandler(url?.scheme == "https" || url?.absoluteString == "about:blank" ? .allow : .cancel)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
}
MainActor.assumeIsolated {
    let app=NSApplication.shared; let delegate=Probe(); app.setActivationPolicy(.regular); app.delegate=delegate; app.run()
}
