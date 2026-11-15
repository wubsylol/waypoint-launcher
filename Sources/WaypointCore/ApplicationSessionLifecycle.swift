import Foundation

/// Only fixed labels and booleans cross the lifecycle test's public boundary.
public struct ApplicationSessionTestReport: Sendable {
    public var creationResponseVerified = false
    public var creationCallbackVerified = false
    public var instanceMatchesAuthenticationContext: Bool?
    public var destroyRequestAccepted = false
    public var destructionCallbackVerified = false
    public var outcome = "No creation request submitted"
    public var refusalCode: UInt64?
}

enum ApplicationSessionTestFailure: Error { case identity, malformed, refused(UInt64), unavailable }

/// Connection-scoped state. Private server identifiers are never logged/exported.
final class ApplicationSessionLifecycle {
    private struct Handle: Equatable {
        let id: UInt64
        let title: UInt64
        let region: UInt64
        init(_ data: Data) throws {
            guard data.count <= 128 else { throw ApplicationSessionTestFailure.malformed }
            let m = try BGSWire.decode(data)
            id = try BGSWire.uint(m, 1); title = try BGSWire.uint(m, 2); region = try BGSWire.uint(m, 3)
            guard id > 0, title == 0x417070, region == 1 else { throw ApplicationSessionTestFailure.identity }
        }
        var encoded: Data { BGSWire.number(1, id) + BGSWire.number(2, title) + BGSWire.number(3, region) }
    }
    private struct Identity: Equatable {
        let owner: UInt64
        let handle: Handle
        let instance: String
        let region: UInt64
    }
    private let owner: UInt64
    private let handle: Handle
    private let context: Data
    private var responseIdentity: Identity?
    private var callbackIdentity: Identity?
    private var identityConflict = false
    private(set) var submitted = false
    private(set) var destroySubmitted = false
    private(set) var report = ApplicationSessionTestReport()

    init(owner: UInt64, record: BGSWire.Message, context: Data) throws {
        guard owner > 0, ApplicationHandleMetadata.classify(record) == .matching,
              !context.isEmpty, context.count <= 512,
              let text = String(data: context, encoding: .utf8),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ApplicationSessionTestFailure.unavailable
        }
        let entries = record[2] ?? []
        let matching = entries.compactMap { entry -> Handle? in
            guard case .bytes(let data) = entry else { return nil }
            return try? Handle(data)
        }
        guard matching.count == 1 else { throw ApplicationSessionTestFailure.unavailable }
        self.owner = owner; handle = matching[0]; self.context = context
    }

    var request: Data { BGSWire.bytes(1, handle.encoded) }
    var confirmed: Bool { responseIdentity != nil && responseIdentity == callbackIdentity && !identityConflict }
    var canDestroy: Bool { submitted && responseIdentity != nil && !identityConflict && !destroySubmitted && !report.destructionCallbackVerified }

    func validateContext(_ supplied: Data?) throws {
        guard supplied == context else {
            identityConflict = true
            throw ApplicationSessionTestFailure.identity
        }
    }
    func markSubmitted() { submitted = true; report.outcome = "Creation submitted; cleanup unconfirmed" }
    func acceptCreationResponse(_ data: Data) throws {
        do {
            let m = try BGSWire.decode(data)
            let identity = try parseIdentity(BGSWire.data(m, 1))
            if let callbackIdentity, callbackIdentity != identity { throw ApplicationSessionTestFailure.identity }
            if let responseIdentity, responseIdentity != identity { throw ApplicationSessionTestFailure.identity }
            responseIdentity = identity
            report.creationResponseVerified = true
            report.instanceMatchesAuthenticationContext = Data(identity.instance.utf8) == context
        } catch {
            identityConflict = true
            throw error
        }
    }

    func notification(method: UInt64, headerContext: Data?, data: Data) throws {
        do {
            guard submitted, method == 1 || method == 2 else { throw ApplicationSessionTestFailure.unavailable }
            if let headerContext, headerContext != context { throw ApplicationSessionTestFailure.identity }
            let m = try BGSWire.decode(data)
            let status = try BGSWire.uint(m, 1, default: 0)
            guard status == 0 else { throw ApplicationSessionTestFailure.refused(status) }
            let identity = try parseIdentity(BGSWire.data(m, 3))
            if let responseIdentity, identity != responseIdentity { throw ApplicationSessionTestFailure.identity }
            if let callbackIdentity, identity != callbackIdentity { throw ApplicationSessionTestFailure.identity }
            if method == 1 {
                callbackIdentity = identity
                report.creationCallbackVerified = true
            } else {
                // Do not accept an unrelated destruction event before either ID is known.
                guard responseIdentity != nil || callbackIdentity != nil else { throw ApplicationSessionTestFailure.identity }
                report.destructionCallbackVerified = true
                if report.destroyRequestAccepted { report.outcome = "Destroy acknowledged and matching destruction callback verified; connection closed" }
            }
        } catch {
            identityConflict = true
            throw error
        }
    }

    func markDestroySubmitted() throws {
        guard canDestroy else { throw ApplicationSessionTestFailure.unavailable }
        destroySubmitted = true
    }
    func acceptDestroyResponse() throws {
        guard destroySubmitted, responseIdentity != nil, !identityConflict else { throw ApplicationSessionTestFailure.unavailable }
        report.destroyRequestAccepted = true
        report.outcome = report.destructionCallbackVerified
            ? "Destroy acknowledged and matching destruction callback verified; connection closed"
            : "Destroy acknowledged; matching destruction callback unconfirmed; connection closed"
    }
    func recordFailure(_ error: Error) {
        switch error {
        case ApplicationSessionTestFailure.identity, NativeGameAccounts.Failure.owner,
             AuthenticationContextFailure.missingClientID:
            identityConflict = true
        case is BGSWire.Failure:
            identityConflict = true
        default: break
        }
        if case ApplicationSessionTestFailure.refused(let code) = error { report.refusalCode = code }
        if report.destroyRequestAccepted { return }
        if report.destructionCallbackVerified { report.outcome = "Matching destruction callback observed; connection closed" }
        else if case ApplicationSessionTestFailure.refused = error, !destroySubmitted, responseIdentity == nil, callbackIdentity == nil {
            report.outcome = "Creation refused; no cleanup request sent"
        }
        else if submitted { report.outcome = "Creation may have been submitted; cleanup unconfirmed. No automatic retry." }
        else { report.outcome = "Stopped before creation; no session request submitted" }
    }

    private func parseIdentity(_ data: Data) throws -> Identity {
        guard data.count <= 1024 else { throw ApplicationSessionTestFailure.malformed }
        let m = try BGSWire.decode(data)
        let returnedOwner = try BGSWire.uint(m, 1)
        let returnedHandle = try Handle(BGSWire.data(m, 2))
        let instanceData = try BGSWire.data(m, 3)
        let region = try BGSWire.uint(m, 4)
        guard returnedOwner == owner, returnedHandle == handle, region == 1,
              !instanceData.isEmpty, instanceData.count <= 512,
              let instance = String(data: instanceData, encoding: .utf8),
              !instance.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ApplicationSessionTestFailure.identity
        }
        return Identity(owner: returnedOwner, handle: returnedHandle, instance: instance, region: region)
    }
}
