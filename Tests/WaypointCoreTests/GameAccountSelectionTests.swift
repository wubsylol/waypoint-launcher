import Foundation
import Testing
@testable import WaypointCore

@Test func gameAccountChoiceIsScopedToOwnerEditionAndRegion() {
    var choices = GameAccountSelections()
    let one = GameAccountSelection(accountID:"101",name:"WoW1",region:"us")
    let two = GameAccountSelection(accountID:"102",name:"WoW2",region:"us")
    choices.select(one,owner:"owner-a",uid:"wowf",region:"US")
    choices.select(two,owner:"owner-a",uid:"wow",region:"us")
    #expect(choices.choice(owner:"owner-a",uid:"wowf",region:"us") == one)
    #expect(choices.choice(owner:"owner-a",uid:"wow",region:"US") == two)
    #expect(choices.choice(owner:"owner-b",uid:"wowf",region:"us") == nil)
    #expect(choices.choice(owner:"owner-a",uid:"wowf",region:"eu") == nil)
}
@Test func selectedGameAccountSurvivesRestartAndOwnerRemovalIsIsolated() throws {
    let suite="WaypointCoreTests.gameChoices.\(UUID().uuidString)"
    let defaults=try #require(UserDefaults(suiteName:suite))
    defer { defaults.removePersistentDomain(forName:suite) }
    var choices=GameAccountSelections()
    let one=GameAccountSelection(accountID:"101",name:"WoW1",region:"us")
    let two=GameAccountSelection(accountID:"102",name:"WoW2",region:"us")
    choices.select(one,owner:"owner-a",uid:"wowf",region:"us")
    choices.select(two,owner:"owner-a",uid:"wowf",region:"us")
    choices.select(one,owner:"owner-b",uid:"wowf",region:"us")
    choices.save(to:defaults)
    var loaded=GameAccountSelections.load(from:defaults)
    #expect(loaded.choice(owner:"owner-a",uid:"wowf",region:"us") == two)
    loaded.remove(owner:"owner-a")
    #expect(loaded.choice(owner:"owner-a",uid:"wowf",region:"us") == nil)
    #expect(loaded.choice(owner:"owner-b",uid:"wowf",region:"us") == one)
}
@Test func explicitGameAccountHandoffReplacesPreviousSelectionWithMatchingToken() throws {
    let suite="WaypointCoreTests.gameHandoff.\(UUID().uuidString)"
    let defaults=try #require(UserDefaults(suiteName:suite))
    defer { defaults.removePersistentDomain(forName:suite) }
    let options=LaunchOptions(gameKey:"WoW",userName:"testuser",preferencesDomain:suite)
    let one="US-0123456789abcdef0123456789abcdef-111"
    let two="US-fedcba9876543210fedcba9876543210-222"
    try options.write(token:one,region:.us,locale:"enUS",gameAccount:"WoW1")
    #expect(defaults.string(forKey:options.gameAccountKey) == "WoW1")
    try options.write(token:two,region:.eu,locale:"enGB",gameAccount:"WoW2")
    #expect(defaults.string(forKey:options.gameAccountKey) == "WoW2")
    #expect(try options.storedToken() == two)
    #expect(options.storedRegion() == "EU")
    #expect(options.storedLocale() == "enGB")
}

@Test func defaultWoWChoiceAppliesAcrossEditionsWithoutReplacingOverrides() throws {
    var choices = GameAccountSelections()
    let one = GameAccountSelection(accountID: "101", name: "WoW1", region: "us")
    let two = GameAccountSelection(accountID: "102", name: "WoW2", region: "us")
    choices.select(two, owner: "owner-a", uid: "wow", region: "us")
    choices.selectDefault(one, owner: "owner-a", region: "US")
    #expect(choices.choice(owner: "owner-a", uid: "wowf", region: "us") == one)
    #expect(choices.choice(owner: "owner-a", uid: "wow", region: "us") == two)
    #expect(choices.choice(owner: "owner-b", uid: "wowf", region: "us") == nil)
    #expect(choices.choice(owner: "owner-a", uid: "wowf", region: "eu") == nil)
    let suite = "WaypointCoreTests.defaultLicence.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    choices.save(to: defaults)
    let saved = GameAccountSelections.load(from: defaults)
    #expect(saved.defaultChoice(owner: "owner-a", region: "us") == one)
    #expect(saved.choice(owner: "owner-a", uid: "wow", region: "us") == two)
}

@Test func gameAccountCatalogPersistsOnlyOwnerAndRegionValidatedLists() throws {
    var catalogs = GameAccountCatalogs()
    let one = GameAccountSelection(accountID: "101", name: "WoW1", region: "us")
    let two = GameAccountSelection(accountID: "102", name: "WoW1", region: "us")
    #expect(catalogs.accounts(owner: "owner-a", region: "us") == nil)
    let stored = catalogs.cache([one, two], owner: "owner-a", region: "US")
    #expect(stored)
    #expect(catalogs.accounts(owner: "owner-b", region: "us") == nil)
    #expect(catalogs.accounts(owner: "owner-a", region: "eu") == nil)
    let duplicates = catalogs.cache([one, one], owner: "owner-a", region: "us")
    #expect(!duplicates)
    let wrongRegion = catalogs.cache([one], owner: "owner-a", region: "eu")
    #expect(!wrongRegion)
    let malformed = catalogs.cache([GameAccountSelection(accountID: "103", name: "WoW3\n", region: "us")], owner: "owner-a", region: "us")
    #expect(!malformed)
    #expect(catalogs.accounts(owner: "owner-a", region: "us") == [one, two])
    let suite = "WaypointCoreTests.licenceCatalog.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    catalogs.save(to: defaults)
    var loaded = GameAccountCatalogs.load(from: defaults)
    #expect(loaded.accounts(owner: "owner-a", region: "us") == [one, two])
    let empty = loaded.cache([], owner: "owner-a", region: "us")
    #expect(empty)
    #expect(loaded.accounts(owner: "owner-a", region: "us") == [])
    loaded.remove(owner: "owner-b")
    #expect(loaded.accounts(owner: "owner-a", region: "us") == [])
    loaded.remove(owner: "owner-a")
    #expect(loaded.accounts(owner: "owner-a", region: "us") == nil)
}

@Test func unselectedWoWLaunchDoesNotInheritAnotherOwnerOrRegionLicence() throws {
    let suite = "WaypointCoreTests.unselectedLicence.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let options = LaunchOptions(gameKey: "WoW", userName: "testuser", preferencesDomain: suite)
    try options.write(token: "US-0123456789abcdef0123456789abcdef-111", region: .us, locale: "enUS", gameAccount: "WoW1")
    try options.write(token: "US-fedcba9876543210fedcba9876543210-222", region: .eu, locale: "enGB")
    #expect(defaults.string(forKey: options.gameAccountKey) == nil)
    #expect(options.storedRegion() == "EU")
}
