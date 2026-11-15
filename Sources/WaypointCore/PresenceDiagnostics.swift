import Foundation

/// Diagnostic metadata only: no account IDs, names, activity text or field values.
public struct PresenceQuerySummary: Sendable {
    public var sampledFriends: Int = 0
    public var states: Int = 0
    public var fieldKinds: Set<String> = []
    public var gameTitles: Set<String> = []
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

    static func request(friendID: UInt64) -> Data {
        var body = BGSWire.number(1, friendID) + BGSWire.number(2, 2) // INCLUDE_ALL_GAME_ACCOUNTS
        for (title, group, field) in keys {
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
                guard keys.contains(where: { $0.0 == title && $0.1 == group && $0.2 == field }) else { continue }
                if try W.uint(entry, 3, default: 0) == 1 {
                    result.fieldKinds.insert("BN \(group)/\(field): deleted")
                    continue
                }
                guard entry[2] != nil else { continue }
                let variant = try W.decode(W.data(entry, 2))
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
        case 0x576f57: "World of Warcraft"
        case 0x46656e: "Diablo IV"
        case 0x4433: "Diablo III"
        case 0x57544347: "Hearthstone"
        case 0x4865726f: "Heroes of the Storm"
        case 0x50726f: "Overwatch"
        case 0x5332: "StarCraft II"
        case 0x417070: "Battle.net app"
        default: "Other game"
        }
    }
}
