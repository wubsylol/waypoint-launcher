import AppKit
import Foundation
import WaypointCore

@main @MainActor final class SessionLifecycleProbe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "Not started. No connection made.")
    private let output = NSTextView()
    private var button: NSButton!
    private var showButton: NSButton!
    private var rows: [FriendPresenceRow] = []
    private var snapshotOwner: String?
    private var diagnosticText = ""
    private var showingFriends = false
    private var task: Task<Void, Never>?
    private var ownerMonitor: Task<Void, Never>?
    private var attempted = false
    private let defaults = UserDefaults(suiteName: "io.wubs.waypoint-review")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Waypoint — Friends Presence Viewer 7"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "Temporary application session — explicit test")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: "Run only after agreeing to this test. Close Blizzard games and official Battle.net launchers on both Macs. This requests a fresh App credential, authenticates, creates one session bound to its own App handle, verifies the reply/callback, then requests destruction in the same context and waits up to five seconds for its callback (within the overall connection deadline). It may affect another client or visible presence. Before cleanup, reads fresh friend IDs and queries account-only presence for at most 64 friends, with a 20-second between-request sampling budget (an in-flight request may continue to the overall 35-second deadline). BattleTags, status, game titles and activity are available only through Show Friends after verified cleanup; IDs are never displayed or saved. No status updates, subscriptions or messages are sent. A disconnect, cancellation or failed identity check can leave cleanup unconfirmed; there is no automatic retry or reconnect. Saved login is not replaced.")
        button = NSButton(title: "Read friends and presence", target: self, action: #selector(run))
        let stop = NSButton(title: "Stop connection", target: self, action: #selector(stop))
        showButton = NSButton(title: "Show Friends", target: self, action: #selector(showFriends)); showButton.isEnabled = false
        let actions = NSStackView(views: [button, stop, showButton, NSView()]); actions.spacing = 12
        output.isEditable = false; output.isRichText = false
        output.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let scroll = NSScrollView(); scroll.documentView = output
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let stack = NSStackView(views: [title, explanation, actions, status, scroll])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor), status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240)
        ])
        let menu = NSMenu(), root = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Lifecycle Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu; menu.addItem(root); NSApp.mainMenu = menu
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
        ownerMonitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                self?.discardChangedOwner()
            }
        }
    }
    private func conflictingClientIsRunning() -> Bool {
        RunningProcesses.executables().contains {
            let name = URL(fileURLWithPath: $0.path).lastPathComponent
            return name.hasPrefix("World of Warcraft") || name == "Battle.net" || name.hasPrefix("Battle.net Helper")
        }
    }
    @objc private func run() {
        guard !attempted, task == nil else { return }
        guard !conflictingClientIsRunning() else { status.stringValue = "Close WoW and the official Battle.net launcher before this test."; return }
        guard let account = AccountList.load(from: defaults).active,
              let token = TokenVault(service: "io.wubs.waypoint-review: Battle.net login tokens").token(account: account.id, codename: "WoW"),
              token.accountID == account.id else { status.stringValue = "No matching saved WoW login. No request made."; return }
        attempted = true; button.isEnabled = false
        status.stringValue = "Checking public builds, then performing the agreed single lifecycle test…"
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            let config = URLSessionConfiguration.ephemeral
            config.waitsForConnectivity = false; config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 20
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            do {
                let versions = VersionService(session: session)
                let game = try await versions.latest(product: "wowf", region: .us)
                let app = try await versions.latest(product: "bna", region: .us)
                try Task.checkCancellation()
                guard AccountList.load(from: self.defaults).activeID == account.id, !self.conflictingClientIsRunning(),
                      game.buildID > 0, app.buildID > 0, game.region == "us", app.region == "us" else {
                    self.status.stringValue = "Account/client state or metadata changed. No lifecycle request made."; return
                }
                let report = try await NativeGameAccounts().applicationFriendsPresenceViewer(token: token,
                    build: UInt64(game.buildID), applicationBuild: UInt64(app.buildID), region: .us)
                func yes(_ value: Bool) -> String { value ? "yes" : "no" }
                let same = report.instanceMatchesAuthenticationContext.map(yes) ?? "unknown"
                let refusal = report.refusalCode.map { String($0) } ?? "none reported"
                let sample = report.presenceSummary.map { "Sampled friends: \($0.sampledFriends)\nStates: \($0.states)\nField kinds: \($0.fieldKinds.sorted().joined(separator: ", "))\nSelected status counts: \($0.selectedStatusCounts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", "))\nOnline game handles: \($0.onlineGameHandles)\nGame titles: \($0.gameTitles.sorted().joined(separator: ", "))" } ?? "No presence sample returned"
                self.output.string = "Presence: \(report.presenceStatus)\n\(sample)\n\nCreation response owner/binding verified: \(yes(report.creationResponseVerified))\nCreation callback verified: \(yes(report.creationCallbackVerified))\nInstance matches authentication context: \(same)\nDestroy request accepted: \(yes(report.destroyRequestAccepted))\nMatching destruction callback observed: \(yes(report.destructionCallbackVerified))\nRefusal code: \(refusal)\n\n\(report.outcome)\n\nNo identifiers or keys are shown. No automatic retry."
                self.diagnosticText = self.output.string
                guard AccountList.load(from: self.defaults).activeID == account.id, !Task.isCancelled else {
                    self.rows = []; self.status.stringValue = "Account changed or cancelled; private rows discarded. Cleanup outcome remains above."; return
                }
                self.rows = report.friendPresenceRows; self.snapshotOwner = account.id
                self.showButton.isEnabled = !self.rows.isEmpty
                self.status.stringValue = "Viewer sample complete (\(report.presenceComplete ? "full roster" : "partial or unavailable")). Lifecycle test finished; connection closed. Read the cleanup outcome above. Saved login data unchanged."
            } catch {
                // Core returns a report for every failure after possible CreateSession
                // submission. Throws here therefore precede explicit creation.
                self.status.stringValue = "Stopped before explicit session creation. Saved login unchanged."
            }
        }
    }
    private func discardChangedOwner() {
        guard let snapshotOwner, AccountList.load(from: defaults).activeID != snapshotOwner else { return }
        rows = []; self.snapshotOwner = nil; showingFriends = false
        showButton.isEnabled = false; showButton.title = "Show Friends"
        output.string = diagnosticText
        status.stringValue = "Account changed; private rows cleared. Cleanup outcome remains above."
    }
    func applicationDidBecomeActive(_ notification: Notification) { discardChangedOwner() }
    func windowDidBecomeKey(_ notification: Notification) { discardChangedOwner() }
    @objc private func showFriends() {
        guard task == nil, AccountList.load(from: defaults).activeID == snapshotOwner else {
            rows = []; showButton.isEnabled = false; output.string = diagnosticText; return
        }
        showingFriends.toggle()
        showButton.title = showingFriends ? "Hide Friends" : "Show Friends"
        if showingFriends {
            output.string = rows.enumerated().map { index, row in
                let name = row.battleTag ?? "BattleTag unavailable (friend \(index + 1))"
                let games = row.games.isEmpty ? "" : " · " + row.games.joined(separator: ", ")
                let activity = row.activity.map { "\n  " + $0 } ?? ""
                return "\(name) — \(row.status)\(games)\(activity)"
            }.joined(separator: "\n\n")
        } else { output.string = diagnosticText }
    }
    @objc private func stop() {
        guard task != nil else { return }
        status.stringValue = "Stopping connection. If creation was submitted, cleanup may be unconfirmed."
        task?.cancel()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if task != nil { stop(); return false }
        NSApp.terminate(nil); return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if task != nil { stop(); return .terminateCancel }
        return .terminateNow
    }
    static func main() {
        let app = NSApplication.shared, delegate = SessionLifecycleProbe()
        app.setActivationPolicy(.regular); app.delegate = delegate; app.run()
    }
}
