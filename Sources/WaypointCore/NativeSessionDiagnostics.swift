import Foundation

/// Presence/status only. Never exposes CIIDs, session IDs/keys, BattleTags or tokens.
public struct NativeSessionDiagnostics: Equatable, Sendable {
    public var bindlessAccepted: Bool?
    public var connectionIdentityPresent: Bool
    public var logonRecordHasField3: Bool
    public var logonRecordHasField2: Bool
    public var logonRecordHasField5: Bool
    /// Field numbers and codec categories only; not the actual field values.
    public var logonRecordShape: [String] = []
    public var sessionQueryStatus: UInt64
    /// Nil if the server refused the query; refusal does not prove no session exists.
    public var serverSessionIDPresent: Bool?
}

/// Only a correlated session-query response receives this classification.
enum SessionDiagnosticRefusal: Error { case response(UInt64) }

public enum SessionDiagnosticStage: String, Sendable {
    case connection = "connection setup"
    case connectionMetadata = "connection metadata"
    case authentication = "authentication"
    case query = "existing-session query"
    case response = "session reply parsing"
}

/// Static stage/categories only, never raw errors, payloads, URLs or credentials.
public enum SessionDiagnosticFailure: Error, LocalizedError {
    case malformed(SessionDiagnosticStage)
    case unavailable(SessionDiagnosticStage)
    case unexpectedCallback(SessionDiagnosticStage, service: UInt64, method: UInt64)
    public var errorDescription: String? {
        switch self {
        case .malformed(let stage): "Unexpected data format during \(stage.rawValue)."
        case .unavailable(let stage): "Connection or protocol failure during \(stage.rawValue)."
        case .unexpectedCallback(let stage, let hash, let method):
            "Unsupported callback during \(stage.rawValue) (service \(String(hash, radix: 16)), method \(method))."
        }
    }
}
