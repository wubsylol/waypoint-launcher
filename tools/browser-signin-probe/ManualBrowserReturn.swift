import AppKit
import Foundation
import WaypointCore

@main @MainActor final class ManualBrowserReturn: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let field = NSSecureTextField()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var validateButton = NSButton()
    private var launchButton = NSButton()
    private let spinner = NSProgressIndicator()
    private var task: Task<Void, Never>?
    private var token: LoginToken?
    private var game: Game?
    private var knownGames: [Game] = []
    private var verifiedChoice: GameAccountSelection?
    private var owner: String?
    private var testing = false
    private let defaults = UserDefaults(suiteName: "io.wubs.waypoint-review")!
    static func main() {
        let app = NSApplication.shared; let delegate = ManualBrowserReturn()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        owner = AccountList.load(from: defaults).activeID
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:560,height:340),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = "Waypoint — browser return test"
        window.isReleasedWhenClosed = false; window.delegate = self
        let title = NSTextField(labelWithString: "Sign in using Safari")
        title.font = .systemFont(ofSize:21,weight:.semibold)
        let instructions = NSTextField(wrappingLabelWithString: "1. Open Blizzard’s sign-in page in Safari and sign in normally.\n2. When Safari reaches its localhost error page, press ⌘L then ⌘C.\n3. Paste that return address below. It contains a temporary game ticket; keep it private.")
        instructions.textColor = .secondaryLabelColor
        let open = NSButton(title:"Open Battle.net in Safari",target:self,action:#selector(openBrowser))
        field.placeholderString = "Paste the complete browser return address"
        field.setAccessibilityLabel("Private browser return address")
        validateButton = NSButton(title:"Validate return",target:self,action:#selector(validateReturn))
        validateButton.keyEquivalent = "\r"
        launchButton = NSButton(title:"Launch Forever (test)",target:self,action:#selector(launchGame));launchButton.isEnabled=false
        let cancel = NSButton(title:"Close",target:self,action:#selector(close));cancel.keyEquivalent="\u{1b}"
        spinner.style = .spinning;spinner.controlSize = .small;spinner.isDisplayedWhenStopped=false
        let progress = NSStackView(views:[spinner,status]);progress.spacing=10
        let buttons = NSStackView(views:[validateButton,NSView(),launchButton,cancel]);buttons.spacing=10
        let stack = NSStackView(views:[title,instructions,open,field,progress,NSView(),buttons])
        stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:24),
            stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-24),
            stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:24),
            stack.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-20),
            instructions.widthAnchor.constraint(equalTo:stack.widthAnchor),field.widthAnchor.constraint(equalTo:stack.widthAnchor),
            progress.widthAnchor.constraint(equalTo:stack.widthAnchor),buttons.widthAnchor.constraint(equalTo:stack.widthAnchor),
        ])
        status.stringValue = owner == nil ? "Open Waypoint and select your Battle.net account first." : "The test does not change Waypoint’s saved Keychain login."
        validateButton.isEnabled = owner != nil
        window.center();window.makeKeyAndOrderFront(nil);NSApp.activate()
    }
    @objc private func openBrowser() {
        let url = BattleNetLogin.url(codename:"WoW",region:.us)
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.Safari") else { return }
        NSWorkspace.shared.open([url],withApplicationAt:safari,configuration:NSWorkspace.OpenConfiguration())
    }
    private func currentIdentityMatches() -> Bool { AccountList.load(from:defaults).activeID == owner }
    private func hasRunningWoW(_ games:[Game]) -> Bool {
        let processes = RunningProcesses.executables()
        return games.contains { $0.family == .worldOfWarcraft && $0.appURL.map { RunningProcesses.isRunning(bundle:$0,in:processes) } == true }
    }
    @objc private func validateReturn() {
        guard !testing, let owner, currentIdentityMatches() else { return }
        token=nil;game=nil;verifiedChoice=nil;launchButton.isEnabled=false
        let text=field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        field.stringValue=""
        guard text.utf8.count<=8192, let url=URL(string:text),url.scheme=="http",url.host=="localhost",url.port==0,
              url.path.isEmpty || url.path=="/",url.user==nil,url.password==nil,
              let items=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems,
              items.filter({$0.name=="ST"}).count==1,
              let candidate=LoginToken(callbackURL:url),candidate.accountID==owner else {
            status.stringValue="That isn’t a valid game return for the selected Waypoint account. No saved login was changed.";return
        }
        testing=true;validateButton.isEnabled=false;spinner.startAnimation(nil)
        status.stringValue="Checking game authorization with Blizzard…"
        task=Task { [weak self] in
            guard let self else { return }
            defer { self.testing=false;self.validateButton.isEnabled=true;self.spinner.stopAnimation(nil) }
            do {
                let games=await Task.detached {
                    GameLibrary(searchRoots:[URL(fileURLWithPath:"/Volumes/External HD/Battle.Net/World of Warcraft",isDirectory:true)]).games()
                }.value
                guard !Task.isCancelled else { return }
                guard !self.hasRunningWoW(games) else { self.status.stringValue="Close WoW before validating a new game session.";return }
                guard let forever=games.first(where:{$0.install.productCode=="wowf"}),
                      let app=forever.appURL,let bundle=Bundle(url:app),let version=bundle.object(forInfoDictionaryKey:"CFBundleVersion") as? String,
                      let build=UInt64(version.split(separator:".").last ?? "") else { self.status.stringValue="The Forever installation couldn’t be read.";return }
                let accounts=try await NativeGameAccounts().discover(token:candidate,build:build,region:.us)
                guard !Task.isCancelled,self.currentIdentityMatches() else { return }
                let plan=try GameLauncher.plan(for:forever,region:.us)
                guard let choice=GameAccountSelections.load(from:self.defaults).choice(owner:owner,uid:forever.id,region:plan.region.rawValue),
                      accounts.contains(where:{$0.accountID==choice.accountID && $0.name==choice.name}) else {
                    self.status.stringValue="The saved Forever licence was not in the verified list. Select a current licence in Waypoint first.";return
                }
                self.token=candidate;self.game=forever;self.knownGames=games;self.verifiedChoice=choice;self.launchButton.isEnabled=true
                self.status.stringValue="Browser ticket accepted for the expected account and saved Forever licence. Ready for a real launch test."
                print("Manual browser return validated by native game service:",true)
            } catch {
                if !Task.isCancelled { self.status.stringValue="Blizzard couldn’t validate this game ticket. Your saved Keychain login is unchanged." }
                print("Manual browser return validation stopped without changing saved authorization.")
            }
        }
    }
    @objc private func launchGame() {
        guard !testing,let token,let game,let owner,currentIdentityMatches(),!hasRunningWoW(knownGames) else { return }
        do {
            var plan=try GameLauncher.plan(for:game,region:.us)
            guard let choice=GameAccountSelections.load(from:defaults).choice(owner:owner,uid:game.id,region:plan.region.rawValue), choice==verifiedChoice else {
                status.stringValue="The selected licence changed. Validate the browser return again before launching.";return
            }
            plan.gameAccount=choice.name
            _=try GameLauncher.launch(plan,token:token,gameName:game.displayName)
            self.token=nil;launchButton.isEnabled=false;validateButton.isEnabled=false
            status.stringValue="Forever launched using the browser ticket and your saved licence. Check the character list. Waypoint’s Keychain login was not replaced."
            print("Manual browser return launched Forever using its saved licence.")
        } catch { status.stringValue="Couldn’t launch Forever. Waypoint’s saved Keychain login is unchanged." }
    }
    @objc private func close() { task?.cancel();token=nil;field.stringValue="";NSApp.terminate(nil) }
    func windowShouldClose(_ sender:NSWindow)->Bool { close();return true }
}
