import Foundation

/// Shared preferences keep automatic checks distinct from explicit Check for Updates.
public enum UpdatePreferences {
    public static let automaticKey = "automaticUpdateChecks"
    public static let notificationsKey = "updateNotifications"
    public static let hideDockKey = "hideDockIcon"
    public static func automatic(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: automaticKey) as? Bool ?? true
    }
}

/// Persist only alerts actually handed to Notification Center, so failed or
/// denied delivery can retry. A new build produces a new alert, not every poll.
public struct UpdateAlertLedger {
    private let defaults: UserDefaults
    private let key = "announcedUpdateBuilds"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func needsAlert(id: String, build: String) -> Bool {
        (defaults.dictionary(forKey: key) as? [String: String])?[id] != build
    }
    public func record(id: String, build: String) {
        var records = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        records[id] = build
        defaults.set(records, forKey: key)
    }
}

/// A queued game-launch check must never widen into a check of other games.
public enum UpdateCheckScope: Equatable, Sendable {
    case all
    case games(Set<String>)
    public func includes(_ id: String) -> Bool {
        switch self { case .all: true; case .games(let ids): ids.contains(id) }
    }
    fileprivate func merging(_ other: Self) -> Self {
        switch (self, other) {
        case (.all, _), (_, .all): .all
        case (.games(let a), .games(let b)): .games(a.union(b))
        }
    }
}

/// Coalesce concurrent requests while retaining the caller's exact game scope.
public struct UpdateCheckSchedule {
    public private(set) var current: UpdateCheckScope?
    private var pending: UpdateCheckScope?
    public init() {}
    public mutating func request(force: Bool, automatic: Bool, scope: UpdateCheckScope = .all) -> Bool {
        guard force || automatic else { return false }
        if current != nil {
            pending = pending.map { $0.merging(scope) } ?? scope
            return false
        }
        current = scope
        return true
    }
    public mutating func complete() -> Bool {
        current = pending; pending = nil
        return current != nil
    }
    public mutating func cancel() { current = nil; pending = nil }
}

public enum AppPresentationPolicy {
    public static func showsDock(hideDock: Bool, menuBarEnabled: Bool, windowsOpen: Bool) -> Bool {
        windowsOpen || !hideDock || !menuBarEnabled
    }
}
