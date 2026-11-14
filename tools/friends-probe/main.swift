import AppKit
import Foundation
import WaypointCore

@main @MainActor final class FriendsProbe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "")
    private let output = NSTextView()
    private var button: NSButton!
    private var task: Task<Void, Never>?
    private let defaults = UserDefaults(suiteName: "io.wubs.waypoint-review")!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 480), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Waypoint Friends — Read-only Experiment (friends identity control 10)"
        window.isReleasedWhenClosed = false; window.delegate = self
        let title = NSTextField(labelWithString: "Battle.net friends identity-header control")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: "Uses the selected Waypoint account’s saved WoW login. Close WoW first. Does not send messages, change friendships, or save the returned list. Includes only the current connection’s server-provided identity in the original v2 friends query header; sign-in is unchanged. It sends no session creation, restoration or destruction requests, changes no friendships and never shows the connection identifier.")
        explanation.textColor = .secondaryLabelColor
        button = NSButton(title: "Read friends with identity header", target: self, action: #selector(readFriends))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelRead))
        let actions = NSStackView(views: [button, cancel, NSView()]); actions.spacing = 10
        output.isEditable = false; output.isRichText = false; output.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        let scroll = NSScrollView(); scroll.documentView = output; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let stack = NSStackView(views: [title, explanation, actions, status, scroll]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor), status.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
        status.stringValue = "Ready. No connection has been made."
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    private func gameIsRunning() -> Bool {
        RunningProcesses.executables().contains { URL(fileURLWithPath: $0.path).lastPathComponent.hasPrefix("World of Warcraft") }
    }
    @objc private func readFriends() {
        guard task == nil else { return }
        output.string = ""
        guard !gameIsRunning() else { status.stringValue = "Close World of Warcraft before this test."; return }
        guard let account = AccountList.load(from: defaults).active else { status.stringValue = "Select an account in Waypoint first."; return }
        let vault = TokenVault(service: "io.wubs.waypoint-review: Battle.net login tokens")
        guard let token = vault.token(account: account.id, codename: "WoW"), token.accountID == account.id else { status.stringValue = "No saved WoW login is available. This test will not request another sign-in."; return }
        button.isEnabled = false; status.stringValue = "Checking public build metadata, then requesting friends with the identity header…"
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil; self.button.isEnabled = true }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = false; configuration.timeoutIntervalForRequest = 10; configuration.timeoutIntervalForResource = 20
            let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
            do {
                let version = try await VersionService(session: session).latest(product: "wowf", region: .us)
                try Task.checkCancellation()
                guard AccountList.load(from: self.defaults).activeID == account.id, !self.gameIsRunning(), version.buildID > 0, version.region == "us" else {
                    self.status.stringValue = "Account changed, WoW opened, or build metadata was unavailable. No connection made."; return
                }
                let friends = try await NativeGameAccounts().friends(token: token, build: UInt64(version.buildID), region: .us, includeConnectionIdentity: true)
                try Task.checkCancellation()
                guard AccountList.load(from: self.defaults).activeID == account.id else { self.status.stringValue = "Account changed; result discarded."; return }
                self.output.string = friends.enumerated().map { $0.element.battleTag ?? "Friend \($0.offset + 1) — BattleTag unavailable" }.joined(separator: "\n")
                self.status.stringValue = "Friends identity control returned \(friends.count) friends. Connection closed."
            } catch is CancellationError { self.status.stringValue = "Cancelled. No saved login changed." }
            catch FriendSnapshotFailure.requestRejected(let code) {
                let reason = code == 3025 ? "RPC method disabled" : "request refused"
                self.status.stringValue = "Signed in successfully; friends lookup with identity header failed: \(reason) (\(code)). Saved login unchanged."
            }
            catch NativeGameAccounts.Failure.rejected(let code) { self.status.stringValue = "Connection/authentication refused (status \(code)); friends query was not completed. Saved login unchanged." }
            catch let error as SessionDiagnosticFailure { self.status.stringValue = error.localizedDescription + " Saved login unchanged." }
            catch NativeGameAccounts.Failure.owner { self.status.stringValue = "Account identity mismatch. Result discarded." }
            catch { self.status.stringValue = "Could not complete the friends identity control. Saved login unchanged." }
        }
    }
    @objc private func cancelRead() { task?.cancel(); output.string = "" }
    func windowShouldClose(_ sender: NSWindow) -> Bool { task?.cancel(); NSApp.terminate(nil); return true }
    static func main() {
        let app = NSApplication.shared
        let delegate = FriendsProbe()
        app.setActivationPolicy(.regular); app.delegate = delegate; app.run()
    }

}