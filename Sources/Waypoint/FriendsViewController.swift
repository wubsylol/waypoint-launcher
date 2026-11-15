import AppKit
import WaypointCore

/// Experimental, manually refreshed social snapshot. No message actions or disk cache.
@MainActor
final class FriendsViewController: NSViewController, NSSearchFieldDelegate {
    #if DEBUG
    private let isDemo = ProcessInfo.processInfo.arguments.contains("--friends-demo")
    #else
    private let isDemo = false
    #endif
    private let model: AppModel
    private var owner: String?
    private var rows: [FriendPresenceRow] = []
    private var task: Task<Void, Never>?
    private var lastRefresh: Date?
    private var showsOffline = false
    private let account = NSTextField.label(.caption1, color: .secondaryLabelColor)
    private let summary = NSTextField.label(.caption1, color: .secondaryLabelColor)
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let search = NSSearchField()
    private let refresh = NSButton()
    private let spinner = NSProgressIndicator.spinner()
    private let list = FriendsListStack()
    private let offline = NSButton()
    private var snapshotComplete = false

    init(model: AppModel) { self.model = model; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        spinner.isDisplayedWhenStopped = false
        let title = NSTextField(labelWithString: "Friends")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let badge = NSTextField(labelWithString: "EXPERIMENTAL")
        badge.font = .systemFont(ofSize: 9, weight: .semibold)
        badge.textColor = .tertiaryLabelColor
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh friends")
        refresh.bezelStyle = .texturedRounded; refresh.imagePosition = .imageOnly
        refresh.target = self; refresh.action = #selector(refreshFriends)
        refresh.toolTip = "Refresh friends. Close Blizzard games on all devices first."
        refresh.setAccessibilityLabel("Refresh friends")
        let heading = NSStackView(views: [title, badge, NSView(), spinner, refresh]); heading.spacing = 8
        search.placeholderString = "Search friends"; search.delegate = self
        notice.font = .systemFont(ofSize: 12); notice.textColor = .secondaryLabelColor
        notice.maximumNumberOfLines = 0
        list.orientation = .vertical; list.alignment = .leading; list.spacing = 4
        list.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView(); scroll.documentView = list
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let root = NSStackView(views: [heading, account, search, summary, notice, scroll])
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 14, bottom: 12, right: 14)
        for child in [heading, account, search, summary, notice, scroll] as [NSView] {
            child.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28).isActive = true
        }
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        view = root
        observeChanges { [weak self] in self?.accountChanged() }
        if isDemo {
            rows = [
                FriendPresenceRow(battleTag: "Jaina#1201", status: "Online", games: ["World of Warcraft"], activity: "Exploring Azeroth"),
                FriendPresenceRow(battleTag: "Lorath#1202", status: "Busy", games: ["Diablo IV"], activity: "Sanctuary"),
                FriendPresenceRow(battleTag: "Chromie#1203", status: "Away", games: ["Battle.net app"], activity: nil),
                FriendPresenceRow(battleTag: "Anduin#1204", status: "Online", games: ["Hearthstone"], activity: "In a match"),
                FriendPresenceRow(battleTag: "Thrall#1205", status: "Offline", games: [], activity: nil),
            ]
            lastRefresh = Date(); snapshotComplete = true
            notice.stringValue = "Sample data · No connection made"; refresh.isEnabled = false
        }
        render()
    }

    private func accountChanged() {
        let active = model.activeAccount
        account.stringValue = active?.displayName ?? "Not signed in"
        refresh.isEnabled = active != nil && task == nil && !model.isSigningIn && !model.experimentalFriendsCleanupUnconfirmed
        guard owner != active?.id else { return }
        task?.cancel(); rows = []; lastRefresh = nil; snapshotComplete = false
        owner = active?.id; notice.stringValue = ""; search.stringValue = ""
        render()
    }

    @objc private func refreshFriends() {
        guard !isDemo, task == nil, let active = model.activeAccount else { return }
        owner = active.id
        refresh.isEnabled = false; spinner.startAnimation(nil)
        // Retain existing rows as an explicitly dated snapshot during refresh.
        notice.stringValue = "Refreshing… Close Blizzard games on all devices."
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.task = nil; self.spinner.stopAnimation(nil)
                self.refresh.isEnabled = self.model.activeAccount != nil && !self.model.experimentalFriendsCleanupUnconfirmed
            }
            do {
                let report = try await self.model.experimentalFriendsSnapshot(accountID: active.id)
                if self.model.experimentalFriendsCleanupUnconfirmed {
                    self.notice.stringValue = "Connection closed, but session cleanup could not be confirmed. Stop testing and report this result."
                    self.render(); return
                }
                guard self.owner == active.id, self.model.activeAccount?.id == active.id, !Task.isCancelled else { return }
                guard report.destroyRequestAccepted && report.destructionCallbackVerified else {
                    self.notice.stringValue = "Friends unavailable. \(report.outcome). Your saved login is unchanged."
                    self.render(); return
                }
                guard report.presenceSummary != nil else {
                    self.notice.stringValue = "Friends could not be refreshed. \(report.presenceStatus). Your saved login is unchanged."
                    self.render(); return
                }
                self.rows = report.friendPresenceRows; self.snapshotComplete = report.presenceComplete
                self.lastRefresh = Date(); self.notice.stringValue = ""
                self.render()
            } catch is CancellationError {
                if self.owner == active.id { self.notice.stringValue = "Refresh stopped. The previous snapshot has been kept." }
            } catch {
                if self.owner == active.id { self.notice.stringValue = (error as? FriendsPanelFailure)?.message ?? "Couldn’t connect to friends. Your saved login is unchanged." }
            }
        }
    }

    func controlTextDidChange(_ notification: Notification) { render() }
    @objc private func toggleOffline() { showsOffline.toggle(); render() }

    private func render() {
        for child in list.arrangedSubviews { list.removeArrangedSubview(child); child.removeFromSuperview() }
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = rows.filter { row in
            query.isEmpty || ([row.battleTag ?? "", row.status] + row.games + [row.activity ?? ""])
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted { ($0.battleTag ?? "").localizedStandardCompare($1.battleTag ?? "") == .orderedAscending }
        let unknown = filtered.filter { $0.status == "Status unavailable" }
        let online = filtered.filter { $0.status != "Offline" && $0.status != "Status unavailable" }, away = filtered.filter { $0.status == "Offline" }
        if let lastRefresh {
            let time = lastRefresh.formatted(date: .omitted, time: .shortened)
            let onlineCount = rows.filter { $0.status != "Offline" && $0.status != "Status unavailable" }.count
            summary.stringValue = "\(onlineCount) online · Updated \(time)\(snapshotComplete ? "" : " · Partial list")"
        } else { summary.stringValue = "Manual refresh · Nothing saved on this Mac" }
        if rows.isEmpty {
            addEmpty(model.activeAccount == nil ? "Sign in to see your friends" : (lastRefresh == nil ? "Your friends, alongside your games" : "No friends returned"),
                detail: lastRefresh == nil ? "Refresh to load a private snapshot of statuses and games. Close Blizzard games before refreshing." : "Try refreshing again later.")
        } else if filtered.isEmpty { addEmpty("No matching friends", detail: "Try a different name or game.") }
        else {
            addSection("ONLINE", count: online.count)
            for row in online { addRow(row) }
            if !unknown.isEmpty {
                addSection("STATUS UNAVAILABLE", count: unknown.count)
                for row in unknown { addRow(row) }
            }
            offline.title = "\(showsOffline ? "▾" : "▸")  OFFLINE  \(away.count)"
            offline.font = .systemFont(ofSize: 10, weight: .semibold); offline.contentTintColor = .secondaryLabelColor
            offline.isBordered = false; offline.alignment = .left; offline.target = self; offline.action = #selector(toggleOffline)
            add(offline)
            if showsOffline { for row in away { addRow(row) } }
        }
        notice.isHidden = notice.stringValue.isEmpty
    }
    private func add(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false; list.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
    }
    private func addSection(_ title: String, count: Int) {
        let label = NSTextField(labelWithString: "\(title)  \(count)")
        label.font = .systemFont(ofSize: 10, weight: .semibold); label.textColor = .secondaryLabelColor
        add(label)
    }
    private func addEmpty(_ title: String, detail: String) {
        let icon = NSImageView(image: NSImage(systemSymbolName: "person.2", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .tertiaryLabelColor
        let heading = NSTextField(wrappingLabelWithString: title); heading.font = .systemFont(ofSize: 14, weight: .semibold)
        let text = NSTextField(wrappingLabelWithString: detail); text.textColor = .secondaryLabelColor; text.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [icon, heading, text]); stack.orientation = .vertical; stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 8, bottom: 12, right: 8)
        for label in [heading, text] { label.alignment = .center; label.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true }
        add(stack)
    }
    private func addRow(_ row: FriendPresenceRow) {
        let color: NSColor = switch row.status { case "Offline": .tertiaryLabelColor; case "Away": .systemOrange; case "Busy": .systemRed; case "Status unavailable", "Online (status unavailable)": .secondaryLabelColor; default: .systemGreen }
        let avatar = FriendsMonogram(name: row.battleTag ?? "?", color: color)
        avatar.widthAnchor.constraint(equalToConstant: 34).isActive = true; avatar.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let name = NSTextField.label(.body); name.stringValue = row.battleTag ?? "BattleTag unavailable"
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        let detail = NSTextField.label(.caption1, color: .secondaryLabelColor)
        let games = row.games.filter { $0 != "Battle.net app" }
        detail.stringValue = ([row.status] + games).joined(separator: " · ")
        let text = NSStackView(views: [name, detail]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 3
        if let activity = row.activity, !activity.isEmpty {
            let label = NSTextField.label(.caption1, color: .secondaryLabelColor); label.stringValue = activity
            text.addArrangedSubview(label); label.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        }
        for label in [name, detail] { label.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true }
        let stack = NSStackView(views: [avatar, text]); stack.spacing = 10; stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 2, bottom: 9, right: 2)
        text.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        add(stack)
    }
}

@MainActor private final class FriendsMonogram: NSView {
    private let name: String
    private let color: NSColor
    init(name: String, color: NSColor) { self.name = name; self.color = color; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternarySystemFill.setFill(); NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        let string = String(name.prefix(1)).uppercased() as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
        let size = string.size(withAttributes: attrs)
        string.draw(at: NSPoint(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2), withAttributes: attrs)
        NSColor.windowBackgroundColor.setFill(); NSBezierPath(ovalIn: NSRect(x: bounds.maxX-10, y: 0, width: 11, height: 11)).fill()
        color.setFill(); NSBezierPath(ovalIn: NSRect(x: bounds.maxX-8, y: 2, width: 7, height: 7)).fill()
    }
}

enum FriendsPanelFailure: Error {
    case unavailable, gamesRunning, accountChanged
    var message: String {
        switch self {
        case .unavailable: "Friends currently needs a saved Americas WoW login. Your login has not been changed."
        case .gamesRunning: "Close Blizzard games and the official Battle.net launcher before refreshing friends."
        case .accountChanged: "The active account changed. Refresh again for the current account."
        }
    }
}

/// Short lists begin at the top of the scroll view, like a native friends list.
@MainActor private final class FriendsListStack: NSStackView {
    override var isFlipped: Bool { true }
}
