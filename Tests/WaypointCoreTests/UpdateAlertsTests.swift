import Foundation
import Testing
@testable import WaypointCore

@Test func automaticUpdateChecksDefaultOnButRespectOptOut() throws {
    let suite = "WaypointCoreTests.updatePreferences.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(UpdatePreferences.automatic(in: defaults))
    defaults.set(false, forKey: UpdatePreferences.automaticKey)
    #expect(!UpdatePreferences.automatic(in: defaults))
    defaults.set(true, forKey: UpdatePreferences.automaticKey)
    #expect(UpdatePreferences.automatic(in: defaults))
    #expect(!defaults.bool(forKey: UpdatePreferences.notificationsKey))
    #expect(!defaults.bool(forKey: UpdatePreferences.hideDockKey))
}

@Test func updateAlertsRetryUntilRecordedAndPersistAcrossLaunches() throws {
    let suite = "WaypointCoreTests.updateAlerts.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let ledger = UpdateAlertLedger(defaults: defaults)
    #expect(ledger.needsAlert(id: "game:wow", build: "build-a"))
    // Denied permissions or a scheduling failure never call record.
    #expect(ledger.needsAlert(id: "game:wow", build: "build-a"))
    ledger.record(id: "game:wow", build: "build-a")
    #expect(!UpdateAlertLedger(defaults: defaults).needsAlert(id: "game:wow", build: "build-a"))
    #expect(ledger.needsAlert(id: "game:wow", build: "build-b"))
    #expect(ledger.needsAlert(id: "game:wowf", build: "build-a"))
    #expect(ledger.needsAlert(id: "waypoint", build: "build-a"))
}

@Test func queuedGameLaunchNeverWidensToOtherTitles() {
    var schedule = UpdateCheckSchedule()
    let started = schedule.request(force: false, automatic: true, scope: .all)
    #expect(started)
    let queued = schedule.request(force: false, automatic: true, scope: .games(["wowf"]))
    #expect(!queued)
    let again = schedule.complete()
    #expect(again)
    #expect(schedule.current == .games(["wowf"]))
    #expect(schedule.current?.includes("wowf") == true)
    #expect(schedule.current?.includes("wow") == false)
    let done = schedule.complete()
    #expect(!done)
}

@Test func concurrentGameLaunchesKeepOnlyRequestedScopesAndManualCheckIsExplicit() {
    var schedule = UpdateCheckSchedule()
    _ = schedule.request(force: false, automatic: true, scope: .games(["wow"]))
    _ = schedule.request(force: false, automatic: true, scope: .games(["wowf"]))
    _ = schedule.request(force: false, automatic: true, scope: .games(["hero"]))
    _ = schedule.complete()
    #expect(schedule.current == .games(["wowf", "hero"]))
    _ = schedule.request(force: true, automatic: false, scope: .all)
    _ = schedule.complete()
    #expect(schedule.current == .all)
}

@Test func automaticOptOutStillAllowsExplicitCheckAndNewLaunchesAreNotThrottled() {
    var schedule = UpdateCheckSchedule()
    let disabled = schedule.request(force: false, automatic: false)
    #expect(!disabled)
    let manual = schedule.request(force: true, automatic: false)
    #expect(manual)
    schedule.cancel()
    let launch = schedule.request(force: false, automatic: true, scope: .games(["wow"]))
    #expect(launch)
    _ = schedule.complete()
    let nextLaunch = schedule.request(force: false, automatic: true, scope: .games(["wow"]))
    #expect(nextLaunch)
}

@Test func dockAppearsForWindowsAndReturnsToMenuOnlyAfterClosing() {
    #expect(AppPresentationPolicy.showsDock(hideDock: true, menuBarEnabled: true, windowsOpen: true))
    #expect(!AppPresentationPolicy.showsDock(hideDock: true, menuBarEnabled: true, windowsOpen: false))
    #expect(AppPresentationPolicy.showsDock(hideDock: true, menuBarEnabled: false, windowsOpen: false))
    #expect(AppPresentationPolicy.showsDock(hideDock: false, menuBarEnabled: true, windowsOpen: false))
}
