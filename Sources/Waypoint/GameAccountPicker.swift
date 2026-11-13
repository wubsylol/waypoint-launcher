import AppKit
import WebKit
import WaypointCore

/// Owner-verified licence discovery and selection in the account's existing cookie jar.
/// Does not request passwords itself, change subscriptions, or log page data/errors.
@MainActor
final class GameAccountPicker: NSObject, NSWindowDelegate, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<GameAccountSelection?, Never>?
    private var accounts: [GameAccount] = []
    private var popup = NSPopUpButton()
    private var status = NSTextField(wrappingLabelWithString: "")
    private var useButton = NSButton()
    private var owner = ""
    private var region = ""
    private var remembered: GameAccountSelection?
    private var reading = false
    private var finishedReading = false

    private static let script = """
    if (location.origin !== 'https://account.battle.net') return JSON.stringify({failure:'origin'});
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
      async function identity() {
        const r = await fetch('/api/', {method:'POST', credentials:'include', signal:controller.signal});
        if (!r.ok) throw new Error();
        const s = await r.json();
        if (!s.authenticated || s.accountId == null) throw new Error();
        if (typeof s.accountId === 'number' && !Number.isSafeInteger(s.accountId)) throw new Error();
        return String(s.accountId);
      }
      if (await identity() !== expectedOwner) return JSON.stringify({failure:'owner'});
      const r = await fetch('/api/games-and-subs', {credentials:'include', signal:controller.signal});
      if (!r.ok) throw new Error();
      const body = await r.json();
      if (!Array.isArray(body.gameAccounts)) throw new Error();
      const rows = body.gameAccounts.filter(a => a && String(a.titleId) === '5730135').map(a => {
        const id = a.gameAccountUniqueId?.gameAccountId;
        const safeID = (typeof id === 'string' && /^[0-9]+$/.test(id)) || (typeof id === 'number' && Number.isSafeInteger(id) && id >= 0);
        if (!safeID) throw new Error();
        return {titleId:'5730135',gameAccountUniqueId:{gameAccountId:String(id)},
          gameAccountName:a.gameAccountName,gameAccountRegion:a.gameAccountRegion,
          gameAccountStatus:typeof a.gameAccountStatus === 'string' ? a.gameAccountStatus : null};
      });
      if (await identity() !== expectedOwner) return JSON.stringify({failure:'owner'});
      return JSON.stringify({gameAccounts:rows});
    } catch (_) { return JSON.stringify({failure:controller.signal.aborted ? 'timeout' : 'unavailable'}); }
    finally { clearTimeout(timer); }
    """

    func run(account: Account, gameName: String, region: Region, selected: GameAccountSelection?) async -> GameAccountSelection? {
        guard region != .cn else {
            let alert = NSAlert(); alert.messageText = "Game account selection is not available for China yet."
            alert.runModal(); return nil
        }
        owner = account.id; self.region = region.rawValue; remembered = selected
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let window = NSWindow(contentRect: NSRect(x:0,y:0,width:800,height:690), styleMask:[.titled,.closable,.resizable], backing:.buffered, defer:false)
            window.title = "Select account — \(gameName)"
            window.isReleasedWhenClosed = false; window.delegate = self
            window.contentMinSize = NSSize(width:560,height:320)
            self.window = window
            status.stringValue = "Looking up WoW accounts for \(account.displayName). Sign in below if Blizzard asks."
            popup.isEnabled = false
            let refresh = NSButton(title:"Refresh", target:self, action:#selector(refresh))
            let cancel = NSButton(title:"Cancel", target:self, action:#selector(cancel))
            cancel.keyEquivalent = "\u{1b}"
            useButton = NSButton(title:"Use account", target:self, action:#selector(choose))
            useButton.keyEquivalent = "\r"; useButton.isEnabled = false
            let web = WKWebView(frame:.zero, configuration:WebSession.makeConfiguration(account.session))
            web.navigationDelegate = self; web.underPageBackgroundColor = WebSession.launcherBackdropColor
            webView = web
            let buttons = NSStackView(views:[refresh, NSView(), cancel, useButton])
            buttons.orientation = .horizontal; buttons.spacing = 12
            let stack = NSStackView(views:[status,popup,web,buttons])
            stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
            stack.translatesAutoresizingMaskIntoConstraints = false
            window.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:20),
                stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-20),
                stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:20),
                stack.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-20),
                status.widthAnchor.constraint(equalTo:stack.widthAnchor),
                popup.widthAnchor.constraint(equalTo:stack.widthAnchor),
                web.widthAnchor.constraint(equalTo:stack.widthAnchor),
                buttons.widthAnchor.constraint(equalTo:stack.widthAnchor),
            ])
            window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
            web.load(URLRequest(url:URL(string:"https://account.battle.net/oauth2/authorization/account-settings")!))
        }
    }
    @objc private func refresh() {
        guard !reading else { return }
        finishedReading = false; accounts=[]; popup.removeAllItems(); popup.isEnabled=false; useButton.isEnabled=false
        webView?.isHidden=false
        window?.setContentSize(NSSize(width:800,height:690))
        if let webView, webView.url?.host == "account.battle.net", webView.url?.path.hasPrefix("/login") != true { read(webView) }
        else { webView?.load(URLRequest(url:URL(string:"https://account.battle.net/oauth2/authorization/account-settings")!)) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !finishedReading, webView.url?.scheme == "https", webView.url?.host == "account.battle.net",
              webView.url?.path.hasPrefix("/login") != true, webView.url?.path.hasPrefix("/oauth2") != true,
              webView.url?.path.hasPrefix("/callback") != true else { return }
        read(webView)
    }
    private func read(_ view: WKWebView) {
        guard !reading else { return }; reading=true
        Task {
            defer { reading=false }
            do {
                let value = try await view.callAsyncJavaScript(Self.script, arguments:["expectedOwner":owner], contentWorld:.defaultClient)
                guard continuation != nil, let text=value as? String, let data=text.data(using:.utf8) else { return }
                let object=try JSONSerialization.jsonObject(with:data) as? [String:Any]
                if let failure=object?["failure"] as? String {
                    status.stringValue = failure == "owner" ? "That is a different Battle.net account. Sign in as the selected identity, then Refresh." : "Couldn’t load your accounts. Complete sign-in if needed, then Refresh."
                    return
                }
                let catalog = try GameAccountCatalog.decodeWoW(data)
                accounts = catalog.gameAccounts.filter { $0.region.caseInsensitiveCompare(region) == .orderedSame }
                popup.removeAllItems()
                for account in accounts { popup.addItem(withTitle:"\(account.name) — \(account.region) · \(account.status ?? "Status unknown")") }
                if let index=accounts.firstIndex(where: { $0.accountID == remembered?.accountID }) { popup.selectItem(at:index) }
                popup.isEnabled = !accounts.isEmpty; useButton.isEnabled = !accounts.isEmpty
                finishedReading = true
                status.stringValue = accounts.isEmpty ? "No WoW accounts were found for \(region.uppercased()). Check the selected identity and region." : "Choose the WoW account to remember for this title and region. Subscription and edition access are checked by the game."
                view.isHidden = !accounts.isEmpty
                if !accounts.isEmpty { window?.setContentSize(NSSize(width:600,height:330)) }
            } catch {
                guard continuation != nil else { return }
                status.stringValue = "Couldn’t read a complete account list. Please try Refresh."
            }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        decisionHandler(url.scheme == "https" || url.absoluteString == "about:blank" ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        status.stringValue = "Couldn’t load Blizzard’s account page. Check your connection and try Refresh."
    }
    @objc private func choose() {
        guard accounts.indices.contains(popup.indexOfSelectedItem) else { return }
        let account=accounts[popup.indexOfSelectedItem]
        finish(GameAccountSelection(accountID:account.accountID,name:account.name,region:region))
    }
    @objc private func cancel() { finish(nil) }
    private func finish(_ choice: GameAccountSelection?) {
        guard let continuation else { return }; self.continuation=nil
        webView?.stopLoading(); webView?.navigationDelegate=nil; webView=nil
        window?.delegate=nil; window?.close(); window=nil
        continuation.resume(returning:choice)
    }
    func windowWillClose(_ notification:Notification) { finish(nil) }
}
