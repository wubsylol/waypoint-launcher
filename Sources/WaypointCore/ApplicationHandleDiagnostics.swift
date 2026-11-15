import Foundation

/// Fixed classifications only. Never exposes account handles, IDs or names.
public enum ApplicationHandleState: String, Sendable {
    case missing = "No game-account handles reported"
    case matching = "One Americas App handle reported"
    case other = "Handles reported, but no Americas App handle"
    case ambiguous = "Multiple Americas App handles reported"
    case unrecognized = "Optional handle metadata not recognized"
}

public struct ApplicationHandleDiagnostics: Sendable {
    public let state: ApplicationHandleState
    public let authenticatedContextPresent: Bool
}

enum ApplicationHandleMetadata {
    static func classify(_ fields: BGSWire.Message) -> ApplicationHandleState {
        guard let entries = fields[2], !entries.isEmpty else { return .missing }
        guard entries.count <= 100 else { return .unrecognized }
        var matching = 0
        for entry in entries {
            guard case .bytes(let data) = entry, data.count <= 128,
                  let handle = try? BGSWire.decode(data),
                  let id = try? BGSWire.uint(handle, 1), id > 0,
                  let title = try? BGSWire.uint(handle, 2), title <= UInt32.max,
                  let region = try? BGSWire.uint(handle, 3), region <= UInt32.max else { return .unrecognized }
            if title == 0x417070 && region == 1 { matching += 1 }
        }
        return matching == 1 ? .matching : matching > 1 ? .ambiguous : .other
    }
}
