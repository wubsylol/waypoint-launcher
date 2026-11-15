import AppKit
import WaypointCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation {
    let model = AppModel()
    let appUpdater = AppUpdater()
    let backgroundServices = BackgroundServices()
    private var libraryWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var friendsWindow: NSWindow?
    private var menuBarItem: MenuBarItem?
    private var isTerminating = false

    static func main() {
        let app = NSApplication.shared
        // Preserve this fork’s previous Dark default until a choice is saved.
        UserDefaults.standard.register(defaults: [AppAppearance.defaultsKey: AppAppearance.Mode.dark.rawValue])
        AppAppearance.apply()
        if ProcessInfo.processInfo.environment["WAYPOINT_SHARED_SIGNIN_PROBE"] == "1" {
            let probe = SharedSignInProbe()
            app.delegate = probe; app.setActivationPolicy(.regular)
            withExtendedLifetime(probe) { app.run() }
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        // Also makes `swift run` builds, which have no bundle, a regular app.
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Capture the hint before any system-service calls. This remains best effort.
        let loginLaunch = Self.launchedAtLogin
        appUpdater.prepareForRestart = { [weak model] in await model?.prepareToQuit() ?? true }
        NSApp.mainMenu = MainMenu.make(for: self)
        menuBarItem = MenuBarItem(model: model, appUpdater: appUpdater)
        backgroundServices.openLibrary = { [weak self] in self?.showLibrary(nil) }
        backgroundServices.openAppUpdate = { [weak self] in self?.showLibrary(nil) }
        backgroundServices.setLibraryOpen(!loginLaunch)
        backgroundServices.start(model: model, updater: appUpdater)
        // The launch marker is best effort. Unknown/manual launches show a window.
        Log.info(.app, "launch_context", nil, ["login_item_hint": loginLaunch])
        if !loginLaunch {
            showLibrary(nil)
        }
        // How long the launch took, to compare versions and Macs by the logs.
        Log.info(.app, "interface_ready", nil, ["launch_ms": ProcessStart.millisecondsAgo ?? -1, "games": model.games.count])
    }

    private static var launchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.isRefreshingExperimentalFriends {
            let alert = NSAlert()
            alert.messageText = "Friends is still refreshing"
            alert.informativeText = "Wait for the refresh and connection cleanup to finish before quitting."
            alert.addButton(withTitle: "Keep Waypoint Open")
            alert.runModal()
            return .terminateCancel
        }
        guard model.hasActiveDownloads || isTerminating else { return .terminateNow }
        if !isTerminating {
            isTerminating = true
            Task {
                let ready = await model.prepareToQuit()
                isTerminating = ready
                sender.reply(toApplicationShouldTerminate: ready)
            }
        }
        return .terminateLater
    }

    /// Closing the window doesn't quit (AppKit's default): game downloads and
    /// Sparkle's install-on-quit keep going. Reopening Waypoint (Dock click,
    /// Spotlight, Raycast, `open`) brings the library back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showLibrary(nil)
        return true
    }

    // MARK: Library window

    /// The status icon toggles only the library window, never the application.
    /// The red close button uses the same window-close path; background work lives on.
    @objc func toggleLibrary(_ sender: Any?) {
        if let window = libraryWindow, window.isVisible, !window.isMiniaturized, !NSApp.isHidden {
            window.performClose(sender)
        } else {
            showLibrary(sender)
        }
    }

    @objc func showLibrary(_ sender: Any?) {
        let window = libraryWindow ?? makeLibraryWindow()
        libraryWindow = window
        backgroundServices.setLibraryOpen(true)
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeLibraryWindow() -> NSWindow {
        let library = LibraryViewController(model: model, appUpdater: appUpdater)
        // The toolbar and the frame come first and the content last. Each of
        // them lays the window out; with the content already in, that was
        // three passes over the list, building its rows, instead of one.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                              // The list scrolls under the toolbar.
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.title = "Waypoint"
        window.toolbar = library.toolbar
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 380, height: 260)
        window.setContentSize(NSSize(width: 460, height: 360))
        window.isReleasedWhenClosed = false
        // Window ▸ Waypoint reopens it; no second entry for the open window.
        window.isExcludedFromWindowsMenu = true
        window.delegate = self
        if !window.setFrameUsingName("Library") { window.center() }
        // A window takes the size of the view its controller brings: bring
        // one that already has the window's.
        let frame = window.frame
        library.view.setFrameSize(window.contentRect(forFrameRect: frame).size)
        window.contentViewController = library
        if window.frame != frame { window.setFrame(frame, display: false) }
        window.setFrameAutosaveName("Library")
        return window
    }

    @objc func showFriends(_ sender: Any?) {
        let window: NSWindow
        if let existing = friendsWindow { window = existing }
        else {
            window = NSWindow(contentViewController: FriendsViewController(model: model))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.title = "Friends — Waypoint"
            window.delegate = self
            window.contentMinSize = NSSize(width: 300, height: 420)
            window.setContentSize(NSSize(width: 340, height: 600))
            window.isReleasedWhenClosed = false
            if !window.setFrameUsingName("FriendsExperiment") { window.center() }
            window.setFrameAutosaveName("FriendsExperiment")
            friendsWindow = window
        }
        backgroundServices.setFriendsOpen(true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettings(_ sender: Any?) {
        let window = settingsWindow ?? NSWindow(contentViewController: SettingsViewController(model: model, backgroundServices: backgroundServices))
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        if settingsWindow == nil { window.center() }
        settingsWindow = window
        window.delegate = self
        backgroundServices.setSettingsOpen(true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// A closed library is let go, views and all; reopening builds a new one.
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === friendsWindow {
            backgroundServices.setFriendsOpen(false)
        }
        if notification.object as? NSWindow === libraryWindow {
            libraryWindow = nil
            backgroundServices.setLibraryOpen(false)
        }
        if notification.object as? NSWindow === settingsWindow {
            backgroundServices.setSettingsOpen(false)
        }
    }

    // MARK: Commands

    /// One command for everything: games (Blizzard's version service) and
    /// Waypoint itself (Sparkle, in the background).
    @objc func checkForUpdates(_ sender: Any?) {
        appUpdater.checkNow()
        Task { await model.checkForUpdates(force: true) }
    }

    @objc func restartToUpdate(_ sender: Any?) {
        appUpdater.restartToUpdate()
    }

    @objc func locateInstalledGames(_ sender: Any?) {
        Task { await model.locateInstalledGames() }
    }

    @objc func rescan(_ sender: Any?) {
        model.reload()
    }

    @objc func addAccount(_ sender: Any?) {
        Task { await model.addAccount() }
    }

    @objc func signInAgain(_ sender: Any?) {
        Task { await model.signInAgain() }
    }

    @objc func signOut(_ sender: Any?) {
        Task { await model.signOut() }
    }

    /// Saves a diagnostics snapshot plus the last week of logs as one JSONL
    /// file, for bug reports.
    @objc func exportDiagnostics(_ sender: Any?) {
        let panel = NSSavePanel()
        let stamp = Diagnostics.timestampString(Date()).prefix(19).replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "Waypoint-Diagnostics-\(stamp).jsonl"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiagnosticsReport.export(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            Log.error(.app, "diagnostics_export_failed", nil, ["error": error])
            NSAlert(error: error).runModal()
        }
    }

    @objc func showLogs(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([Diagnostics.shared.directory])
    }

    /// The app menu: shows whichever update command applies as it opens,
    /// and names the account Sign In Again and Sign Out apply to.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let ready = appUpdater.readyVersion
        for item in menu.items {
            switch item.action {
            case #selector(checkForUpdates(_:)):
                item.isHidden = ready != nil
            case #selector(restartToUpdate(_:)):
                item.isHidden = ready == nil
                item.title = "Restart to Update Waypoint \(ready ?? "")"
            case #selector(addAccount(_:)):
                item.title = model.accounts.isEmpty ? "Sign In to Battle.net…" : "Add Battle.net Account…"
            case #selector(signInAgain(_:)):
                item.isHidden = model.activeAccount == nil
                item.title = "Sign In to \(model.activeAccount?.displayName ?? "Battle.net") Again…"
            case #selector(signOut(_:)):
                item.isHidden = model.activeAccount == nil
                item.title = "Sign Out of \(model.activeAccount?.displayName ?? "Battle.net")"
            default:
                break
            }
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(checkForUpdates(_:)): true
        case #selector(addAccount(_:)), #selector(signInAgain(_:)), #selector(signOut(_:)): !model.isSigningIn
        default: true
        }
    }
}
