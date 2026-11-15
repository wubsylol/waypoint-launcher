import AppKit
import Foundation
import WaypointCore

@main @MainActor final class SessionLifecycleProbe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "Not started. No connection made.")
    private let output = NSTextView()
    private var button: NSButton!
    private var task: Task<Void, Never>?
    private var attempted = false
    private let defaults = UserDefaults(suiteName: "io.wubs.waypoint-review")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Waypoint — App Session Lifecycle Test 2"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "Temporary application session — explicit test")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: "Run only after agreeing to this test. Close Blizzard games and official Battle.net launchers on both Macs. This requests a fresh App credential, authenticates, creates one session bound to its own App handle, verifies the reply/callback, then requests destruction in the same context and waits up to five seconds for its callback (within the overall connection deadline). It may affect another client or visible presence. No friends/presence queries, status updates or messages are sent. A disconnect, cancellation or failed identity check can leave cleanup unconfirmed; there is no automatic retry or reconnect. Saved login is not replaced.")
        button = NSButton(title: "Create and clean up App session", target: self, action: #selector(run))
        let stop = NSButton(title: "Stop connection", target: self, action: #selector(stop))
        let actions = NSStackView(views: [button, stop, NSView()]); actions.spacing = 12
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
                let report = try await NativeGameAccounts().applicationSessionLifecycleTest(token: token,
                    build: UInt64(game.buildID), applicationBuild: UInt64(app.buildID), region: .us)
                func yes(_ value: Bool) -> String { value ? "yes" : "no" }
                let same = report.instanceMatchesAuthenticationContext.map(yes) ?? "unknown"
                let refusal = report.refusalCode.map { String($0) } ?? "none reported"
                self.output.string = "Creation response owner/binding verified: \(yes(report.creationResponseVerified))\nCreation callback verified: \(yes(report.creationCallbackVerified))\nInstance matches authentication context: \(same)\nDestroy request accepted: \(yes(report.destroyRequestAccepted))\nMatching destruction callback observed: \(yes(report.destructionCallbackVerified))\nRefusal code: \(refusal)\n\n\(report.outcome)\n\nNo identifiers or keys are shown. No automatic retry."
                self.status.stringValue = "Lifecycle test finished; connection closed. Read the cleanup outcome above. Saved login data unchanged."
            } catch {
                // Core returns a report for every failure after possible CreateSession
                // submission. Throws here therefore precede explicit creation.
                self.status.stringValue = "Stopped before explicit session creation. Saved login unchanged."
            }
        }
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
