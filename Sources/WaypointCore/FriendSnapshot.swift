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
