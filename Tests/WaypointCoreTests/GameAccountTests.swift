import Foundation
import Testing
@testable import WaypointCore

private func catalog(_ accounts: String) throws -> GameAccountCatalog {
    try GameAccountCatalog.decode(Data("{\"gameAccounts\":[\(accounts)]}".utf8))
}
private let wowOne = #"{"titleId":"WoW","gameAccountUniqueId":{"gameAccountId":101},"gameAccountName":"WoW1","gameAccountRegion":"US","gameAccountStatus":"Good"}"#
private let wowTwo = #"{"titleId":"WoW","gameAccountUniqueId":{"gameAccountId":"102"},"gameAccountName":"WoW2","gameAccountRegion":"US","gameAccountStatus":"Banned"}"#

@Test func discoversMultipleGameAccountsWithoutGuessingLaunchSelectors() throws {
    let accounts = try catalog(wowOne + "," + wowTwo).gameAccounts
    #expect(accounts.map(\.name) == ["WoW1", "WoW2"])
    #expect(accounts.map(\.accountID) == ["101", "102"])
    #expect(accounts.last?.status == "Banned") // Don't hide unavailable accounts or infer eligibility.
}
@Test func gameAccountIdentifiersPreserveIntegerPrecision() throws {
    let account = try #require(catalog(wowOne.replacingOccurrences(of: "101", with: "9007199254740993")).gameAccounts.first)
    #expect(account.accountID == "9007199254740993")
}
@Test func gameAccountIdentityIncludesRegionAndTitle() throws {
    let eu = wowOne.replacingOccurrences(of: "US", with: "EU")
    let other = wowOne.replacingOccurrences(of: "WoW\"", with: "Other\"")
    #expect(try catalog(wowOne + "," + eu + "," + other).gameAccounts.count == 3)
    #expect(throws: (any Error).self) { try catalog(wowOne + "," + wowOne) }
}
@Test func invalidGameAccountSchemasFailClosed() throws {
    for data in ["{}", "{\"gameAccounts\":null}", "{\"gameAccounts\":[{}]}"] {
        #expect(throws: (any Error).self) { try GameAccountCatalog.decode(Data(data.utf8)) }
    }
    for value in ["true", "1.5", "-1", "null"] {
        #expect(throws: (any Error).self) { try catalog(wowOne.replacingOccurrences(of: "101", with: value)) }
    }
    #expect(throws: (any Error).self) { try catalog(wowOne.replacingOccurrences(of: "WoW1", with: "")) }
    #expect(try catalog("").gameAccounts.isEmpty)
}
