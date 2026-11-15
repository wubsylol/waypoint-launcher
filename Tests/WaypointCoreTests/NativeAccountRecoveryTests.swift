import Foundation
import Testing
@testable import WaypointCore

@MainActor
private final class AccountTestTransport: NativeAccountTransport {
    var input: Data
    var cancelled = false
    var cancellationReturnsUnavailable = false
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
    func cancel() { cancelled = true; pending?.resume(throwing: cancellationReturnsUnavailable ? NativeGameAccounts.Failure.unavailable : CancellationError()); pending = nil }
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
    let privateFields = BGSWire.number(1, 42) + BGSWire.text(3, "Friend#1234")
        + BGSWire.text(4, "Synthetic private real name") + BGSWire.bytes(5, BGSWire.text(1, "Synthetic private note"))
    let rich = try FriendSnapshotPage.decode(BGSWire.bytes(1, privateFields))
    #expect(rich.friends == normal.friends) // fetch_names must not expose Real ID/name attributes.
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

@Test @MainActor func sessionDiagnosticsUsesVerifiedLogonContextWithoutCreatingSession() async throws {
    let state = BGSWire.bytes(1, BGSWire.bytes(1, BGSWire.number(1, 123)))
    let replies = [accountFrame(token: 0, body: BGSWire.text(9, "different-transport-id")), accountFrame(token: 1),
        accountFrame(token: 99, body: BGSWire.bytes(2, BGSWire.number(1, 123)), service: 0, method: 1, hash: 0x9da8116b, clientID: "verified-context"),
        accountFrame(token: 2, body: state)]
    let transport = AccountTestTransport(replies.reduce(Data(), +))
    let report = try await NativeGameAccounts(transport: transport).sessionDiagnostics(token: accountTestToken, build: 70938, region: .us, useAuthenticatedClientID: true)
    #expect(report.serverSessionIDPresent == true); #expect(transport.cancelled); #expect(transport.written.count == 3)
    let packet = try #require(transport.written.last), prefix = [UInt8](packet.prefix(2))
    let length = Int(prefix[0]) * 256 + Int(prefix[1]), h = try BGSWire.decode(Data(packet.dropFirst(2).prefix(length)))
    #expect(try BGSWire.data(h, 13) == Data("verified-context".utf8))
    #expect(try BGSWire.uint(h, 11) == 0x7b37d770); #expect(try BGSWire.uint(h, 2) == 5)
    #expect(packet.dropFirst(2 + length).isEmpty)
}

@Test @MainActor func applicationPreflightOnlyRequestsMatchingOwnerCredentialThenCloses() async throws {
    let response = BGSWire.text(1, "US-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-123")
    let transport = AccountTestTransport((Array(accountReplies().prefix(3)) + [accountFrame(token: 2, body: response)]).reduce(Data(), +))
    try await NativeGameAccounts(transport: transport).applicationCredentialPreflight(token: accountTestToken, build: 70938, region: .us)
    #expect(transport.cancelled)
    #expect(transport.written.count == 3) // Connect, WoW logon, issuance; nothing else.
    let packet = try #require(transport.written.last), prefix = [UInt8](packet.prefix(2))
    let length = Int(prefix[0]) * 256 + Int(prefix[1])
    let header = try BGSWire.decode(Data(packet.dropFirst(2).prefix(length)))
    #expect(try BGSWire.uint(header, 11) == 0xc02f8216)
    #expect(try BGSWire.uint(header, 2) == 3)
    let body = try BGSWire.decode(Data(packet.dropFirst(2 + length)))
    #expect(try BGSWire.uint(body, 1) == 0x417070)
    #expect(body.count == 1)
}

@Test @MainActor func applicationPreflightRejectsWrongOwnerBeforeIssuance() async {
    let transport = AccountTestTransport(Array(accountReplies(owner: 999).prefix(3)).reduce(Data(), +))
    do {
        try await NativeGameAccounts(transport: transport).applicationCredentialPreflight(token: accountTestToken, build: 70938, region: .us)
        Issue.record("Wrong owner accepted")
    } catch NativeGameAccounts.Failure.owner { #expect(transport.written.count == 2); #expect(transport.cancelled) }
    catch { Issue.record("Expected owner rejection") }
}

@Test @MainActor func applicationPreflightRejectsMalformedAndWrongOwnerIssuedCredentials() async {
    for text in ["US-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-999", "not a credential", String(repeating: "x", count: 257)] {
        let transport = AccountTestTransport((Array(accountReplies().prefix(3)) + [accountFrame(token: 2, body: BGSWire.text(1, text))]).reduce(Data(), +))
        do {
            try await NativeGameAccounts(transport: transport).applicationCredentialPreflight(token: accountTestToken, build: 70938, region: .us)
            Issue.record("Unverified credential accepted")
        } catch NativeGameAccounts.Failure.owner { #expect(text.hasSuffix("999")) }
        catch ApplicationCredentialFailure.format { #expect(!text.hasSuffix("999")) }
        catch { Issue.record("Expected typed credential failure") }
        #expect(transport.written.count == 3); #expect(transport.cancelled)
    }
}

@Test @MainActor func applicationPreflightLabelsIssuanceRefusalSeparately() async {
    let h = BGSWire.number(1, 254) + BGSWire.number(3, 2) + BGSWire.number(5, 0) + BGSWire.number(6, 3025)
    let rejected = Data([UInt8(h.count >> 8), UInt8(h.count & 255)]) + h
    let transport = AccountTestTransport((Array(accountReplies().prefix(3)) + [rejected]).reduce(Data(), +))
    do {
        try await NativeGameAccounts(transport: transport).applicationCredentialPreflight(token: accountTestToken, build: 70938, region: .us)
        Issue.record("Refused issuance succeeded")
    } catch ApplicationCredentialFailure.refused(let code) { #expect(code == 3025); #expect(transport.cancelled) }
    catch { Issue.record("Issuance refusal mislabeled as authentication") }
}

@Test @MainActor func applicationAuthenticationUsesFreshCredentialAndOnlyConnectsAndLogsOn() async throws {
    let issued = "US-cccccccccccccccccccccccccccccccc-123"
    let source = AccountTestTransport((Array(accountReplies().prefix(3)) + [accountFrame(token: 2, body: BGSWire.text(1, issued))]).reduce(Data(), +))
    let target = AccountTestTransport(Array(accountReplies().prefix(3)).reduce(Data(), +))
    try await NativeGameAccounts(transport: source).applicationAuthenticationPreflight(token: accountTestToken, build: 70938,
        applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
    #expect(source.cancelled && target.cancelled)
    #expect(source.written.count == 3 && target.written.count == 2)
    let packet = target.written[1], prefix = [UInt8](packet.prefix(2))
    let length = Int(prefix[0]) * 256 + Int(prefix[1])
    let header = try BGSWire.decode(Data(packet.dropFirst(2).prefix(length)))
    let body = try BGSWire.decode(Data(packet.dropFirst(2 + length)))
    #expect(try BGSWire.uint(header, 11) == 0xc02f8216)
    #expect(try BGSWire.uint(header, 2) == 1)
    #expect(try BGSWire.uint(body, 1) == 0x417070)
    #expect(try BGSWire.uint(body, 4) == 17986)
    let options = try BGSWire.decode(BGSWire.data(body, 10))
    #expect(try BGSWire.data(options, 1) == Data(issued.utf8))
}

@Test @MainActor func applicationAuthenticationDoesNotConnectTargetWhenIssuanceFails() async {
    let source = AccountTestTransport(Array(accountReplies(owner: 999).prefix(3)).reduce(Data(), +))
    let target = AccountTestTransport()
    do {
        try await NativeGameAccounts(transport: source).applicationAuthenticationPreflight(token: accountTestToken, build: 70938,
            applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
        Issue.record("Unverified source reached target")
    } catch { #expect(source.cancelled); #expect(target.written.isEmpty) }
}

@Test @MainActor func applicationAuthenticationChecksTargetOwner() async {
    let source = AccountTestTransport((Array(accountReplies().prefix(3)) + [accountFrame(token: 2, body: BGSWire.text(1, accountTestToken.value))]).reduce(Data(), +))
    let target = AccountTestTransport(Array(accountReplies(owner: 999).prefix(3)).reduce(Data(), +))
    do {
        try await NativeGameAccounts(transport: source).applicationAuthenticationPreflight(token: accountTestToken, build: 70938,
            applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
        Issue.record("Wrong App owner accepted")
    } catch ApplicationAuthenticationFailure.owner { #expect(source.cancelled && target.cancelled) }
    catch { Issue.record("Expected target owner failure") }
}

@Test @MainActor func applicationAuthenticationSeparatesTargetRefusalFromIssuance() async {
    let source = AccountTestTransport((Array(accountReplies().prefix(3)) + [accountFrame(token: 2, body: BGSWire.text(1, accountTestToken.value))]).reduce(Data(), +))
    let h = BGSWire.number(1, 254) + BGSWire.number(3, 1) + BGSWire.number(5, 0) + BGSWire.number(6, 3025)
    let refused = Data([UInt8(h.count >> 8), UInt8(h.count & 255)]) + h
    let target = AccountTestTransport(accountFrame(token: 0) + refused)
    do {
        try await NativeGameAccounts(transport: source).applicationAuthenticationPreflight(token: accountTestToken, build: 70938,
            applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
        Issue.record("Refused App logon succeeded")
    } catch ApplicationAuthenticationFailure.refused(let code) {
        #expect(code == 3025); #expect(source.cancelled && target.cancelled)
        #expect(source.written.count == 3 && target.written.count == 2)
    } catch { Issue.record("Expected target-authentication refusal") }
}

@Test @MainActor func applicationAuthenticationCancellationClosesTargetWithoutFurtherRequests() async {
    let source = AccountTestTransport((Array(accountReplies().prefix(3)) + [accountFrame(token: 2, body: BGSWire.text(1, accountTestToken.value))]).reduce(Data(), +))
    let target = AccountTestTransport(accountFrame(token: 0), stall: true)
    target.cancellationReturnsUnavailable = true // Match NWConnection's cancelled-read behavior.
    let task = Task {
        try await NativeGameAccounts(transport: source).applicationAuthenticationPreflight(token: accountTestToken, build: 70938,
            applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
    }
    while target.pending == nil { await Task.yield() }
    task.cancel()
    do { try await task.value; Issue.record("Cancelled App logon succeeded") }
    catch is CancellationError { #expect(source.cancelled && target.cancelled); #expect(target.pending == nil) }
    catch { Issue.record("Cancelled target transport was mislabeled as authentication failure") }
    #expect(source.written.count == 3 && target.written.count == 2)
}

private func applicationIssuanceReplies() -> Data {
    (Array(accountReplies().prefix(3)) + [accountFrame(token: 2,
        body: BGSWire.text(1, "US-dddddddddddddddddddddddddddddddd-123"))]).reduce(Data(), +)
}

@Test @MainActor func applicationFriendsUsesApplicationLogonAndVerifiedContextOnly() async throws {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let target = AccountTestTransport(authenticatedContextReplies().reduce(Data(), +))
    let result = try await NativeGameAccounts(transport: source).applicationFriendsPreflight(token: accountTestToken,
        build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
    #expect(result.count == 1)
    #expect(source.cancelled && target.cancelled)
    #expect(source.written.count == 3 && target.written.count == 3)
    let auth = target.written[1], authLength = Int(auth[0]) * 256 + Int(auth[1])
    let authBody = try BGSWire.decode(Data(auth.dropFirst(2 + authLength)))
    #expect(try BGSWire.uint(authBody, 1) == 0x417070)
    #expect(try BGSWire.uint(authBody, 4) == 17986)
    let options = try BGSWire.decode(BGSWire.data(authBody, 10))
    #expect(try BGSWire.data(options, 1) == Data("US-dddddddddddddddddddddddddddddddd-123".utf8))
    let packet = target.written[2], length = Int(packet[0]) * 256 + Int(packet[1])
    let header = try BGSWire.decode(Data(packet.dropFirst(2).prefix(length)))
    #expect(try BGSWire.uint(header, 11) == 0x5869be8c)
    #expect(try BGSWire.uint(header, 2) == 5)
    #expect(try BGSWire.data(header, 13) == Data("synthetic-authenticated-id".utf8))
    let request = try BGSWire.decode(Data(packet.dropFirst(2 + length)))
    let nameOptions = try BGSWire.decode(BGSWire.data(request, 1))
    #expect(try BGSWire.uint(nameOptions, 1) == 1)
    #expect(request.count == 1)
}

@Test @MainActor func applicationFriendsMissingContextStopsBeforeSocialRequest() async {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let target = AccountTestTransport(authenticatedContextReplies(logonID: nil).reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: source).applicationFriendsPreflight(token: accountTestToken,
            build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
        Issue.record("Missing context reached friends")
    } catch AuthenticationContextFailure.missingClientID { #expect(target.written.count == 2) }
    catch { Issue.record("Expected missing authenticated context") }
    #expect(source.cancelled && target.cancelled)
}

@Test @MainActor func applicationFriendsRefusalRemainsSocialFailure() async {
    let h = BGSWire.number(1, 254) + BGSWire.number(3, 2) + BGSWire.number(5, 0) + BGSWire.number(6, 3025)
    let refused = Data([UInt8(h.count >> 8), UInt8(h.count & 255)]) + h
    let source = AccountTestTransport(applicationIssuanceReplies())
    let target = AccountTestTransport(Array(authenticatedContextReplies().prefix(3)).reduce(Data(), +) + refused)
    do {
        _ = try await NativeGameAccounts(transport: source).applicationFriendsPreflight(token: accountTestToken,
            build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
        Issue.record("Refused friends request succeeded")
    } catch FriendSnapshotFailure.requestRejected(let code) { #expect(code == 3025) }
    catch { Issue.record("Social refusal mislabeled as authentication failure") }
    #expect(source.cancelled && target.cancelled)
    #expect(target.written.count == 3)
}

@Test @MainActor func applicationFriendsRequestsNamesOnEveryContinuationPage() async throws {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let logon = Array(authenticatedContextReplies().prefix(3))
    let first = accountFrame(token: 2, body: friendPage(42, tag: "Synthetic#1234", continuation: 9))
    let second = accountFrame(token: 3, body: friendPage(43, tag: "Other#5678") + BGSWire.text(88, "discarded"))
    let target = AccountTestTransport((logon + [first, second]).reduce(Data(), +))
    let result = try await NativeGameAccounts(transport: source).applicationFriendsPreflight(token: accountTestToken,
        build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.battleTag != nil })
    #expect(target.written.count == 4 && target.cancelled && source.cancelled)
    for (index, packet) in target.written.dropFirst(2).enumerated() {
        let length = Int(packet[0]) * 256 + Int(packet[1])
        let body = try BGSWire.decode(Data(packet.dropFirst(2 + length)))
        let options = try BGSWire.decode(BGSWire.data(body, 1))
        #expect(try BGSWire.uint(options, 1) == 1)
        if index == 1 { #expect(try BGSWire.uint(body, 2) == 9) }
        else { #expect(body[2] == nil) }
    }
}

private func presencePage(friend: UInt64, title: UInt64 = 0x576f57) -> Data {
    let key = BGSWire.number(1, 0x424e) + BGSWire.number(2, 1) + BGSWire.number(3, 13) + BGSWire.number(4, 987654321)
    let field = BGSWire.bytes(1, key) + BGSWire.bytes(2, BGSWire.number(6, 1))
    let unrequested = BGSWire.bytes(1, BGSWire.number(1, 0x424e) + BGSWire.number(2, 1) + BGSWire.number(3, 1))
        + BGSWire.bytes(2, BGSWire.text(4, "Synthetic private real name"))
    let handle = BGSWire.number(1, 888888888) + BGSWire.number(2, title) + BGSWire.number(3, 1)
    return BGSWire.bytes(1, BGSWire.number(1, friend) + BGSWire.bytes(2, handle)
        + BGSWire.bytes(3, field) + BGSWire.bytes(3, unrequested))
}

@Test func presenceDiagnosticRequestOnlyIncludesFixedAllowlistAndGameQueryScope() throws {
    let body = try BGSWire.decode(PresenceDiagnosticPage.request(friendID: 42))
    #expect(try BGSWire.uint(body, 1) == 42)
    #expect(try BGSWire.uint(body, 2) == 2)
    let keys = try #require(body[3])
    #expect(keys.count == 4 && body.count == 3)
    for (index, value) in keys.enumerated() {
        guard case .bytes(let bytes) = value else { Issue.record("Non-message key"); return }
        let key = try BGSWire.decode(bytes), expected = PresenceDiagnosticPage.keys[index]
        #expect(try BGSWire.uint(key, 1) == expected.0)
        #expect(try BGSWire.uint(key, 2) == expected.1)
        #expect(try BGSWire.uint(key, 3) == expected.2)
        #expect(try BGSWire.uint(key, 4) == 0)
        #expect(key.count == 4) // Explicit zero is not a guessed private identifier.
    }
}

@Test func presenceDiagnosticDiscardsIdentitiesAndValuesAndRejectsWrongFriend() throws {
    let report = try PresenceDiagnosticPage.decode(presencePage(friend: 42), expectedFriend: 42)
    #expect(report.states == 1)
    #expect(report.gameTitles == ["World of Warcraft"])
    #expect(report.fieldKinds == ["BN 1/13: unsigned integer"])
    #expect(throws: (any Error).self) { try PresenceDiagnosticPage.decode(presencePage(friend: 43), expectedFriend: 42) }
    #expect(try PresenceDiagnosticPage.decode(Data(), expectedFriend: 42).fieldKinds.isEmpty)
    let tooMany = (0..<65).map { _ in BGSWire.bytes(1, BGSWire.number(1, 42)) }.reduce(Data(), +)
    #expect(throws: (any Error).self) { try PresenceDiagnosticPage.decode(tooMany, expectedFriend: 42) }
}

@Test @MainActor func applicationPresenceSamplesOnlyThreeCurrentFriendsWithVerifiedContext() async throws {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let roster = [42,43,44,45].map { BGSWire.bytes(1, BGSWire.number(1, UInt64($0))) }.reduce(Data(), +)
    var replies = Array(authenticatedContextReplies().prefix(3)) + [accountFrame(token: 2, body: roster)]
    for (index, id) in [42,43,44].enumerated() { replies.append(accountFrame(token: UInt64(index + 3), body: presencePage(friend: UInt64(id)))) }
    let target = AccountTestTransport(replies.reduce(Data(), +))
    let report = try await NativeGameAccounts(transport: source).applicationPresencePreflight(token: accountTestToken,
        build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
    #expect(report.sampledFriends == 3 && report.states == 3)
    #expect(source.cancelled && target.cancelled)
    #expect(source.written.count == 3 && target.written.count == 6)
    let rosterRequest = target.written[2], rosterHeaderLength = Int(rosterRequest[0]) * 256 + Int(rosterRequest[1])
    #expect(rosterRequest.dropFirst(2 + rosterHeaderLength).isEmpty) // No names requested.
    for packet in target.written.dropFirst(3) {
        let length = Int(packet[0]) * 256 + Int(packet[1])
        let header = try BGSWire.decode(Data(packet.dropFirst(2).prefix(length)))
        let body = try BGSWire.decode(Data(packet.dropFirst(2 + length)))
        #expect(try BGSWire.uint(header, 11) == 0x138d200c)
        #expect(try BGSWire.uint(header, 2) == 5)
        #expect(try BGSWire.data(header, 13) == Data("synthetic-authenticated-id".utf8))
        #expect([42,43,44].contains(try BGSWire.uint(body, 1)))
    }
}

@Test @MainActor func applicationPresenceRefusalStopsWithoutFallback() async {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let h = BGSWire.number(1, 254) + BGSWire.number(3, 3) + BGSWire.number(5, 0) + BGSWire.number(6, 3025)
    let refused = Data([UInt8(h.count >> 8), UInt8(h.count & 255)]) + h
    let target = AccountTestTransport(authenticatedContextReplies().reduce(Data(), +) + refused)
    do {
        _ = try await NativeGameAccounts(transport: source).applicationPresencePreflight(token: accountTestToken,
            build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
        Issue.record("Refused presence succeeded")
    } catch PresenceQueryFailure.refused(let code) { #expect(code == 3025) }
    catch { Issue.record("Presence refusal mislabeled") }
    #expect(source.cancelled && target.cancelled)
    #expect(target.written.count == 4)
}

@Test @MainActor func applicationPresenceCancellationClosesPendingQuery() async {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let target = AccountTestTransport(authenticatedContextReplies().reduce(Data(), +), stall: true)
    target.cancellationReturnsUnavailable = true
    let task = Task {
        try await NativeGameAccounts(transport: source).applicationPresencePreflight(token: accountTestToken,
            build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
    }
    while target.pending == nil { await Task.yield() }
    task.cancel()
    do { _ = try await task.value; Issue.record("Cancelled presence succeeded") }
    catch is CancellationError { #expect(source.cancelled && target.cancelled) }
    catch { Issue.record("Cancelled query mislabeled") }
    #expect(target.written.count == 4)
}

@Test func presenceExplicitZeroControlChangesOnlyKeyMemberPresence() throws {
    var original = BGSWire.number(1, 42) + BGSWire.number(2, 2)
    for (title, group, field) in PresenceDiagnosticPage.keys {
        original += BGSWire.bytes(3, BGSWire.number(1, title) + BGSWire.number(2, group) + BGSWire.number(3, field))
    }
    let before = try BGSWire.decode(original)
    let after = try BGSWire.decode(PresenceDiagnosticPage.request(friendID: 42))
    #expect(before[1] == after[1] && before[2] == after[2])
    let previousKeys = try #require(before[3]), currentKeys = try #require(after[3])
    #expect(previousKeys.count == currentKeys.count)
    for (previous, current) in zip(previousKeys, currentKeys) {
        guard case .bytes(let oldData) = previous, case .bytes(let newData) = current else { Issue.record("Nonmessage key"); return }
        let old = try BGSWire.decode(oldData), new = try BGSWire.decode(newData)
        for field in 1...3 { #expect(old[field] == new[field]) }
        #expect(old[4] == nil && new.count == old.count + 1)
        #expect(try BGSWire.uint(new, 4) == 0)
    }
}

@Test @MainActor func applicationSessionPreflightQueriesAppContextOnlyAndKeepsRefusalUnknown() async throws {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let header = BGSWire.number(1, 254) + BGSWire.number(3, 2) + BGSWire.number(5, 0) + BGSWire.number(6, 7)
    let refusal = Data([UInt8(header.count >> 8), UInt8(header.count & 255)]) + header
    let target = AccountTestTransport(Array(authenticatedContextReplies().prefix(3)).reduce(Data(), +) + refusal)
    let report = try await NativeGameAccounts(transport: source).applicationSessionPreflight(token: accountTestToken,
        build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
    #expect(report.sessionQueryStatus == 7 && report.serverSessionIDPresent == nil)
    #expect(source.cancelled && target.cancelled)
    #expect(source.written.count == 3 && target.written.count == 3)
    let auth = target.written[1], authLength = Int(auth[0]) * 256 + Int(auth[1])
    let body = try BGSWire.decode(Data(auth.dropFirst(2 + authLength)))
    #expect(try BGSWire.uint(body, 1) == 0x417070)
    let query = target.written[2], queryLength = Int(query[0]) * 256 + Int(query[1])
    let h = try BGSWire.decode(Data(query.dropFirst(2).prefix(queryLength)))
    #expect(try BGSWire.uint(h, 11) == 0x7b37d770)
    #expect(try BGSWire.uint(h, 2) == 5)
    #expect(try BGSWire.data(h, 13) == Data("synthetic-authenticated-id".utf8))
    #expect(query.dropFirst(2 + queryLength).isEmpty)
}

@Test @MainActor func applicationSessionPreflightRejectsAnotherOwnersReturnedSession() async {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let state = BGSWire.bytes(1, BGSWire.bytes(1, BGSWire.number(1, 999)))
    let target = AccountTestTransport(Array(authenticatedContextReplies().prefix(3)).reduce(Data(), +) + accountFrame(token: 2, body: state))
    do {
        _ = try await NativeGameAccounts(transport: source).applicationSessionPreflight(token: accountTestToken,
            build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
        Issue.record("Another owner's session was accepted")
    } catch NativeGameAccounts.Failure.owner { #expect(source.cancelled && target.cancelled) }
    catch { Issue.record("Expected session-owner validation failure") }
}

@Test func applicationHandleMetadataClassifiesOnlyBoundedExplicitAppHandles() {
    func entry(_ id: UInt64, title: UInt64 = 0x417070, region: UInt64 = 1) -> BGSWire.Value {
        .bytes(BGSWire.number(1, id) + BGSWire.number(2, title) + BGSWire.number(3, region))
    }
    #expect(ApplicationHandleMetadata.classify([:]) == .missing)
    #expect(ApplicationHandleMetadata.classify([2: [entry(456)]]) == .matching)
    #expect(ApplicationHandleMetadata.classify([2: [entry(456, title: 0x576f57)]]) == .other)
    #expect(ApplicationHandleMetadata.classify([2: [entry(456, region: 2)]]) == .other)
    #expect(ApplicationHandleMetadata.classify([2: [entry(456), entry(789)]]) == .ambiguous)
    #expect(ApplicationHandleMetadata.classify([2: [.number(3)]]) == .unrecognized)
    #expect(ApplicationHandleMetadata.classify([2: [entry(0)]]) == .unrecognized)
    #expect(ApplicationHandleMetadata.classify([2: Array(repeating: entry(456), count: 101)]) == .unrecognized)
}

@Test @MainActor func applicationHandleCheckOnlyAuthenticatesAndReportsClassification() async throws {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let handle = BGSWire.number(1, 456) + BGSWire.number(2, 0x417070) + BGSWire.number(3, 1)
    let record = BGSWire.number(1, 123) + BGSWire.bytes(2, handle)
    let targetReplies = [accountFrame(token: 0), accountFrame(token: 1),
        accountFrame(token: 99, body: BGSWire.bytes(2, record), service: 0, method: 1, hash: 0x9da8116b, clientID: "synthetic-app-context")]
    let target = AccountTestTransport(targetReplies.reduce(Data(), +))
    let report = try await NativeGameAccounts(transport: source).applicationHandlePreflight(token: accountTestToken,
        build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
    #expect(report.state == .matching && report.authenticatedContextPresent)
    #expect(source.cancelled && target.cancelled)
    #expect(source.written.count == 3 && target.written.count == 2)
}

private func appLifecycleRecord() -> Data {
    BGSWire.number(1, 123) + BGSWire.bytes(2,
        BGSWire.number(1, 456) + BGSWire.number(2, 0x417070) + BGSWire.number(3, 1))
}
private func appLifecycleIdentity(owner: UInt64 = 123, handleID: UInt64 = 456, region: UInt64 = 1,
                                  instance: String = "synthetic-app-instance") -> Data {
    BGSWire.number(1, owner) + BGSWire.bytes(2,
        BGSWire.number(1, handleID) + BGSWire.number(2, 0x417070) + BGSWire.number(3, 1))
        + BGSWire.text(3, instance) + BGSWire.number(4, region)
}
private func appLifecycleAuthReplies() -> [Data] {
    [accountFrame(token: 0), accountFrame(token: 1), accountFrame(token: 99,
        body: BGSWire.bytes(2, appLifecycleRecord()), service: 0, method: 1,
        hash: 0x9da8116b, clientID: "synthetic-app-context")]
}
private func appLifecycleNotification(_ method: UInt64, identity: Data = appLifecycleIdentity(), context: String = "synthetic-app-context") -> Data {
    accountFrame(token: 99, body: BGSWire.bytes(3, identity), service: 0, method: method,
        hash: 0xbca72135, clientID: context)
}

@Test func appLifecycleValidatesReplyAndCallbackInEitherOrder() throws {
    for callbackFirst in [true, false] {
        let model = try ApplicationSessionLifecycle(owner: 123, record: BGSWire.decode(appLifecycleRecord()),
            context: Data("synthetic-app-context".utf8))
        model.markSubmitted()
        let response = BGSWire.bytes(1, appLifecycleIdentity())
        let callback = BGSWire.bytes(3, appLifecycleIdentity())
        if callbackFirst { try model.notification(method: 1, headerContext: nil, data: callback) }
        try model.acceptCreationResponse(response)
        if !callbackFirst { try model.notification(method: 1, headerContext: nil, data: callback) }
        #expect(model.confirmed && model.canDestroy)
        #expect(model.report.instanceMatchesAuthenticationContext == false)
        try model.markDestroySubmitted()
        try model.acceptDestroyResponse()
        #expect(model.report.destroyRequestAccepted)
        #expect(!model.canDestroy)
    }
}

@Test func appLifecycleRejectsForeignOrAmbiguousIdentitiesBeforeCleanup() throws {
    for identity in [appLifecycleIdentity(owner: 999), appLifecycleIdentity(handleID: 789),
                     appLifecycleIdentity(region: 2), appLifecycleIdentity(instance: "bad\ninstance")] {
        let model = try ApplicationSessionLifecycle(owner: 123, record: BGSWire.decode(appLifecycleRecord()), context: Data("context".utf8))
        model.markSubmitted()
        #expect(throws: (any Error).self) { try model.acceptCreationResponse(BGSWire.bytes(1, identity)) }
        #expect(!model.canDestroy)
    }
    let model = try ApplicationSessionLifecycle(owner: 123, record: BGSWire.decode(appLifecycleRecord()), context: Data("context".utf8))
    model.markSubmitted()
    try model.acceptCreationResponse(BGSWire.bytes(1, appLifecycleIdentity()))
    #expect(throws: (any Error).self) {
        try model.notification(method: 1, headerContext: Data("foreign".utf8), data: BGSWire.bytes(3, appLifecycleIdentity()))
    }
    #expect(!model.canDestroy)
    let mismatch = try ApplicationSessionLifecycle(owner: 123, record: BGSWire.decode(appLifecycleRecord()), context: Data("context".utf8))
    mismatch.markSubmitted()
    try mismatch.acceptCreationResponse(BGSWire.bytes(1, appLifecycleIdentity()))
    #expect(throws: (any Error).self) {
        try mismatch.notification(method: 1, headerContext: nil,
            data: BGSWire.bytes(3, appLifecycleIdentity(instance: "different-synthetic-instance")))
    }
    #expect(!mismatch.canDestroy)
}

@Test @MainActor func appLifecycleDispatchesOnlyCreateAndDestroyWithOwnAppHandleAndContext() async throws {
    for callbackFirst in [true, false] {
      for destructionFirst in [true, false] {
        let source = AccountTestTransport(applicationIssuanceReplies())
        let response = accountFrame(token: 2, body: BGSWire.bytes(1, appLifecycleIdentity()))
        let created = appLifecycleNotification(1)
        let target = AccountTestTransport((appLifecycleAuthReplies() + (callbackFirst ? [created,response] : [response,created])
            + (destructionFirst ? [appLifecycleNotification(2), accountFrame(token: 3)] : [accountFrame(token: 3), appLifecycleNotification(2)])).reduce(Data(), +))
        let report = try await NativeGameAccounts(transport: source).applicationSessionLifecycleTest(token: accountTestToken,
            build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
        #expect(report.creationResponseVerified && report.creationCallbackVerified && report.destroyRequestAccepted && report.destructionCallbackVerified)
        #expect(source.cancelled && target.cancelled)
        #expect(source.written.count == 3 && target.written.count == 4)
        for (index, packet) in target.written.dropFirst(2).enumerated() {
            let length = Int(packet[0]) * 256 + Int(packet[1])
            let header = try BGSWire.decode(Data(packet.dropFirst(2).prefix(length)))
            #expect(try BGSWire.uint(header, 11) == 0x7b37d770)
            #expect(try BGSWire.uint(header, 2) == (index == 0 ? 1 : 3))
            #expect(try BGSWire.data(header, 13) == Data("synthetic-app-context".utf8))
            let data = Data(packet.dropFirst(2 + length))
            if index == 0 {
                let body = try BGSWire.decode(data), handle = try BGSWire.decode(BGSWire.data(body, 1))
                #expect(body.count == 1 && handle.count == 3)
                #expect(try BGSWire.uint(handle, 1) == 456)
                #expect(try BGSWire.uint(handle, 2) == 0x417070)
                #expect(try BGSWire.uint(handle, 3) == 1)
            } else { #expect(data.isEmpty) }
        }
    }
}

}

@Test @MainActor func appLifecycleDoesNotCreateWithoutExplicitAppHandle() async {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let target = AccountTestTransport(Array(authenticatedContextReplies().prefix(3)).reduce(Data(), +))
    do {
        _ = try await NativeGameAccounts(transport: source).applicationSessionLifecycleTest(token: accountTestToken,
            build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
        Issue.record("Missing App handle reached creation")
    } catch { #expect(target.written.count == 2); #expect(source.cancelled && target.cancelled) }
}

@Test @MainActor func appLifecycleRefusedCreationDoesNotDestroyOrRetry() async throws {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let h = BGSWire.number(1, 254) + BGSWire.number(3, 2) + BGSWire.number(5, 0) + BGSWire.number(6, 7)
    let target = AccountTestTransport(appLifecycleAuthReplies().reduce(Data(), +) + Data([UInt8(h.count >> 8), UInt8(h.count & 255)]) + h)
    let report = try await NativeGameAccounts(transport: source).applicationSessionLifecycleTest(token: accountTestToken,
        build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
    #expect(report.refusalCode == 7 && !report.creationResponseVerified && !report.destroyRequestAccepted)
    #expect(target.written.count == 3 && target.cancelled)
}

@Test @MainActor func appLifecycleInvalidCreatedOwnerDoesNotSendDestruction() async throws {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let target = AccountTestTransport((appLifecycleAuthReplies() + [accountFrame(token: 2,
        body: BGSWire.bytes(1, appLifecycleIdentity(owner: 999)))]).reduce(Data(), +))
    let report = try await NativeGameAccounts(transport: source).applicationSessionLifecycleTest(token: accountTestToken,
        build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
    #expect(!report.creationResponseVerified && !report.destroyRequestAccepted)
    #expect(report.outcome.contains("unconfirmed"))
    #expect(target.written.count == 3 && target.cancelled)
}

@Test @MainActor func appLifecycleInterruptedAfterCreationReportsCleanupUnknownWithoutReconnecting() async throws {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let target = AccountTestTransport((appLifecycleAuthReplies() + [accountFrame(token: 2,
        body: BGSWire.bytes(1, appLifecycleIdentity()))]).reduce(Data(), +), stall: true)
    target.cancellationReturnsUnavailable = true
    let task = Task {
        try await NativeGameAccounts(transport: source).applicationSessionLifecycleTest(token: accountTestToken,
            build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
    }
    while target.pending == nil { await Task.yield() }
    task.cancel()
    let report = try await task.value
    #expect(report.creationResponseVerified && !report.destroyRequestAccepted)
    #expect(report.outcome.contains("unconfirmed"))
    #expect(source.cancelled && target.cancelled && target.written.count == 3)
}

@Test @MainActor func appLifecycleExternalIdentityFailuresNeverTriggerDestruction() async throws {
    let body = BGSWire.bytes(3, appLifecycleIdentity())
    let malformedHeader = BGSWire.number(1, 0) + BGSWire.number(2, 1) + BGSWire.number(3, 99)
        + BGSWire.number(5, UInt64(body.count)) + BGSWire.fixed32(11, 0xbca72135) + BGSWire.number(13, 123)
    let malformedContext = Data([UInt8(malformedHeader.count >> 8), UInt8(malformedHeader.count & 255)]) + malformedHeader + body
    let foreignAuth = accountFrame(token: 99, body: BGSWire.bytes(2, BGSWire.number(1, 999)),
        service: 0, method: 1, hash: 0x9da8116b, clientID: "foreign-context")
    let changedContextAuth = accountFrame(token: 99, body: BGSWire.bytes(2, appLifecycleRecord()),
        service: 0, method: 1, hash: 0x9da8116b, clientID: "changed-context")
    for event in [malformedContext, foreignAuth, changedContextAuth] {
        let source = AccountTestTransport(applicationIssuanceReplies())
        let target = AccountTestTransport((appLifecycleAuthReplies() + [accountFrame(token: 2,
            body: BGSWire.bytes(1, appLifecycleIdentity())), event]).reduce(Data(), +))
        let report = try await NativeGameAccounts(transport: source).applicationSessionLifecycleTest(token: accountTestToken,
            build: 70938, applicationBuild: 17986, region: .us, applicationClient: NativeGameAccounts(transport: target))
        #expect(report.creationResponseVerified && !report.destroyRequestAccepted)
        #expect(report.outcome.contains("unconfirmed"))
        #expect(target.written.count == 3 && source.cancelled && target.cancelled)
    }
}

@Test @MainActor func appLifecycleMissingDestructionCallbackRemainsUnconfirmedWithoutRetry() async throws {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let target = AccountTestTransport((appLifecycleAuthReplies() + [
        accountFrame(token: 2, body: BGSWire.bytes(1, appLifecycleIdentity())),
        appLifecycleNotification(1), accountFrame(token: 3)]).reduce(Data(), +), stall: true)
    let report = try await NativeGameAccounts(transport: source).applicationSessionLifecycleTest(token: accountTestToken,
        build: 70938, applicationBuild: 17986, region: .us,
        applicationClient: NativeGameAccounts(transport: target, timeout: .milliseconds(30)))
    #expect(report.destroyRequestAccepted && !report.destructionCallbackVerified)
    #expect(report.outcome.contains("unconfirmed"))
    #expect(target.cancelled && target.written.count == 4)
}

@Test @MainActor func appLifecycleForeignDestructionAfterAcknowledgmentRemainsUnconfirmed() async throws {
    let source = AccountTestTransport(applicationIssuanceReplies())
    let target = AccountTestTransport((appLifecycleAuthReplies() + [
        accountFrame(token: 2, body: BGSWire.bytes(1, appLifecycleIdentity())),
        appLifecycleNotification(1), accountFrame(token: 3),
        appLifecycleNotification(2, context: "foreign-context")]).reduce(Data(), +))
    let report = try await NativeGameAccounts(transport: source).applicationSessionLifecycleTest(token: accountTestToken,
        build: 70938, applicationBuild: 17986, region: .us,
        applicationClient: NativeGameAccounts(transport: target))
    #expect(report.destroyRequestAccepted && !report.destructionCallbackVerified)
    #expect(report.outcome.contains("unconfirmed"))
    #expect(target.cancelled && target.written.count == 4)
}
