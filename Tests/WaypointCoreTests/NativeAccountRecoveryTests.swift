import Foundation
import Testing
@testable import WaypointCore

@MainActor
private final class AccountTestTransport: NativeAccountTransport {
    var input: Data
    var cancelled = false
    var pending: CheckedContinuation<Data, Error>?
    var connectFails = false
    var sendFailsAt: Int?
    var written: [Data] = []
    var sends = 0
    var stall: Bool
    init(_ input: Data = Data(), stall: Bool = false) { self.input = input; self.stall = stall }
    func connect() async throws { if connectFails { throw NativeGameAccounts.Failure.unavailable } }
    func send(_ data: Data) async throws {
        written.append(data)
        sends += 1
        if cancelled { throw CancellationError() }
        if sends == sendFailsAt { throw NativeGameAccounts.Failure.unavailable }
    }
    func read(maximum: Int) async throws -> Data {
        if cancelled { throw CancellationError() }
        if input.isEmpty {
            if stall { return try await withCheckedThrowingContinuation { pending = $0 } }
            throw NativeGameAccounts.Failure.unavailable
        }
        // Exercise fragmentation independently of message boundaries.
        let chunk = Data(input.prefix(min(maximum, 3))); input.removeFirst(chunk.count); return chunk
    }
    func cancel() { cancelled = true; pending?.resume(throwing: CancellationError()); pending = nil }
}
private func accountFrame(token: UInt64, body: Data = Data(), service: UInt64 = 254, method: UInt64? = nil, hash: UInt32? = nil, clientID: String? = nil) -> Data {
    var h = BGSWire.number(1, service) + BGSWire.number(3, token) + BGSWire.number(5, UInt64(body.count))
    if let method { h += BGSWire.number(2, method) }
    if let hash { h += BGSWire.fixed32(11, hash) }
    if let clientID { h += BGSWire.text(13, clientID) }
    return Data([UInt8(h.count >> 8), UInt8(h.count & 255)]) + h + body
}
private func accountReplies(owner: UInt64 = 123) -> [Data] {
    let handle = BGSWire.number(1, 456) + BGSWire.number(2, 5730135) + BGSWire.number(3, 1)
    return [accountFrame(token: 0), accountFrame(token: 1),
            accountFrame(token: 99, body: BGSWire.bytes(2, BGSWire.number(1, owner)), service: 0, method: 1, hash: 0x9da8116b),
            accountFrame(token: 2, body: BGSWire.bytes(1, BGSWire.bytes(1, handle))),
            accountFrame(token: 3, body: BGSWire.bytes(1, BGSWire.number(1, owner) + BGSWire.text(2, "Test licence")))]
}
private let accountTestToken = LoginToken("US-0123456789abcdef0123456789abcdef-123")!

@Test @MainActor func nativeDiscoveryDisconnectsFailClosedAndFreshRetrySucceeds() async throws {
    let replies = accountReplies(), complete = replies.reduce(Data(), +)
    // Before connect response, during logon, before links, and mid-info reply.
    for cut in [0, replies[0].count + 1, replies.prefix(3).reduce(0) { $0 + $1.count }, complete.count - 1] {
        let broken = AccountTestTransport(Data(complete.prefix(cut)))
        do {
            _ = try await NativeGameAccounts(transport: broken).discover(token: accountTestToken, build: 70938, region: .us)
            Issue.record("Disconnected discovery returned a catalogue")
        } catch { #expect(broken.cancelled) }
    }
    let restored = AccountTestTransport(complete)
    let accounts = try await NativeGameAccounts(transport: restored).discover(token: accountTestToken, build: 70938, region: .us)
    #expect(accounts.map(\.name) == ["Test licence"])
    #expect(restored.cancelled)
}
@Test @MainActor func nativeDiscoveryRejectsWrongOwner() async {
    let transport = AccountTestTransport(accountReplies(owner: 999).reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: transport).discover(token: accountTestToken, build: 70938, region: .us)
        Issue.record("Wrong-owner discovery succeeded")
    } catch NativeGameAccounts.Failure.owner { #expect(transport.cancelled) }
    catch { Issue.record("Wrong-owner discovery did not report identity mismatch") }
}
@Test @MainActor func nativeDiscoveryDeadlineClosesStalledConnection() async {
    let transport = AccountTestTransport(stall: true)
    do {
        _ = try await NativeGameAccounts(transport: transport, timeout: .milliseconds(20)).discover(token: accountTestToken, build: 70938, region: .us)
        Issue.record("Stalled connection succeeded")
    } catch { #expect(transport.cancelled); #expect(transport.pending == nil) }
}
@Test @MainActor func nativeDiscoveryCancellationClosesPendingRead() async {
    let transport = AccountTestTransport(stall: true)
    let task = Task { try await NativeGameAccounts(transport: transport).discover(token: accountTestToken, build: 70938, region: .us) }
    while transport.pending == nil { await Task.yield() }
    task.cancel()
    do { _ = try await task.value; Issue.record("Cancelled discovery succeeded") }
    catch { #expect(transport.cancelled); #expect(transport.pending == nil) }
}

@Test @MainActor func nativeDiscoveryConnectAndSendFailuresCloseTransport() async {
    for failConnect in [true, false] {
        let transport = AccountTestTransport(accountReplies().reduce(Data(), +))
        transport.connectFails = failConnect; transport.sendFailsAt = 2
        do {
            _ = try await NativeGameAccounts(transport: transport).discover(token: accountTestToken, build: 70938, region: .us)
            Issue.record("Failed transport returned a catalogue")
        } catch { #expect(transport.cancelled) }
    }
}
@Test @MainActor func nativeDiscoveryChecksOwnerAgainWhenResolvingNames() async {
    var replies = accountReplies()
    replies[4] = accountFrame(token: 3, body: BGSWire.bytes(1, BGSWire.number(1, 999) + BGSWire.text(2, "Other licence")))
    let transport = AccountTestTransport(replies.reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: transport).discover(token: accountTestToken, build: 70938, region: .us)
        Issue.record("Wrong-owner account info returned a catalogue")
    } catch NativeGameAccounts.Failure.owner { #expect(transport.cancelled) }
    catch { Issue.record("Account-info owner mismatch was not recognized") }
}


private func friendPage(_ id: UInt64, tag: String, continuation: UInt64? = nil) -> Data {
    var page = BGSWire.bytes(1, BGSWire.number(1, id) + BGSWire.text(3, tag) + BGSWire.text(4, "Private real name") + BGSWire.text(7, "Private note"))
    if let continuation { page += BGSWire.number(2, continuation) }
    return page
}
@Test @MainActor func friendsSnapshotPagesReadOnlyRequestsAndClosesSession() async throws {
    let replies = Array(accountReplies().prefix(3)) + [
        accountFrame(token: 2, body: friendPage(42, tag: "Friend#1234", continuation: 11)),
        accountFrame(token: 3, body: friendPage(43, tag: "Other#5678"))]
    let transport = AccountTestTransport(replies.reduce(Data(), +))
    let friends = try await NativeGameAccounts(transport: transport).friends(token: accountTestToken, build: 70938, region: .us)
    #expect(friends.map(\.displayName) == ["Friend#1234", "Other#5678"])
    #expect(transport.cancelled)
    // After connection/authentication, every request is GetFriends v2 method 5.
    for packet in transport.written.dropFirst(2) {
        let prefix = [UInt8](packet.prefix(2)), count = Int(prefix[0]) * 256 + Int(prefix[1])
        let h = try BGSWire.decode(Data(packet.dropFirst(2).prefix(count)))
        #expect(try BGSWire.uint(h, 11) == 0x5869be8c)
        #expect(try BGSWire.uint(h, 2) == 5)
    }
}
@Test @MainActor func friendsSnapshotRejectsDuplicateIDsAndLoopedPagination() async {
    for second in [friendPage(42, tag: "Again#1234"), friendPage(43, tag: "Other#5678", continuation: 11)] {
        let replies = Array(accountReplies().prefix(3)) + [accountFrame(token: 2, body: friendPage(42, tag: "Friend#1234", continuation: 11)), accountFrame(token: 3, body: second)]
        let transport = AccountTestTransport(replies.reduce(Data(), +))
        do {
            _ = try await NativeGameAccounts(transport: transport).friends(token: accountTestToken, build: 70938, region: .us)
            Issue.record("Malformed friends pagination returned a list")
        } catch { #expect(transport.cancelled) }
    }
}
@Test @MainActor func friendsSnapshotRejectsWrongOwnerBeforeSocialRequest() async {
    let transport = AccountTestTransport(Array(accountReplies(owner: 999).prefix(3)).reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: transport).friends(token: accountTestToken, build: 70938, region: .us)
        Issue.record("Wrong-owner friends snapshot succeeded")
    } catch NativeGameAccounts.Failure.owner { #expect(transport.written.count == 2); #expect(transport.cancelled) }
    catch { Issue.record("Wrong-owner result did not report mismatch") }
}
@Test func friendSnapshotParserRejectsBadNamesAndDoesNotExposePrivateFields() throws {
    let normal = try FriendSnapshotPage.decode(friendPage(42, tag: "Friend#1234"))
    #expect(normal.friends.first?.battleTag == "Friend#1234")
    #expect(normal.friends.first?.id == "42")
    let missing = try FriendSnapshotPage.decode(BGSWire.bytes(1, BGSWire.number(1, 42)))
    #expect(missing.friends.first?.displayName == "Friend 42")
    for bytes in [BGSWire.number(1, 0), BGSWire.number(1, 42) + BGSWire.text(3, "bad\nname"), BGSWire.number(1, 42) + BGSWire.text(3, String(repeating: "x", count: 257))] {
        #expect(throws: (any Error).self) { try FriendSnapshotPage.decode(BGSWire.bytes(1, bytes)) }
    }
    #expect(try FriendSnapshotPage.decode(Data()).friends.isEmpty)
}

@Test @MainActor func friendsSnapshotDistinguishesDisabledSocialMethodFromAuthenticationFailure() async {
    let disabled = BGSWire.number(1, 254) + BGSWire.number(3, 2) + BGSWire.number(5, 0) + BGSWire.number(6, 3025)
    let frame = Data([UInt8(disabled.count >> 8), UInt8(disabled.count & 255)]) + disabled
    let transport = AccountTestTransport((Array(accountReplies().prefix(3)) + [frame]).reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: transport).friends(token: accountTestToken, build: 70938, region: .us)
        Issue.record("Disabled social method returned a friends list")
    } catch FriendSnapshotFailure.requestRejected(let code) { #expect(code == 3025); #expect(transport.cancelled) }
    catch { Issue.record("Social rejection misreported as authentication failure") }
}

@Test @MainActor func friendsSnapshotDoesNotMislabelAnAuthenticationNotificationAsSocialRejection() async {
    let notification = accountFrame(token: 99, body: BGSWire.number(1, 3025), service: 0, method: 1, hash: 0x9da8116b)
    let transport = AccountTestTransport((Array(accountReplies().prefix(3)) + [notification]).reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: transport).friends(token: accountTestToken, build: 70938, region: .us)
        Issue.record("Rejected authentication notification returned friends")
    } catch NativeGameAccounts.Failure.rejected(let code) { #expect(code == 3025); #expect(transport.cancelled) }
    catch { Issue.record("Authentication notification was mislabeled as social rejection") }
}


private func legacyFriend(_ low: UInt64) -> Data {
    // Exercise fixed64 wire encoding, not just the codec’s varint path.
    func fixed(_ field: Int, _ value: UInt64) -> Data {
        BGSWire.varint(UInt64(field << 3 | 1)) + Data((0..<8).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    return BGSWire.bytes(1, BGSWire.bytes(1, fixed(1, 0x100000000000000) + fixed(2, low)))
}
@Test @MainActor func friendsSnapshotLegacyUsesOnlyReadOnlyMethodAndDiscardsNames() async throws {
    let page = legacyFriend(42) + legacyFriend(43)
    let transport = AccountTestTransport((Array(accountReplies().prefix(3)) + [accountFrame(token: 2, body: page)]).reduce(Data(), +))
    let result = try await NativeGameAccounts(transport: transport).friends(token: accountTestToken, build: 70938, region: .us, protocolVersion: .legacy)
    #expect(result.count == 2); #expect(result.allSatisfy { $0.battleTag == nil }); #expect(transport.cancelled)
    #expect(transport.written.count == 3)
    let packet = try #require(transport.written.last), prefix = [UInt8](packet.prefix(2))
    let count = Int(prefix[0]) * 256 + Int(prefix[1])
    let header = try BGSWire.decode(Data(packet.dropFirst(2).prefix(count)))
    #expect(try BGSWire.uint(header, 11) == 0xa3ddb1bd)
    #expect(try BGSWire.uint(header, 2) == 13)
    #expect(try BGSWire.uint(header, 5) == 0)
}
@Test func friendsSnapshotLegacyRejectsDuplicateOrMissingEntityIDs() throws {
    #expect(try LegacyFriendSnapshot.decode(Data()).isEmpty)
    for data in [legacyFriend(42) + legacyFriend(42), legacyFriend(0), BGSWire.bytes(1, Data())] {
        #expect(throws: (any Error).self) { try LegacyFriendSnapshot.decode(data) }
    }
}

@Test @MainActor func friendsSnapshotSubscriptionReadsFieldFiveThenCloses() async throws {
    let entry = try BGSWire.data(BGSWire.decode(legacyFriend(42)), 1)
    let page = BGSWire.number(1, 200) + BGSWire.bytes(5, entry)
    let transport = AccountTestTransport((Array(accountReplies().prefix(3)) + [accountFrame(token: 2, body: page)]).reduce(Data(), +))
    let result = try await NativeGameAccounts(transport: transport).friends(token: accountTestToken, build: 70938, region: .us, protocolVersion: .legacySubscription)
    #expect(result.count == 1); #expect(transport.cancelled); #expect(transport.written.count == 3)
    let packet = try #require(transport.written.last), prefix = [UInt8](packet.prefix(2))
    let count = Int(prefix[0]) * 256 + Int(prefix[1])
    let header = try BGSWire.decode(Data(packet.dropFirst(2).prefix(count)))
    #expect(try BGSWire.uint(header, 11) == 0xa3ddb1bd)
    #expect(try BGSWire.uint(header, 2) == 1)
    let body = try BGSWire.decode(Data(packet.dropFirst(2 + count)))
    #expect(body.count == 1); #expect(try BGSWire.uint(body, 2) == 1)
}

@Test @MainActor func friendsSnapshotClientCallControlChangesOnlyMethodFlag() async throws {
    let replies = Array(accountReplies().prefix(3)) + [accountFrame(token: 2, body: friendPage(42, tag: "Friend#1234"))]
    var requests: [[Data]] = []
    for mode in [FriendSnapshotProtocol.current, .currentClientCall] {
        let transport = AccountTestTransport(replies.reduce(Data(), +))
        let result = try await NativeGameAccounts(transport: transport).friends(token: accountTestToken, build: 70938, region: .us, protocolVersion: mode)
        #expect(result.count == 1); #expect(transport.cancelled); #expect(transport.written.count == 3)
        requests.append(transport.written)
    }
    #expect(Array(requests[0].prefix(2)) == Array(requests[1].prefix(2)))
    var headers: [BGSWire.Message] = []
    for packet in requests.map({ $0[2] }) {
        let prefix = [UInt8](packet.prefix(2)), length = Int(prefix[0]) * 256 + Int(prefix[1])
        headers.append(try BGSWire.decode(Data(packet.dropFirst(2).prefix(length))))
        #expect(packet.dropFirst(2 + length).isEmpty)
    }
    #expect(try BGSWire.uint(headers[0], 2) == 5)
    #expect(try BGSWire.uint(headers[1], 2) == 0x40000005)
    headers[0].removeValue(forKey: 2); headers[1].removeValue(forKey: 2)
    #expect(headers[0] == headers[1])
}


private func diagnosticReplies(queryBody: Data, owner: UInt64 = 123) -> [Data] {
    [accountFrame(token: 0, body: BGSWire.number(7, 1) + BGSWire.text(9, "synthetic-connection-id")), accountFrame(token: 1),
     accountFrame(token: 99, body: BGSWire.bytes(2, BGSWire.number(1, owner) + BGSWire.text(3, "Synthetic#1234") + BGSWire.bytes(5, Data([1,2,3]))), service: 0, method: 1, hash: 0x9da8116b),
     accountFrame(token: 2, body: queryBody)]
}
@Test @MainActor func sessionDiagnosticsReadsExistingStateWithoutSessionMutation() async throws {
    let state = BGSWire.bytes(1, BGSWire.bytes(1, BGSWire.number(1, 123)))
    let transport = AccountTestTransport(diagnosticReplies(queryBody: state).reduce(Data(), +))
    let report = try await NativeGameAccounts(transport: transport).sessionDiagnostics(token: accountTestToken, build: 70938, region: .us)
    #expect(report.bindlessAccepted == true); #expect(report.connectionIdentityPresent)
    #expect(report.logonRecordHasField3); #expect(report.logonRecordHasField5); #expect(!report.logonRecordHasField2)
    #expect(report.sessionQueryStatus == 0); #expect(report.serverSessionIDPresent == true)
    #expect(transport.cancelled); #expect(transport.written.count == 3)
    let packet = try #require(transport.written.last), prefix = [UInt8](packet.prefix(2))
    let length = Int(prefix[0]) * 256 + Int(prefix[1]), header = try BGSWire.decode(Data(packet.dropFirst(2).prefix(length)))
    #expect(try BGSWire.uint(header, 11) == 0x7b37d770); #expect(try BGSWire.uint(header, 2) == 5)
    #expect(packet.dropFirst(2 + length).isEmpty)
}
@Test @MainActor func sessionDiagnosticsRefusalDoesNotClaimNoExistingSession() async throws {
    var replies = diagnosticReplies(queryBody: Data())
    let header = BGSWire.number(1, 254) + BGSWire.number(3, 2) + BGSWire.number(5, 0) + BGSWire.number(6, 3025)
    replies[3] = Data([UInt8(header.count >> 8), UInt8(header.count & 255)]) + header
    let transport = AccountTestTransport(replies.reduce(Data(), +))
    let report = try await NativeGameAccounts(transport: transport).sessionDiagnostics(token: accountTestToken, build: 70938, region: .us)
    #expect(report.sessionQueryStatus == 3025); #expect(report.serverSessionIDPresent == nil)
    #expect(report.connectionIdentityPresent); #expect(transport.cancelled)
}
@Test @MainActor func sessionDiagnosticsRejectsAnotherOwnersSession() async {
    let state = BGSWire.bytes(1, BGSWire.bytes(1, BGSWire.number(1, 999)))
    let transport = AccountTestTransport(diagnosticReplies(queryBody: state).reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: transport).sessionDiagnostics(token: accountTestToken, build: 70938, region: .us)
        Issue.record("Accepted another owner's session metadata")
    } catch NativeGameAccounts.Failure.owner { #expect(transport.cancelled) }
    catch { Issue.record("Expected session owner mismatch") }
}

@Test @MainActor func sessionDiagnosticsObservesVariantMetadataWithoutRejectingAuthentication() async throws {
    var replies = diagnosticReplies(queryBody: Data())
    replies[0] = accountFrame(token: 0, body: BGSWire.number(7, 99) + BGSWire.number(9, 123))
    replies[2] = accountFrame(token: 99, body: BGSWire.bytes(2, BGSWire.number(1, 123) + BGSWire.number(3, 99) + BGSWire.number(5, 55)), service: 0, method: 1, hash: 0x9da8116b)
    let transport = AccountTestTransport(replies.reduce(Data(), +))
    let report = try await NativeGameAccounts(transport: transport).sessionDiagnostics(token: accountTestToken, build: 70938, region: .us)
    #expect(report.bindlessAccepted == nil); #expect(report.connectionIdentityPresent)
    #expect(report.logonRecordHasField3); #expect(report.logonRecordHasField5)
    #expect(report.logonRecordShape == ["field 1: numeric", "field 3: numeric", "field 5: numeric"])
    #expect(!report.logonRecordShape.joined().contains("123")); #expect(transport.cancelled)
}
@Test @MainActor func sessionDiagnosticsLabelsUnsupportedCallbackAtQueryStage() async {
    var replies = diagnosticReplies(queryBody: Data())
    replies[3] = accountFrame(token: 99, body: Data(), service: 0, method: 7, hash: 0x12345678)
    let transport = AccountTestTransport(replies.reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: transport).sessionDiagnostics(token: accountTestToken, build: 70938, region: .us)
        Issue.record("Unsupported callback accepted")
    } catch SessionDiagnosticFailure.unexpectedCallback(let stage, let hash, let method) {
        #expect(stage == .query); #expect(hash == 0x12345678); #expect(method == 7); #expect(transport.cancelled)
    } catch { Issue.record("Callback failed without safe stage classification") }
}

@Test @MainActor func sessionDiagnosticsIdentityControlChangesOnlyQueryHeader() async throws {
    var written: [[Data]] = []
    for includeIdentity in [false, true] {
        let transport = AccountTestTransport(diagnosticReplies(queryBody: Data()).reduce(Data(), +))
        let report = try await NativeGameAccounts(transport: transport).sessionDiagnostics(token: accountTestToken, build: 70938, region: .us, includeConnectionIdentity: includeIdentity)
        #expect(report.connectionIdentityIncluded == includeIdentity)
        #expect(transport.cancelled); #expect(transport.written.count == 3)
        written.append(transport.written)
    }
    #expect(Array(written[0].prefix(2)) == Array(written[1].prefix(2)))
    var headers: [BGSWire.Message] = []
    for packet in written.map({ $0[2] }) {
        let prefix = [UInt8](packet.prefix(2)), length = Int(prefix[0]) * 256 + Int(prefix[1])
        headers.append(try BGSWire.decode(Data(packet.dropFirst(2).prefix(length))))
        #expect(packet.dropFirst(2 + length).isEmpty)
    }
    #expect(headers[0][13] == nil)
    #expect(try BGSWire.data(headers[1], 13) == Data("synthetic-connection-id".utf8))
    headers[1].removeValue(forKey: 13)
    #expect(headers[0] == headers[1])
}
@Test @MainActor func sessionDiagnosticsRefusesToInventAMissingConnectionIdentity() async {
    var replies = diagnosticReplies(queryBody: Data()); replies[0] = accountFrame(token: 0)
    let transport = AccountTestTransport(replies.reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: transport).sessionDiagnostics(token: accountTestToken, build: 70938, region: .us, includeConnectionIdentity: true)
        Issue.record("Sent query without the required control identity")
    } catch SessionDiagnosticFailure.malformed(let stage) {
        #expect(stage == .connectionMetadata); #expect(transport.written.count == 1); #expect(transport.cancelled)
    } catch { Issue.record("Missing control identity failed without metadata classification") }
}

@Test @MainActor func friendsSnapshotIdentityControlChangesOnlyOriginalV2Header() async throws {
    var written: [[Data]] = []
    for includeIdentity in [false, true] {
        let replies = Array(diagnosticReplies(queryBody: Data()).prefix(3)) + [accountFrame(token: 2, body: friendPage(42, tag: "Synthetic#1234"))]
        let transport = AccountTestTransport(replies.reduce(Data(), +))
        let result = try await NativeGameAccounts(transport: transport).friends(token: accountTestToken, build: 70938, region: .us, includeConnectionIdentity: includeIdentity)
        #expect(result.count == 1); #expect(transport.cancelled); #expect(transport.written.count == 3)
        written.append(transport.written)
    }
    #expect(Array(written[0].prefix(2)) == Array(written[1].prefix(2)))
    var headers: [BGSWire.Message] = []
    for packet in written.map({ $0[2] }) {
        let prefix = [UInt8](packet.prefix(2)), length = Int(prefix[0]) * 256 + Int(prefix[1])
        let header = try BGSWire.decode(Data(packet.dropFirst(2).prefix(length)))
        #expect(try BGSWire.uint(header, 2) == 5); #expect(try BGSWire.uint(header, 11) == 0x5869be8c)
        headers.append(header); #expect(packet.dropFirst(2 + length).isEmpty)
    }
    #expect(headers[0][13] == nil)
    #expect(try BGSWire.data(headers[1], 13) == Data("synthetic-connection-id".utf8))
    headers[1].removeValue(forKey: 13); #expect(headers[0] == headers[1])
}

@Test @MainActor func authenticationContextDiagnosticsOnlyConnectsAndAuthenticates() async throws {
    for ids in [(nil, nil), ("synthetic-id", "synthetic-id"), ("reply-id", "logon-id")] as [(String?, String?)] {
        let replies = [accountFrame(token: 0, body: BGSWire.text(9, "synthetic-transport-id")),
            accountFrame(token: 1, clientID: ids.0),
            accountFrame(token: 99, body: BGSWire.bytes(2, BGSWire.number(1, 123)), service: 0, method: 1, hash: 0x9da8116b, clientID: ids.1)]
        let transport = AccountTestTransport(replies.reduce(Data(), +))
        let report = try await NativeGameAccounts(transport: transport).authenticationContextDiagnostics(token: accountTestToken, build: 70938, region: .us)
        #expect(report.connectionIdentityPresent)
        #expect(report.authenticationReplyClientIDPresent == (ids.0 != nil))
        #expect(report.logonNotificationClientIDPresent == (ids.1 != nil))
        #expect(report.replyAndLogonIDsMatch == (ids.0 == nil || ids.1 == nil ? nil : ids.0 == ids.1))
        #expect(transport.written.count == 2); #expect(transport.cancelled)
    }
}
@Test @MainActor func authenticationContextDiagnosticsRejectsWrongOwner() async {
    let transport = AccountTestTransport(Array(accountReplies(owner: 999).prefix(3)).reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: transport).authenticationContextDiagnostics(token: accountTestToken, build: 70938, region: .us)
        Issue.record("Returned context for wrong account")
    } catch NativeGameAccounts.Failure.owner { #expect(transport.cancelled); #expect(transport.written.count == 2) }
    catch { Issue.record("Expected owner validation before context report") }
}


private func authenticatedContextReplies(logonID: String? = "synthetic-authenticated-id", replyID: String? = nil) -> [Data] {
    [accountFrame(token: 0, body: BGSWire.text(9, "different-transport-id")), accountFrame(token: 1),
     accountFrame(token: 99, body: BGSWire.bytes(2, BGSWire.number(1, 123)), service: 0, method: 1, hash: 0x9da8116b, clientID: logonID),
     accountFrame(token: 2, body: friendPage(42, tag: "Synthetic#1234"), clientID: replyID)]
}
@Test @MainActor func friendsSnapshotUsesOwnerVerifiedLogonIDNotTransportID() async throws {
    let transport = AccountTestTransport(authenticatedContextReplies().reduce(Data(), +))
    let result = try await NativeGameAccounts(transport: transport).friends(token: accountTestToken, build: 70938, region: .us, protocolVersion: .authenticatedContext)
    #expect(result.count == 1); #expect(transport.written.count == 3); #expect(transport.cancelled)
    let packet = try #require(transport.written.last), prefix = [UInt8](packet.prefix(2))
    let length = Int(prefix[0]) * 256 + Int(prefix[1]), header = try BGSWire.decode(Data(packet.dropFirst(2).prefix(length)))
    #expect(try BGSWire.data(header, 13) == Data("synthetic-authenticated-id".utf8))
    #expect(try BGSWire.uint(header, 11) == 0x5869be8c); #expect(try BGSWire.uint(header, 2) == 5)
    #expect(packet.dropFirst(2 + length).isEmpty)
}
@Test @MainActor func friendsSnapshotMissingAuthenticatedIDDoesNotGuessOrQuery() async {
    let transport = AccountTestTransport(authenticatedContextReplies(logonID: nil).reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: transport).friends(token: accountTestToken, build: 70938, region: .us, protocolVersion: .authenticatedContext)
        Issue.record("Used transport ID when authenticated ID was missing")
    } catch AuthenticationContextFailure.missingClientID { #expect(transport.written.count == 2); #expect(transport.cancelled) }
    catch { Issue.record("Expected missing authenticated context classification") }
}
@Test @MainActor func friendsSnapshotRejectsAnotherLogicalClientsReply() async {
    let transport = AccountTestTransport(authenticatedContextReplies(replyID: "different-logical-client").reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: transport).friends(token: accountTestToken, build: 70938, region: .us, protocolVersion: .authenticatedContext)
        Issue.record("Accepted another logical client's reply")
    } catch NativeGameAccounts.Failure.owner { #expect(transport.cancelled) }
    catch { Issue.record("Expected fail-closed context identity mismatch") }
}
