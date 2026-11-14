import Foundation
import Network

/// Uses the saved game authorization, never website cookies or a second login.
/// A separate normal game-service session: do not run while a WoW client is open.
@MainActor
public final class NativeGameAccounts {
    public enum Failure: Error, LocalizedError {
        case unavailable, rejected(UInt64), owner, unsupported, gameRunning
        public var errorDescription: String? {
            switch self {
            case .unavailable: "Couldn’t retrieve your WoW accounts. Check your connection and try again."
            case .rejected: "Blizzard couldn’t authorize account discovery. Your saved account selection has been kept."
            case .owner: "Blizzard returned a different account identity. No account choices were changed."
            case .gameRunning: "Close World of Warcraft before retrieving accounts, then try again."
            case .unsupported: "Background account discovery is currently tested for Americas only."
            }
        }
    }
    private enum ReplyKind { case native, friends, sessionDiagnostic }
    private typealias W = BGSWire
    private var recordsDiagnostics = false
    private var inspectsAuthenticationContext = false
    private var authenticationReplyHasClientID = false
    private var logonNotificationHasClientID = false
    private var authenticationReplyClientID: Data?
    private var logonNotificationClientID: Data?
    private var includesConnectionIdentity = false
    private var connectionIdentity: String?
    private var diagnosticStage = SessionDiagnosticStage.connection
    private var diagnostics = NativeSessionDiagnostics(bindlessAccepted: nil, connectionIdentityPresent: false,
        logonRecordHasField3: false, logonRecordHasField2: false, logonRecordHasField5: false,
        sessionQueryStatus: 0, serverSessionIDPresent: nil)
    private let transport: any NativeAccountTransport
    private let timeout: Duration
    private var sequence: UInt64 = 1
    private var frames = 0
    private var loggedIn = false
    private var expectedOwner: UInt64 = 0
    private var deadlineTask: Task<Void, Never>?
    private var closed = false

    public convenience init() { self.init(transport: TLSAccountTransport()) }
    init(transport: any NativeAccountTransport, timeout: Duration = .seconds(35)) {
        self.transport = transport; self.timeout = timeout
    }
    public func cancel() { closed = true; transport.cancel() }
    private func authenticated<T>(token: LoginToken, build: UInt64, region: Region, operation: () async throws -> T) async throws -> T {
        guard region == .us else { throw Failure.unsupported }
        guard let owner = UInt64(token.accountID), owner > 0, build > 0 else { throw Failure.owner }
        expectedOwner = owner
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: self?.timeout ?? .seconds(35)) } catch { return }
            self?.cancel()
        }
        defer { deadlineTask?.cancel(); cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await transport.connect()
            try await send(service: 0, method: 1, token: 0, body: W.number(3, 1))
            let (header, connectionReply) = try await receive()
            guard try W.uint(header, 1) == 254, try W.uint(header, 3) == 0,
                  try W.uint(header, 6, default: 0) == 0 else { throw Failure.unavailable }
            if recordsDiagnostics {
                diagnosticStage = .connectionMetadata
                let connection = try W.decode(connectionReply)
                if let values = connection[7], values.count == 1,
                   case .number(let accepted) = values[0], accepted <= 1 {
                    diagnostics.bindlessAccepted = accepted == 1
                }
                diagnostics.connectionIdentityPresent = connection[9] != nil
                if includesConnectionIdentity {
                    let rawIdentity = try W.data(connection, 9)
                    guard rawIdentity.count <= 512,
                          let identity = String(data: rawIdentity, encoding: .utf8), !identity.isEmpty,
                          !identity.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                        throw SessionDiagnosticFailure.malformed(.connectionMetadata)
                    }
                    connectionIdentity = identity // In memory only; never displayed/logged.
                }
            }
            let request = W.number(1, 5_730_135) + W.text(2, "Mc64") + W.text(3, "enUS")
                + W.number(4, build) + W.bytes(10, W.text(1, token.value))
            if recordsDiagnostics { diagnosticStage = .authentication }
            _ = try await call(hash: 0xc02f8216, method: 1, body: request)
            while !loggedIn {
                let (header, body) = try await receive()
                try notification(header, body)
            }
            return try await operation()
        } onCancel: { Task { @MainActor in self.cancel() } }
    }

    public func discover(token: LoginToken, build: UInt64, region: Region) async throws -> [GameAccount] {
        try await authenticated(token: token, build: build, region: region) {
            let owner = expectedOwner
            let body = try await call(hash: 0x22dc2464, method: 108)
            let links = try W.decode(W.data(W.decode(body), 1))[1] ?? []
            guard links.count <= 100 else { throw Failure.unavailable }
            var seen = Set<String>(), handles: [(UInt64, Data)] = []
            for link in links {
                guard case .bytes(let handle) = link else { throw Failure.unavailable }
                let fields = try W.decode(handle)
                let id = try W.uint(fields, 1), title = try W.uint(fields, 2), regionID = try W.uint(fields, 3)
                guard id > 0, title <= UInt32.max, regionID <= UInt32.max,
                      seen.insert("\(id):\(title):\(regionID)").inserted else { throw Failure.unavailable }
                if title == 5_730_135, regionID == 1 { handles.append((id, handle)) }
            }
            guard handles.count <= 20 else { throw Failure.unavailable }
            var accounts: [GameAccount] = []
            for (id, handle) in handles {
                let response = try await call(hash: 0x22dc2464, method: 201, body: W.bytes(1, handle))
                let info = try W.decode(W.data(W.decode(response), 1))
                guard try W.uint(info, 1) == owner else { throw Failure.owner }
                guard let name = String(data: try W.data(info, 2), encoding: .utf8),
                      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Failure.unavailable }
                accounts.append(GameAccount(titleID: "5730135", accountID: String(id), name: name, region: region.rawValue))
            }
            return accounts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// Experimental friends read using the selected protocol. The explicit
    /// subscription mode closes after its initial snapshot. Does not set presence,
    /// mutate friendships, send messages, or persist returned friend data.
    public func friends(token: LoginToken, build: UInt64, region: Region, protocolVersion: FriendSnapshotProtocol = .current, includeConnectionIdentity: Bool = false) async throws -> [BattleNetFriend] {
        if includeConnectionIdentity { recordsDiagnostics = true; includesConnectionIdentity = true }
        return try await authenticated(token: token, build: build, region: region) {
            if recordsDiagnostics { diagnosticStage = .friendsQuery }
            if protocolVersion == .legacySubscription {
                // Connection-scoped listener object 1. The initial subscription
                // response contains the list in field 5; close immediately after
                // parsing it. Never keep a social subscription in the launcher.
                let response = try await call(hash: 0xa3ddb1bd, method: 1, body: W.number(2, 1), replyKind: .friends)
                return try LegacyFriendSnapshot.decode(response, friendsField: 5)
            }
            if protocolVersion == .legacy {
                let response = try await call(hash: 0xa3ddb1bd, method: 13, replyKind: .friends)
                return try LegacyFriendSnapshot.decode(response)
            }
            var result: [BattleNetFriend] = [], seenIDs = Set<String>(), continuations = Set<UInt64>()
            var continuation: UInt64 = 0
            for _ in 0..<20 {
                let request = continuation == 0 ? Data() : W.number(2, continuation)
                // Explicit control: only the method's client-call bit changes.
                let method: UInt64 = protocolVersion == .currentClientCall ? 0x40000005 : 5
                let response = try await call(hash: 0x5869be8c, method: method, body: request, replyKind: .friends)
                let page = try FriendSnapshotPage.decode(response)
                for friend in page.friends {
                    guard seenIDs.insert(friend.id).inserted, result.count < 1000 else { throw Failure.unavailable }
                    result.append(friend)
                }
                guard let next = page.continuation, next != 0 else {
                    return result.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
                }
                guard continuations.insert(next).inserted else { throw Failure.unavailable }
                continuation = next
            }
            throw Failure.unavailable
        }
    }
    /// Read-only connection metadata plus GetSessionState. Sends no session
    /// creation, restoration, destruction or mark-alive request.
    public func sessionDiagnostics(token: LoginToken, build: UInt64, region: Region, includeConnectionIdentity: Bool = false) async throws -> NativeSessionDiagnostics {
        recordsDiagnostics = true
        includesConnectionIdentity = includeConnectionIdentity
        do {
            return try await authenticated(token: token, build: build, region: region) {
                do {
                    diagnosticStage = .query
                    let reply = try await call(hash: 0x7b37d770, method: 5, replyKind: .sessionDiagnostic)
                    diagnosticStage = .response
                    let response = try W.decode(reply)
                    diagnostics.serverSessionIDPresent = false
                    if response[1] != nil {
                        let state = try W.decode(W.data(response, 1))
                        if state[1] != nil {
                            let identity = try W.decode(W.data(state, 1))
                            guard try W.uint(identity, 1) == expectedOwner else { throw Failure.owner }
                            diagnostics.serverSessionIDPresent = true
                        }
                    }
                    diagnostics.sessionQueryStatus = 0
                } catch SessionDiagnosticRefusal.response(let code) {
                    diagnostics.sessionQueryStatus = code
                    diagnostics.serverSessionIDPresent = nil
                }
                return diagnostics
            }
        } catch is W.Failure { throw SessionDiagnosticFailure.malformed(diagnosticStage) }
        catch Failure.unavailable { throw SessionDiagnosticFailure.unavailable(diagnosticStage) }
    }

    /// Connect/authenticate only, then close. No friends, session-query or
    /// session-creation RPC is sent. Actual header IDs stay inside this instance.
    public func authenticationContextDiagnostics(token: LoginToken, build: UInt64, region: Region) async throws -> AuthenticationContextDiagnostics {
        recordsDiagnostics = true
        inspectsAuthenticationContext = true
        return try await authenticated(token: token, build: build, region: region) {
            let match: Bool?
            if let reply = authenticationReplyClientID, let logon = logonNotificationClientID { match = reply == logon }
            else { match = nil }
            return AuthenticationContextDiagnostics(connectionIdentityPresent: diagnostics.connectionIdentityPresent,
                authenticationReplyClientIDPresent: authenticationReplyHasClientID,
                logonNotificationClientIDPresent: logonNotificationHasClientID, replyAndLogonIDsMatch: match)
        }
    }

    private func boundedHeaderClientID(_ header: W.Message) -> Data? {
        guard let values = header[13], values.count == 1, case .bytes(let data) = values[0],
              !data.isEmpty, data.count <= 512 else { return nil }
        return data
    }

    private func send(service: UInt64, method: UInt64, token: UInt64, body: Data, hash: UInt32? = nil, clientID: String? = nil) async throws {
        try Task.checkCancellation()
        guard !closed, body.count <= 1_048_576 else { throw Failure.unavailable }
        var header = W.number(1, service) + W.number(2, method) + W.number(3, token) + W.number(5, UInt64(body.count))
        if let hash { header += W.fixed32(11, hash) }
        if let clientID { header += W.text(13, clientID) }
        let frame = Data([UInt8(header.count >> 8), UInt8(header.count & 255)]) + header + body
        try await transport.send(frame)
    }
    private func exact(_ count: Int) async throws -> Data {
        guard count >= 0, count <= 1_048_576 else { throw Failure.unavailable }
        var result = Data()
        while result.count < count {
            try Task.checkCancellation()
            guard !closed else { throw Failure.unavailable }
            let chunk = try await transport.read(maximum: count - result.count)
            guard !chunk.isEmpty, chunk.count <= count - result.count else { throw Failure.unavailable }
            result += chunk
        }
        return result
    }
    private func receive() async throws -> (W.Message, Data) {
        frames += 1; guard frames <= 100 else { throw Failure.unavailable }
        let prefix = [UInt8](try await exact(2)), length = Int(prefix[0]) * 256 + Int(prefix[1])
        guard length > 0, length <= 8192 else { throw Failure.unavailable }
        let header = try W.decode(await exact(length))
        for field in [1, 2, 3, 5, 6, 9, 11] where header[field] != nil { _ = try W.uint(header, field) }
        let size = try W.uint(header, 5, default: 0)
        guard size <= 1_048_576 else { throw Failure.unavailable }
        return (header, try await exact(Int(size)))
    }
    private func call(hash: UInt32, method: UInt64, body: Data = Data(), replyKind: ReplyKind = .native) async throws -> Data {
        let token = sequence; sequence += 1
        var clientID: String?
        if (replyKind == .sessionDiagnostic || replyKind == .friends), includesConnectionIdentity {
            guard let identity = connectionIdentity else { throw SessionDiagnosticFailure.unavailable(diagnosticStage) }
            clientID = identity
            diagnostics.connectionIdentityIncluded = true
        }
        try await send(service: 0, method: method, token: token, body: body, hash: hash, clientID: clientID)
        while true {
            let (header, response) = try await receive()
            if try W.uint(header, 1) == 254 {
                guard try W.uint(header, 3) == token else { throw Failure.unavailable }
                let status = try W.uint(header, 6, default: 0)
                guard status == 0 else {
                    switch replyKind {
                    case .friends: throw FriendSnapshotFailure.requestRejected(status)
                    case .sessionDiagnostic: throw SessionDiagnosticRefusal.response(status)
                    case .native: throw Failure.rejected(status)
                    }
                }
                if inspectsAuthenticationContext, hash == 0xc02f8216, method == 1 {
                    authenticationReplyHasClientID = header[13] != nil
                    authenticationReplyClientID = boundedHeaderClientID(header)
                }
                return response
            }
            try notification(header, response)
        }
    }
    private func notification(_ header: W.Message, _ body: Data) throws {
        let hash = try W.uint(header, 11), method = try W.uint(header, 2) & 0x3fff_ffff
        guard hash == 0x9da8116b || hash == 0xecb8b826 else {
            if recordsDiagnostics { throw SessionDiagnosticFailure.unexpectedCallback(diagnosticStage, service: hash, method: method) }
            throw Failure.unavailable
        }
        switch method {
        case 1:
            let message = try W.decode(body), status = try W.uint(message, 1, default: 0)
            guard status == 0 else { throw Failure.rejected(status) }
            let record = try W.decode(W.data(message, 2))
            guard try W.uint(record, 1) == expectedOwner else { throw Failure.owner }
            if recordsDiagnostics {
                // Desktop schema names are only hypotheses for this game reply.
                // Observe optional metadata instead of enforcing its wire type.
                diagnostics.logonRecordHasField3 = record[3] != nil
                diagnostics.logonRecordHasField2 = record[2] != nil
                diagnostics.logonRecordHasField5 = record[5] != nil
                diagnostics.logonRecordShape = record.keys.sorted().prefix(64).map { field in
                    let categories = Set((record[field] ?? []).map { value in
                        switch value { case .number: "numeric"; case .bytes: "length-delimited" }
                    }).sorted().joined(separator: "/")
                    return "field \(field): \(categories)"
                }
            }
            if inspectsAuthenticationContext {
                logonNotificationHasClientID = header[13] != nil
                logonNotificationClientID = boundedHeaderClientID(header)
            }
            loggedIn = true
        case 2:
            let state = try W.decode(W.data(W.decode(body), 1))
            for field in state.keys { _ = try W.uint(state, field) }
        case 3: guard body.isEmpty else { throw Failure.unavailable }
        default:
            if recordsDiagnostics { throw SessionDiagnosticFailure.unexpectedCallback(diagnosticStage, service: hash, method: method) }
            throw Failure.unavailable // Never answer an external challenge.
        }
        // These listener methods are NO_RESPONSE: do not send RPC acknowledgements.
    }
}

/// Internal seam for deterministic disconnect/cancellation tests. Production
/// always creates TLSAccountTransport with normal system trust validation.
@MainActor
protocol NativeAccountTransport: AnyObject {
    func connect() async throws
    func send(_ data: Data) async throws
    func read(maximum: Int) async throws -> Data
    func cancel()
}

@MainActor
private final class TLSAccountTransport: NativeAccountTransport {
    private let connection = NWConnection(host: "us.actual.battle.net", port: 1119, using: .tls)
    private var ready: CheckedContinuation<Void, Error>?
    private var closed = false
    func cancel() {
        closed = true; connection.cancel()
        ready?.resume(throwing: CancellationError()); ready = nil
    }
    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard !closed else { continuation.resume(throwing: CancellationError()); return }
            ready = continuation
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, let pending = self.ready else { return }
                    switch state {
                    case .ready: self.ready = nil; pending.resume()
                    case .failed, .cancelled: self.ready = nil; pending.resume(throwing: NativeGameAccounts.Failure.unavailable)
                    default: break
                    }
                }
            }
            connection.start(queue: .main)
        }
    }

    func send(_ data: Data) async throws {
        guard !closed else { throw CancellationError() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if error != nil { continuation.resume(throwing: NativeGameAccounts.Failure.unavailable) }
                else { continuation.resume() }
            })
        }
    }
    func read(maximum: Int) async throws -> Data {
        guard !closed else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximum) { data, _, _, error in
                guard error == nil, let data, !data.isEmpty else {
                    continuation.resume(throwing: NativeGameAccounts.Failure.unavailable); return
                }
                continuation.resume(returning: data)
            }
        }
    }
}
