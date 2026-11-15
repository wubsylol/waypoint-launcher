import AppKit
import Foundation
import WaypointCore

@main @MainActor final class FriendsProbe: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "")
    private let output = NSTextView()
    private var button: NSButton!
    private var revealButton: NSButton!
    private let search = NSSearchField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var snapshotNames: [String] = []
    private var visibleNames: [String] = []
    private var snapshotOwner: String?
    private var snapshotLabel = ""
    private var namesVisible = false
    private var task: Task<Void, Never>?
    private let defaults = UserDefaults(suiteName: "io.wubs.waypoint-review")!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 520), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Waypoint Friends — Local Friends Viewer 18"
        window.isReleasedWhenClosed = false; window.delegate = self
        let title = NSTextField(labelWithString: "Battle.net friends — local viewer")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: "Requests a temporary App credential using the saved WoW login, closes the source connection, authenticates as App, then makes one bounded friends lookup using the owner-verified application context. Close Blizzard games on both Macs first. Requests BattleTags explicitly. No explicit session creation/destruction, subscription, messages, presence updates or saved-login writes. Names stay hidden until you choose Show Friends. Only BattleTags are shown locally; no real names or IDs are displayed or saved. This is a snapshot, not live presence or messaging.")
        button = NSButton(title: "Refresh Friends", target: self, action: #selector(readFriends))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelRead))
        revealButton = NSButton(title: "Show Friends", target: self, action: #selector(toggleNames))
        revealButton.isEnabled = false
        let actions = NSStackView(views: [button, revealButton, cancel, NSView()]); actions.spacing = 10
        output.isEditable = false; output.isRichText = false; output.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("battleTag"))
        column.title = "BattleTag"
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.rowHeight = 28
        table.autoresizingMask = [.width]
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Friends snapshot")
        search.placeholderString = "Filter BattleTags"
        search.delegate = self
        search.isHidden = true
        scroll.documentView = output
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let stack = NSStackView(views: [title, explanation, actions, status, search, scroll]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor), explanation.widthAnchor.constraint(equalTo: stack.widthAnchor), status.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
        status.stringValue = "Ready. No connection has been made."
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Friends Viewer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    private func gameIsRunning() -> Bool {
        RunningProcesses.executables().contains { URL(fileURLWithPath: $0.path).lastPathComponent.hasPrefix("World of Warcraft") }
    }
    @objc private func readFriends() {
        guard task == nil else { return }
        clearSnapshot()
        guard !gameIsRunning() else { status.stringValue = "Close World of Warcraft before this test."; return }
        guard let account = AccountList.load(from: defaults).active else { status.stringValue = "Select an account in Waypoint first."; return }
        let vault = TokenVault(service: "io.wubs.waypoint-review: Battle.net login tokens")
        guard let token = vault.token(account: account.id, codename: "WoW"), token.accountID == account.id else { status.stringValue = "No saved WoW login is available. This test will not request another sign-in."; return }
        button.isEnabled = false; status.stringValue = "Checking public build metadata, then testing friends access in the application context…"
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if Task.isCancelled {
                    self.clearSnapshot()
                    self.status.stringValue = "Cancelled. Snapshot cleared; saved login unchanged."
                }
                self.task = nil; self.button.isEnabled = true
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = false; configuration.timeoutIntervalForRequest = 10; configuration.timeoutIntervalForResource = 20
            let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
            do {
                let versions = VersionService(session: session)
                let version = try await versions.latest(product: "wowf", region: .us)
                let applicationVersion = try await versions.latest(product: "bna", region: .us)
                try Task.checkCancellation()
                guard AccountList.load(from: self.defaults).activeID == account.id, !self.gameIsRunning(), version.buildID > 0, version.region == "us", applicationVersion.buildID > 0, applicationVersion.region == "us" else {
                    self.status.stringValue = "Account changed, WoW opened, or build metadata was unavailable. No connection made."; return
                }
                let friends = try await NativeGameAccounts().applicationFriendsPreflight(token: token, build: UInt64(version.buildID), applicationBuild: UInt64(applicationVersion.buildID), region: .us)
                try Task.checkCancellation()
                guard AccountList.load(from: self.defaults).activeID == account.id else { self.status.stringValue = "Account changed; result discarded."; return }
                self.snapshotOwner = account.id
                self.snapshotLabel = account.displayName
                self.snapshotNames = friends.enumerated().map { index, friend in
                    friend.battleTag ?? "Friend \(index + 1) — BattleTag unavailable"
                }
                self.output.string = "Friends snapshot received: \(friends.count) records.\nChoose Show Friends to view BattleTags locally. No real names or IDs are shown.\nBoth connections closed; saved login unchanged."
                self.revealButton.isEnabled = !friends.isEmpty
                self.status.stringValue = "\(friends.count) friends for \(account.displayName). Snapshot only; online status is not retrieved."
            } catch is CancellationError { self.status.stringValue = "Cancelled. No saved login changed." }
            catch ApplicationCredentialFailure.refused(let code) { self.status.stringValue = "Signed in successfully; application credential request refused (\(code)). Saved login unchanged." }
            catch ApplicationCredentialFailure.format { self.status.stringValue = "Signed in successfully; application credential format was not recognized. Saved login unchanged." }
            catch FriendSnapshotFailure.requestRejected(let code) { self.status.stringValue = "Application authentication succeeded; friends request refused (\(code)). Saved login unchanged." }
            catch AuthenticationContextFailure.missingClientID { self.status.stringValue = "Application authentication succeeded; no usable authenticated client context was returned. No friends request sent." }
            catch ApplicationAuthenticationFailure.refused(let code) { self.status.stringValue = "App credential issued; application authentication refused (\(code)). Saved login unchanged." }
            catch ApplicationAuthenticationFailure.owner { self.status.stringValue = "App credential issued; application context identity mismatch. Result discarded." }
            catch ApplicationAuthenticationFailure.unavailable { self.status.stringValue = "App credential issued; application/friends check could not complete. Saved login unchanged." }
            catch NativeGameAccounts.Failure.rejected(let code) { self.status.stringValue = "Connection/authentication refused (status \(code)); application credential preflight was not completed. Saved login unchanged." }
            catch NativeGameAccounts.Failure.owner { self.status.stringValue = "Account identity mismatch. Result discarded." }
            catch { self.status.stringValue = "Could not complete the application friends preflight. Saved login unchanged." }
        }
    }
    private func clearSnapshot() {
        snapshotNames = []; visibleNames = []; snapshotOwner = nil; snapshotLabel = ""
        namesVisible = false
        revealButton?.isEnabled = false
        revealButton?.title = "Show Friends"
        search.stringValue = ""; search.isHidden = true
        table.reloadData(); scroll.documentView = output; output.string = ""
    }

    private func validateSnapshotOwner() -> Bool {
        guard let owner = snapshotOwner, AccountList.load(from: defaults).activeID == owner else {
            clearSnapshot()
            status.stringValue = "Account changed. Snapshot cleared; refresh to load this account’s friends."
            return false
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if snapshotOwner != nil { _ = validateSnapshotOwner() }
    }

    @objc private func toggleNames() {
        guard validateSnapshotOwner() else { return }
        namesVisible.toggle()
        revealButton.title = namesVisible ? "Hide Friends" : "Show Friends"
        search.isHidden = !namesVisible
        if namesVisible {
            scroll.documentView = table
            filterNames()
        } else {
            search.stringValue = ""; visibleNames = []; table.reloadData()
            scroll.documentView = output
            status.stringValue = "\(snapshotNames.count) friends for \(snapshotLabel). Names hidden."
        }
    }

    private func filterNames() {
        guard validateSnapshotOwner(), namesVisible else { return }
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleNames = query.isEmpty ? snapshotNames : snapshotNames.filter { $0.localizedStandardContains(query) }
        table.reloadData()
        status.stringValue = "\(visibleNames.count) of \(snapshotNames.count) friends for \(snapshotLabel). Snapshot only."
    }

    func controlTextDidChange(_ notification: Notification) { filterNames() }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleNames.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleNames.indices.contains(row) else { return nil }
        return NSTextField(labelWithString: visibleNames[row])
    }

    @objc private func cancelRead() {
        task?.cancel(); clearSnapshot()
        status.stringValue = "Cancelled. Snapshot cleared; saved login unchanged."
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { task?.cancel(); NSApp.terminate(nil); return true }
    static func main() {
        let app = NSApplication.shared
        let delegate = FriendsProbe()
        app.setActivationPolicy(.regular); app.delegate = delegate; app.run()
    }

}