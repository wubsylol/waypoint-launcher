import Foundation

/// Presence/status only. Never exposes CIIDs, session IDs/keys, BattleTags or tokens.
public struct NativeSessionDiagnostics: Equatable, Sendable {
    public var bindlessAccepted: Bool?
    public var connectionIdentityPresent: Bool
    public var logonBattleTagPresent: Bool
    public var logonGameAccountPresent: Bool
    public var logonSessionKeyPresent: Bool
    public var sessionQueryStatus: UInt64
    /// Nil if the server refused the query; refusal does not prove no session exists.
    public var serverSessionIDPresent: Bool?
}

/// Only a correlated session-query response receives this classification.
enum SessionDiagnosticRefusal: Error { case response(UInt64) }
