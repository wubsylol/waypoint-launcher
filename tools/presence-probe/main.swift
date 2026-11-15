import AppKit
import Foundation
import WaypointCore

@main @MainActor final class PresenceProbe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "Ready. No connection made.")
    private let output = NSTextView()
    private var button: NSButton!
    private var task: Task<Void, Never>?
    private let defaults = UserDefaults(suiteName: "io.wubs.waypoint-review")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Waypoint Presence — Explicit-zero Key Check 2"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let title = NSTextField(labelWithString: "Presence fields — explicit-zero key control")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: "Close Blizzard games on both Macs first. Uses temporary application authentication, reads friend IDs without names, then queries the same fixed fields for at most three friends, with unique_id explicitly set to zero. No subscriptions, presence updates, messages or explicit session lifecycle calls. Displays only declared field kinds and recognised game titles, never friend IDs, names or activity text. Status-field meanings remain unverified; missing data will not be labelled Offline.")
        button = NSButton(title: "Check presence fields", target: self, action: #selector(check))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        let actions = NSStackView(views: [button, cancel, NSView()])
        actions.spacing = 12
        output.isEditable = false
        output.isRichText = false
        output.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let scroll = NSScrollView()
        scroll.documentView = output
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let stack = NSStackView(views: [title, explanation, actions, status, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
        let menu = NSMenu(), root = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Presence Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu; menu.addItem(root); NSApp.mainMenu = menu
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
    }

    private func gameIsRunning() -> Bool {
        RunningProcesses.executables().contains { URL(fileURLWithPath: $0.path).lastPathComponent.hasPrefix("World of Warcraft") }
    }

    @objc private func check() {
        guard task == nil else { return }
        output.string = ""
        guard !gameIsRunning() else { status.stringValue = "Close WoW before this test."; return }
        guard let account = AccountList.load(from: defaults).active,
              let token = TokenVault(service: "io.wubs.waypoint-review: Battle.net login tokens").token(account: account.id, codename: "WoW"),
              token.accountID == account.id else { status.stringValue = "No matching saved WoW login. No connection made."; return }
        button.isEnabled = false
        status.stringValue = "Checking public build metadata, then reading a bounded presence sample…"
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if Task.isCancelled { self.output.string = ""; self.status.stringValue = "Cancelled. Saved login unchanged." }
                self.task = nil; self.button.isEnabled = true
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 20
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            do {
                let versions = VersionService(session: session)
                let game = try await versions.latest(product: "wowf", region: .us)
                let app = try await versions.latest(product: "bna", region: .us)
                try Task.checkCancellation()
                guard AccountList.load(from: self.defaults).activeID == account.id, !self.gameIsRunning(),
                      game.buildID > 0, app.buildID > 0, game.region == "us", app.region == "us" else {
                    self.status.stringValue = "Account/game state or metadata changed. No connection made."; return
                }
                let report = try await NativeGameAccounts().applicationPresencePreflight(token: token,
                    build: UInt64(game.buildID), applicationBuild: UInt64(app.buildID), region: .us)
                try Task.checkCancellation()
                guard AccountList.load(from: self.defaults).activeID == account.id else {
                    self.status.stringValue = "Account changed; result discarded."; return
                }
                let titles = report.gameTitles.sorted().joined(separator: ", ")
                self.output.string = "Friends sampled: \(report.sampledFriends)\nPresence states returned: \(report.states)\nGame-account titles in returned states: \(titles.isEmpty ? "none reported" : titles)\n\nDeclared Variant fields present:\n"
                    + (report.fieldKinds.isEmpty ? "No allowlisted field values returned." : report.fieldKinds.sorted().joined(separator: "\n"))
                    + "\n\nThis does not yet establish online/offline or current-game semantics."
                self.status.stringValue = "Presence schema check complete. Both connections closed; saved login unchanged."
            } catch is CancellationError { self.status.stringValue = "Cancelled. Saved login unchanged." }
            catch PresenceQueryFailure.refused(let code) { self.status.stringValue = "Application login and friends lookup succeeded; presence query refused (\(code)). Saved login unchanged." }
            catch PresenceQueryFailure.identity { self.status.stringValue = "Presence reply identity mismatch. Result discarded." }
            catch PresenceQueryFailure.malformed { self.status.stringValue = "Presence response exceeded supported schema bounds. Result discarded." }
            catch FriendSnapshotFailure.requestRejected(let code) { self.status.stringValue = "Friends lookup refused (\(code)); no presence request sent." }
            catch ApplicationCredentialFailure.refused(let code) { self.status.stringValue = "Application credential request refused (\(code)). Saved login unchanged." }
            catch ApplicationAuthenticationFailure.refused(let code) { self.status.stringValue = "Application authentication refused (\(code)). Saved login unchanged." }
            catch AuthenticationContextFailure.missingClientID { self.status.stringValue = "No authenticated client context; no presence query sent." }
            catch { self.status.stringValue = "Presence check could not complete. Saved login unchanged." }
        }
    }

    @objc private func cancel() { task?.cancel(); output.string = "" }
    func windowShouldClose(_ sender: NSWindow) -> Bool { task?.cancel(); NSApp.terminate(nil); return true }
    static func main() {
        let app = NSApplication.shared, delegate = PresenceProbe()
        app.setActivationPolicy(.regular); app.delegate = delegate; app.run()
    }
}
