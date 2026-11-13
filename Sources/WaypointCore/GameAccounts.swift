import Foundation

/// Read-only account-website data. These are game licences, not Battle.net identities.
/// No field here is assumed to be the client's GAME_ACCOUNT launch value.
public struct GameAccount: Decodable, Equatable, Sendable, Identifiable {
    public struct ID: Hashable, Sendable {
        public let title: String
        public let region: String
        public let account: String
    }
    public let titleID: String
    public let accountID: String
    public let name: String
    public let region: String
    public let status: String?
    public var id: ID { ID(title: titleID, region: region, account: accountID) }

    private enum CodingKeys: String, CodingKey {
        case titleID = "titleId", uniqueID = "gameAccountUniqueId"
        case name = "gameAccountName", region = "gameAccountRegion", status = "gameAccountStatus"
    }
    private enum UniqueKeys: String, CodingKey { case accountID = "gameAccountId" }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        titleID = try Self.identifier(fields, key: .titleID)
        let unique = try fields.nestedContainer(keyedBy: UniqueKeys.self, forKey: .uniqueID)
        accountID = try Self.identifier(unique, key: .accountID)
        name = try fields.decode(String.self, forKey: .name)
        region = try fields.decode(String.self, forKey: .region)
        status = try fields.decodeIfPresent(String.self, forKey: .status)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing game-account label or region"))
        }
    }
    private static func identifier<Key: CodingKey>(_ fields: KeyedDecodingContainer<Key>, key: Key) throws -> String {
        if let string = try? fields.decode(String.self, forKey: key), !string.isEmpty { return string }
        // Decode integer IDs without rounding them through a Double.
        let number = try fields.decode(UInt64.self, forKey: key)
        return String(number)
    }
}

/// Read-only discovery payload. The caller must bind it to a verified Battle.net owner
/// before storing it or using it to select a game licence.
/// Unknown schemas and duplicate IDs fail rather than presenting an incomplete picker.
public struct GameAccountCatalog: Decodable, Sendable {
    public let gameAccounts: [GameAccount]
    public static func decode(_ data: Data) throws -> GameAccountCatalog {
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard Set(result.gameAccounts.map(\.id)).count == result.gameAccounts.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Duplicate game-account identity"))
        }
        return result
    }
}

extension GameAccountCatalog {
    /// The account website uses 5730135 (0x576f57, WoW) for the observed WoW licences.
    /// Filter by that title before requiring per-licence names: unrelated games
    /// legitimately return null names or have no game account at all.
    public static func decodeWoW(_ data: Data) throws -> GameAccountCatalog {
        struct Envelope: Decodable {
            let accounts: [GameAccount]
            enum Keys: String, CodingKey { case gameAccounts }
            enum RowKeys: String, CodingKey { case titleId }
            init(from decoder: Decoder) throws {
                let fields = try decoder.container(keyedBy: Keys.self)
                var rows = try fields.nestedUnkeyedContainer(forKey: .gameAccounts)
                var found: [GameAccount] = []
                while !rows.isAtEnd {
                    let row = try rows.superDecoder()
                    guard let record = try? row.container(keyedBy: RowKeys.self) else { continue }
                    let title = (try? record.decode(String.self, forKey: .titleId))
                        ?? (try? record.decode(UInt64.self, forKey: .titleId)).map(String.init)
                    guard title == "5730135" else { continue }
                    found.append(try GameAccount(from: row))
                }
                accounts = found
            }
        }
        let result = try JSONDecoder().decode(Envelope.self, from: data)
        guard Set(result.accounts.map(\.id)).count == result.accounts.count else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Duplicate WoW game-account identity"))
        }
        return GameAccountCatalog(gameAccounts: result.accounts)
    }
}
