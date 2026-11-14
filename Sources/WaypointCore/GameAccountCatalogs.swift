import Foundation

/// Owner-verified WoW licence lists, cached separately from launch choices.
/// nil means never fetched; an empty array is a successful empty response.
public struct GameAccountCatalogs: Codable, Sendable {
    private struct Entry: Codable {
        let owner: String
        let region: String
        let accounts: [GameAccountSelection]
    }
    private var entries: [Entry] = []
    public init() {}

    public func accounts(owner: String, region: String) -> [GameAccountSelection]? {
        entries.first { $0.owner == owner && $0.region == region.lowercased() }?.accounts
    }

    @discardableResult
    public mutating func cache(_ accounts: [GameAccountSelection], owner: String, region: String) -> Bool {
        let region = region.lowercased()
        guard !owner.isEmpty, Region(rawValue: region) != nil, accounts.count <= 20,
              Set(accounts.map(\.accountID)).count == accounts.count,
              accounts.allSatisfy({ account in
                  UInt64(account.accountID).map { $0 > 0 } == true && account.region == region &&
                  !account.name.isEmpty && account.name.utf8.count <= 256 &&
                  account.name == account.name.trimmingCharacters(in: .whitespacesAndNewlines) &&
                  !account.name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } &&
                  LoginToken(account.name) == nil
              }) else { return false }
        entries.removeAll { $0.owner == owner && $0.region == region }
        entries.append(Entry(owner: owner, region: region, accounts: accounts))
        return true
    }

    public mutating func remove(owner: String) { entries.removeAll { $0.owner == owner } }
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: "gameAccountCatalogs"),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        var validated = Self()
        for entry in decoded.entries { _ = validated.cache(entry.accounts, owner: entry.owner, region: entry.region) }
        return validated
    }
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: "gameAccountCatalogs")
    }
}
