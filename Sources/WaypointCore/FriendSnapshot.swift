import Foundation

/// Minimal experimental social data. Real names, emails, notes and raw attributes
/// are deliberately not retained. A snapshot does not imply online status.
public struct BattleNetFriend: Equatable, Sendable, Identifiable {
    public let id: String
    public let battleTag: String?
    public var displayName: String { battleTag ?? "Friend \(id)" }
}

struct FriendSnapshotPage {
    let friends: [BattleNetFriend]
    let continuation: UInt64?

    static func decode(_ data: Data) throws -> Self {
        typealias W = BGSWire
        let fields = try W.decode(data), values = fields[1] ?? []
        guard values.count <= 1000 else { throw W.Failure.oversized }
        var friends: [BattleNetFriend] = []
        for value in values {
            guard case .bytes(let bytes) = value else { throw W.Failure.malformed }
            let entry = try W.decode(bytes), id = try W.uint(entry, 1)
            guard id > 0 else { throw W.Failure.malformed }
            var tag: String?
            if entry[3] != nil {
                let raw = try W.data(entry, 3)
                guard raw.count <= 256, let text = String(data: raw, encoding: .utf8),
                      !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw W.Failure.malformed }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                tag = trimmed.isEmpty ? nil : trimmed
            }
            friends.append(BattleNetFriend(id: String(id), battleTag: tag))
        }
        let continuation = fields[2] == nil ? nil : try W.uint(fields, 2)
        return Self(friends: friends, continuation: continuation)
    }
}

/// Keeps a social RPC refusal distinct from connection/authentication rejection.
public enum FriendSnapshotFailure: Error {
    case requestRejected(UInt64)
}


public enum FriendSnapshotProtocol: Sendable {
    case current, legacy, legacySubscription
}

/// Legacy schema has entity references and attributes, not a dedicated BattleTag.
/// Do not interpret arbitrary attributes as names or expose Real ID information.
struct LegacyFriendSnapshot {
    static func decode(_ data: Data, friendsField: Int = 1) throws -> [BattleNetFriend] {
        typealias W = BGSWire
        let values = try W.decode(data)[friendsField] ?? []
        guard values.count <= 1000 else { throw W.Failure.oversized }
        var result: [BattleNetFriend] = [], seen = Set<String>()
        for value in values {
            guard case .bytes(let entry) = value else { throw W.Failure.malformed }
            let entity = try W.decode(W.data(W.decode(entry), 1))
            let high = try W.uint(entity, 1, default: 0), low = try W.uint(entity, 2)
            let id = "\(high):\(low)"
            guard low > 0, seen.insert(id).inserted else { throw W.Failure.malformed }
            result.append(BattleNetFriend(id: id, battleTag: nil))
        }
        return result
    }
}
