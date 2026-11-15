import AppKit
import Observation
import ServiceManagement
import UserNotifications
import WaypointCore

/// Native integration stays dormant unless notifications are on or Settings is open.
@MainActor
@Observable
final class BackgroundServices: NSObject, UNUserNotificationCenterDelegate {
    let supportsSystemIntegration = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    private(set) var loginStatus: SMAppService.Status = .notRegistered
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var loginError: String?
    private(set) var notificationsError: String?
    @ObservationIgnored var openLibrary: (() -> Void)?
    @ObservationIgnored var openAppUpdate: (() -> Void)?
    @ObservationIgnored private var announceAppUpdate: (() -> Void)?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private let ledger = UpdateAlertLedger()
    @ObservationIgnored private var pendingAlerts = Set<String>()
    @ObservationIgnored private var notificationsWereEnabled = false
    @ObservationIgnored private var libraryOpen = false
    @ObservationIgnored private var settingsOpen = false
    @ObservationIgnored private var statusRefresh: Task<Void, Never>?
    @ObservationIgnored private var refreshStatusAgain = false

    private var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: UpdatePreferences.notificationsKey)
    }

    func start(model: AppModel, updater: AppUpdater) {
        model.updateChecked = { [weak self] game, check in
            guard let self, self.supportsSystemIntegration, self.notificationsEnabled else { return }
            guard check.isUpdateAvailable else {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["game:" + game.id])
                return
            }
            self.notify(id: "game:" + game.id, build: check.latest.buildConfig,
                   title: "\(game.displayName) update available", body: "Version \(check.latest.name) is ready to download.")
        }
        model.updateCleared = { [weak self] id in
            guard let self, self.supportsSystemIntegration, self.notificationsEnabled else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["game:" + id])
        }
        updater.updateAvailable = { [weak self] version, build in
            self?.notify(id: "waypoint", build: build, title: "Waypoint update available",
                         body: "Waypoint \(version) is available. Click to view the update.")
        }
        updater.noUpdateAvailable = { [weak self] in
            guard let self, self.supportsSystemIntegration, self.notificationsEnabled else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["waypoint"])
        }
        announceAppUpdate = { [weak updater] in updater?.announceAvailableUpdate() }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.syncDockPolicy(); self?.syncNotifications() }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.settingsOpen else { return }
                self.refreshStatus()
            }
        }
        syncDockPolicy()
        syncNotifications()
    }

    private func syncNotifications() {
        guard supportsSystemIntegration, notificationsWereEnabled != notificationsEnabled else { return }
        notificationsWereEnabled = notificationsEnabled
        if notificationsEnabled {
            UNUserNotificationCenter.current().delegate = self
        } else {
            UNUserNotificationCenter.current().delegate = nil
        }
    }

    func setLibraryOpen(_ open: Bool) { libraryOpen = open; syncDockPolicy() }
    func setSettingsOpen(_ open: Bool) {
        settingsOpen = open
        syncDockPolicy()
        if open { refreshStatus() }
    }

    /// Called only by Settings, never as a general launch/activation hook.
    func refreshStatus() {
        guard supportsSystemIntegration, settingsOpen else { return }
        loginStatus = SMAppService.mainApp.status
        guard statusRefresh == nil else { refreshStatusAgain = true; return }
        statusRefresh = Task {
            repeat {
                refreshStatusAgain = false
                guard settingsOpen else { break }
                let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                if settingsOpen { notificationStatus = status }
            } while refreshStatusAgain && settingsOpen
            statusRefresh = nil
        }
    }

    func setLoginEnabled(_ enabled: Bool) async {
        guard supportsSystemIntegration else { return }
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try await SMAppService.mainApp.unregister() }
        } catch { loginError = "Could not change Start at login: \(error.localizedDescription)" }
        refreshStatus()
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        guard supportsSystemIntegration else { return }
        notificationsError = nil
        if enabled {
            do {
                let center = UNUserNotificationCenter.current()
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                UserDefaults.standard.set(granted, forKey: UpdatePreferences.notificationsKey)
                syncNotifications()
                if granted { announceAppUpdate?() }
                else { notificationsError = "Allow Waypoint notifications in System Settings to receive update alerts." }
            } catch {
                UserDefaults.standard.set(false, forKey: UpdatePreferences.notificationsKey)
                syncNotifications()
                notificationsError = "Could not enable notifications: \(error.localizedDescription)"
            }
        } else {
            UserDefaults.standard.set(false, forKey: UpdatePreferences.notificationsKey)
            syncNotifications()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
        refreshStatus()
    }

    func setHideDock(_ hidden: Bool) {
        if hidden { UserDefaults.standard.set(true, forKey: MenuBarItem.defaultsKey) }
        UserDefaults.standard.set(hidden, forKey: UpdatePreferences.hideDockKey)
        syncDockPolicy()
    }

    private func syncDockPolicy() {
        let defaults = UserDefaults.standard
        let menuEnabled = defaults.bool(forKey: MenuBarItem.defaultsKey)
        if !menuEnabled, defaults.bool(forKey: UpdatePreferences.hideDockKey) {
            defaults.set(false, forKey: UpdatePreferences.hideDockKey)
        }
        let showDock = AppPresentationPolicy.showsDock(hideDock: defaults.bool(forKey: UpdatePreferences.hideDockKey),
                                                      menuBarEnabled: menuEnabled, windowsOpen: libraryOpen || settingsOpen)
        let policy: NSApplication.ActivationPolicy = showDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            let applied = NSApp.setActivationPolicy(policy)
            Log.info(.app, "presentation_changed", nil, ["shows_dock": showDock,
                "windows_open": libraryOpen || settingsOpen, "applied": applied])
        }
    }

    private func notify(id: String, build: String, title: String, body: String) {
        guard supportsSystemIntegration, notificationsEnabled,
              ledger.needsAlert(id: id, build: build), pendingAlerts.insert(id).inserted else { return }
        Task {
            defer { pendingAlerts.remove(id) }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
                  notificationsEnabled else { return }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                ledger.record(id: id, build: build)
            } catch { Log.warning(.app, "update_notification_failed", nil, ["error": error.localizedDescription]) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let isApp = response.notification.request.identifier == "waypoint"
        await MainActor.run {
            if isApp { openAppUpdate?() } else { openLibrary?() }
        }
    }
}
