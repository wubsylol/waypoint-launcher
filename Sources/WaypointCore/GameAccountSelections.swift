import Foundation

/// A verified WoW licence choice, separate from Battle.net identity and authorization.
public struct GameAccountSelection: Codable, Equatable, Sendable {
    public let accountID: String
    public let name: String
    public let region: String
    public init(accountID: String, name: String, region: String) {
        self.accountID = accountID; self.name = name; self.region = region
    }
}

/// Stable owner + edition + play-region scope; no launch choice is inherited from another owner.
public struct GameAccountSelections: Codable, Sendable {
    private struct Entry: Codable {
        let owner: String
        let uid: String
        let region: String
        var choice: GameAccountSelection
    }
    private var entries: [Entry] = []
    public init() {}
    public func choice(owner: String, uid: String, region: String) -> GameAccountSelection? {
        entries.first { $0.owner == owner && $0.uid == uid && $0.region == region.lowercased() }?.choice
            ?? defaultChoice(owner: owner, region: region)
    }
    /// A default applies only where an edition has no explicit saved choice.
    public func defaultChoice(owner: String, region: String) -> GameAccountSelection? {
        entries.first { $0.owner == owner && $0.uid == "*" && $0.region == region.lowercased() }?.choice
    }
    public mutating func selectDefault(_ choice: GameAccountSelection, owner: String, region: String) {
        select(choice, owner: owner, uid: "*", region: region)
    }
    public mutating func select(_ choice: GameAccountSelection, owner: String, uid: String, region: String) {
        entries.removeAll { $0.owner == owner && $0.uid == uid && $0.region == region.lowercased() }
        entries.append(Entry(owner: owner, uid: uid, region: region.lowercased(), choice: choice))
    }
    public mutating func remove(owner: String) { entries.removeAll { $0.owner == owner } }
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.data(forKey: "gameAccountSelections").flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: "gameAccountSelections")
    }
}
