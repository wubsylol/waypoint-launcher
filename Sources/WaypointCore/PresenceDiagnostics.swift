import Foundation

/// Opt-in local viewer row. No IDs; never persisted or included in diagnostics.
public struct FriendPresenceRow: Sendable {
    public let battleTag: String?
    public let status: String
    public let games: [String]
    public let activity: String?
    public init(battleTag: String?, status: String, games: [String], activity: String?) {
        self.battleTag = battleTag; self.status = status; self.games = games; self.activity = activity
    }
}

/// Public diagnostic fields are aggregate-only; private decoded values feed the opt-in viewer.
public struct PresenceQuerySummary: Sendable {
    public var sampledFriends: Int = 0
    public var states: Int = 0
    public var fieldKinds: Set<String> = []
    public var gameTitles: Set<String> = []
    public var selectedStatusCounts: [String: Int] = [:]
    public var onlineGameHandles: Int = 0
    var onlineGameListPresent = false
    var onlineGameTitles: Set<String> = []
    var selectedStatus: UInt64?
    var activity: String?

    var availabilityLabel: String {
        guard onlineGameListPresent else { return "Status unavailable" }
        guard onlineGameHandles > 0 else { return "Offline" }
        switch selectedStatus {
        case 2: return "Away"
        case 3: return "Busy"
        case 0, 1, nil: return "Online"
        default: return "Online (status unavailable)"
        }
    }
}

public enum PresenceQueryFailure: Error {
    case refused(UInt64), identity, malformed
}

/// Modern query envelope is verified against static client descriptors. These
/// candidate keys are not yet validated as status/activity semantics live.
enum PresenceDiagnosticPage {
    static let keys: [(UInt64, UInt64, UInt64)] = [
        (0x424e, 1, 13), (0x424e, 1, 3), (0x424e, 2, 1), (0x424e, 2, 8)
    ]

    static func request(friendID: UInt64, accountOnly: Bool = false) -> Data {
        var body = BGSWire.number(1, friendID) + BGSWire.number(2, accountOnly ? 0 : 2) // Desktop account QueryImpl uses 0.
        for (title, group, field) in keys {
            body += BGSWire.bytes(3, BGSWire.number(1, title) + BGSWire.number(2, group)
                + BGSWire.number(3, field) + BGSWire.number(4, 0))
        }
        return body
    }

    /// AccountData consumes fields20/21/22/25 (core17986 0x8265ef and
    /// switch0x826888). Use the account-key shape observed for fields4/13 at
    /// 0x719de1...0x719e22: title/group/field present, unique_id absent.
    static let desktopAccountKeys: [(UInt64, UInt64, UInt64)] = [(0x424e, 1, 20), (0x424e, 1, 21), (0x424e, 1, 22), (0x424e, 1, 25)]
    static func desktopAccountRequest(friendID: UInt64) -> Data {
        var body = BGSWire.number(1, friendID) + BGSWire.number(2, 0)
        for (title, group, field) in desktopAccountKeys {
            body += BGSWire.bytes(3, BGSWire.number(1, title) + BGSWire.number(2, group) + BGSWire.number(3, field))
        }
        return body
    }

    static func decode(_ data: Data, expectedFriend: UInt64) throws -> PresenceQuerySummary {
        typealias W = BGSWire
        let response = try W.decode(data), states = response[1] ?? []
        guard states.count <= 64 else { throw PresenceQueryFailure.malformed }
        var result = PresenceQuerySummary()
        for state in states {
            guard case .bytes(let bytes) = state else { throw PresenceQueryFailure.malformed }
            let fields = try W.decode(bytes)
            guard try W.uint(fields, 1) == expectedFriend else { throw PresenceQueryFailure.identity }
            result.states += 1
            if fields[2] != nil {
                let handle = try W.decode(W.data(fields, 2))
                let title = try W.uint(handle, 2)
                // Titles in returned states do not alone establish an active game.
                result.gameTitles.insert(gameName(title))
            }
            let values = fields[3] ?? []
            guard values.count <= 128 else { throw PresenceQueryFailure.malformed }
            for value in values {
                guard case .bytes(let raw) = value else { throw PresenceQueryFailure.malformed }
                let entry = try W.decode(raw), key = try W.decode(W.data(entry, 1))
                let title = try W.uint(key, 1), group = try W.uint(key, 2), field = try W.uint(key, 3)
                guard (keys + desktopAccountKeys).contains(where: { $0.0 == title && $0.1 == group && $0.2 == field }) else { continue }
                if try W.uint(entry, 3, default: 0) == 1 {
                    result.fieldKinds.insert("BN \(group)/\(field): deleted")
                    continue
                }
                guard entry[2] != nil else { continue }
                let variant = try W.decode(W.data(entry, 2))
                if title == 0x424e, group == 1, field == 22, variant[6] != nil {
                    let status = try W.uint(variant, 6)
                    result.selectedStatus = status
                    let label = status <= 4 ? "Selected status code \(status)" : "Other selected status"
                    result.selectedStatusCounts[label, default: 0] += 1
                }
                if title == 0x424e, group == 1, field == 20, variant[5] != nil {
                    result.onlineGameListPresent = true
                    let blob = try W.data(variant, 5)
                    guard blob.count <= 32_768 else { throw PresenceQueryFailure.malformed }
                    let accounts = try W.decode(blob)[1] ?? []
                    guard accounts.count <= 64 else { throw PresenceQueryFailure.malformed }
                    for account in accounts {
                        guard case .bytes(let rawAccount) = account else { throw PresenceQueryFailure.malformed }
                        let entry = try W.decode(rawAccount), handle = try W.decode(W.data(entry, 1))
                        let id = try W.uint(handle, 1), game = try W.uint(handle, 2), region = try W.uint(handle, 3)
                        guard id > 0, game > 0, game <= UInt32.max, region > 0, region <= UInt32.max else { throw PresenceQueryFailure.malformed }
                        result.onlineGameHandles += 1
                        result.gameTitles.insert(gameName(game))
                        result.onlineGameTitles.insert(gameName(game))
                    }
                }
                if title == 0x424e, group == 1, field == 25, variant[4] != nil {
                    let raw = try W.data(variant, 4)
                    guard raw.count <= 2048, let text = String(data: raw, encoding: .utf8),
                          !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw PresenceQueryFailure.malformed }
                    result.activity = text.isEmpty ? nil : text
                }
                let labels: [(Int, String)] = [(1, "boolean"), (2, "integer"), (3, "float"),
                    (4, "text (discarded)"), (5, "blob (discarded)"), (6, "unsigned integer")]
                for (number, label) in labels where variant[number] != nil {
                    result.fieldKinds.insert("BN \(group)/\(field): \(label)")
                }
            }
        }
        return result
    }

    private static func gameName(_ title: UInt64) -> String {
        switch title {
        case 0x576f57: return "World of Warcraft"
        case 0x46656e: return "Diablo IV"
        case 0x4433: return "Diablo III"
        case 0x57544347: return "Hearthstone"
        case 0x4865726f: return "Heroes of the Storm"
        case 0x50726f: return "Overwatch"
        case 0x5332: return "StarCraft II"
        case 0x417070: return "Battle.net app"
        default:
            let bytes = (0..<4).reversed().map { UInt8(truncatingIfNeeded: title >> ($0 * 8)) }.drop(while: { $0 == 0 })
            if !bytes.isEmpty, bytes.allSatisfy({ (32...126).contains($0) }), let code = String(bytes: bytes, encoding: .ascii) {
                return "Other title (\(code))"
            }
            return "Other game"

        }
    }
}
