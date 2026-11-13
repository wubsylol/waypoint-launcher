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
    let stage = "origin";
    const controller = new AbortController();
    const deadline = setTimeout(() => controller.abort(), 15000);
    try {
    async function identity() {
      stage = "auth";
      const response = await fetch('/api/', {method:'POST', credentials:'include', signal:controller.signal});
      if (!response.ok) return Promise.reject(new Error('auth'));
      const state = await response.json();
      if (!state.authenticated || state.accountId == null) throw new Error('signed out');
      if (typeof state.accountId === 'number' && !Number.isSafeInteger(state.accountId)) throw new Error('unsafe identity');
      return String(state.accountId);
    }
    const owner = await identity();
    stage = 'catalog';
    const response = await fetch('/api/games-and-subs', {credentials:'include', signal:controller.signal});
    if (!response.ok) throw new Error('catalog');
    stage = "schema";
    const body = await response.json();
    if (!Array.isArray(body.gameAccounts)) throw new Error('schema');
    const accounts = [], diagnostics = [];
    for (const a of body.gameAccounts) {
      if (a == null || typeof a !== 'object' || Array.isArray(a)) {
        diagnostics.push({product:'(malformed row)', title:'(missing title)', valid:false, shape:{}});
        continue;
      }
      const id = a.gameAccountUniqueId?.gameAccountId;
      const safeID = (typeof id === 'string' && id.length > 0) || (typeof id === 'number' && Number.isSafeInteger(id) && id >= 0);
      const safeTitle = (typeof a.titleId === 'string' && a.titleId.length > 0) || (typeof a.titleId === 'number' && Number.isSafeInteger(a.titleId) && a.titleId >= 0);
      const valid = safeID && safeTitle && typeof a.gameAccountName === 'string' && a.gameAccountName.trim().length > 0 && typeof a.gameAccountRegion === 'string' && a.gameAccountRegion.trim().length > 0;
      diagnostics.push({product: typeof a.localizedGameName === 'string' ? a.localizedGameName : '(unnamed product)',
        title: safeTitle ? String(a.titleId) : '(missing title)', valid,
        shape: {idType:typeof id, titleType:typeof a.titleId, nameType:typeof a.gameAccountName,
                regionType:typeof a.gameAccountRegion,
                uniqueKeys:Object.keys(a.gameAccountUniqueId || {}).sort().join(',')}});
      if (valid) accounts.push({titleId:a.titleId, gameAccountUniqueId:{gameAccountId:String(id)},
        gameAccountName:a.gameAccountName, gameAccountRegion:a.gameAccountRegion,
        gameAccountStatus: typeof a.gameAccountStatus === 'string' ? a.gameAccountStatus : null});
    }
    if (owner !== await identity()) throw new Error('identity changed');
    return JSON.stringify({gameAccounts:accounts, diagnostics});
    } catch (_) {
      return JSON.stringify({failure:controller.signal.aborted ? 'timeout' : stage});
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
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let failure = object?["failure"] as? String, ["auth", "catalog", "schema", "timeout", "origin"].contains(failure) {
                    result.string = "Discovery failed at stage: \(failure). No account IDs, credentials, or launch settings were saved."; return
                }
                let catalog=try GameAccountCatalog.decode(data)
                let diagnostics = object?["diagnostics"] as? [[String: Any]] ?? []
                let omitted = diagnostics.filter { $0["valid"] as? Bool != true }
                let accounts = catalog.gameAccounts.map {
                    "\($0.name) · \($0.region) · title \($0.titleID) · \($0.status ?? "Unknown status")"
                }.joined(separator:"\n")
                let shapes = diagnostics.map { row in
                    let shape = row["shape"] as? [String: Any] ?? [:]
                    return "\(row["product"] as? String ?? "Product") · title \(row["title"] as? String ?? "?"): id=\(shape["idType"] as? String ?? "?"), name=\(shape["nameType"] as? String ?? "?"), region=\(shape["regionType"] as? String ?? "?"), unique keys=\(shape["uniqueKeys"] as? String ?? "")"
                }.joined(separator:"\n")
                result.string = "Decoded \(catalog.gameAccounts.count) licences; \(omitted.count) rows do not match the expected schema.\n" + accounts + "\n\nSchema diagnostics (no account IDs):\n" + shapes + "\n\nDiscovery only. A partial result must not be used for account selection."
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
