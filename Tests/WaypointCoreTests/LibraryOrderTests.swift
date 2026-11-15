import Foundation
import Testing
@testable import WaypointCore

@Test func gamesFollowTheDraggedOrderAndNewOnesComeAfterInTheirOwnOrder() {
    let found = ["wow", "hs", "d4", "sc2", "new1", "new2"]
    #expect(LibraryOrder.sorted(found, by: [], id: { $0 }) == found)
    #expect(LibraryOrder.sorted(found, by: ["d4", "wow", "gone", "sc2", "hs"], id: { $0 })
            == ["d4", "wow", "sc2", "hs", "new1", "new2"])
}

@Test func movingAGamePutsItBeforeItsTargetOrLast() {
    let shown = ["wow", "hs", "d4", "sc2"]
    #expect(LibraryOrder.moving("sc2", before: "wow", in: shown, remembered: []) == ["sc2", "wow", "hs", "d4"])
    #expect(LibraryOrder.moving("wow", before: "d4", in: shown, remembered: []) == ["hs", "wow", "d4", "sc2"])
    #expect(LibraryOrder.moving("wow", before: nil, in: shown, remembered: []) == ["hs", "d4", "sc2", "wow"])
    // Dropped where it already is.
    #expect(LibraryOrder.moving("hs", before: "hs", in: shown, remembered: []) == shown)
    #expect(LibraryOrder.moving("hs", before: "d4", in: shown, remembered: []) == shown)
}

@Test func gamesNotShownKeepTheirRememberedPlaceAfterAMove() {
    let order = LibraryOrder.moving("hs", before: "wow", in: ["wow", "hs"], remembered: ["wow", "offline", "hs"])
    #expect(order == ["hs", "wow", "offline"])
    #expect(LibraryOrder.sorted(["wow", "offline", "hs"], by: order, id: { $0 }) == ["hs", "wow", "offline"])
}

@Test func unreadGamesStayBetweenTheGamesTheyFollowedAndDontTravelWithTheDraggedOne() {
    // x and y are on a drive not read yet.
    let remembered = ["a", "x", "b", "c", "y"]
    #expect(LibraryOrder.moving("c", before: "a", in: ["a", "b", "c"], remembered: remembered) == ["c", "a", "x", "b", "y"])
    #expect(LibraryOrder.moving("a", before: nil, in: ["a", "b", "c"], remembered: remembered) == ["x", "b", "c", "y", "a"])
}

@Test func bothHeroesEditionsShareOnePlace() {
    struct Game { let id, uid: String }
    let games = [Game(id: "wow", uid: "wow"), Game(id: "heroes@windows", uid: "heroes")]
    #expect(LibraryOrder.sorted(games, by: ["heroes", "wow"], id: \.uid).map(\.id) == ["heroes@windows", "wow"])
}

@Test func onlyInstalledRowsCanStartDragging() {
    #expect(LibraryDragRules.canStart(rows: IndexSet(integer: 0), installedCount: 2))
    #expect(LibraryDragRules.canStart(rows: IndexSet(integer: 1), installedCount: 2))
    // Header, available title, pending install and foreign indexes are outside the prefix.
    for row in [2, 3, 20] {
        #expect(!LibraryDragRules.canStart(rows: IndexSet(integer: row), installedCount: 2))
    }
    #expect(!LibraryDragRules.canStart(rows: IndexSet(), installedCount: 2))
    #expect(!LibraryDragRules.canStart(rows: IndexSet(integersIn: 0..<2), installedCount: 2))
    #expect(!LibraryDragRules.canStart(rows: IndexSet(integer: 0), installedCount: 0))
}

@Test func availableSectionNeverBecomesADropDestination() {
    for row in [0, 1, 2] {
        #expect(LibraryDragRules.insertionRow(proposed: row, onRow: false, installedCount: 2) == row)
    }
    // A gap before the header is allowed; dropping onto the header/list is not.
    #expect(LibraryDragRules.insertionRow(proposed: 2, onRow: true, installedCount: 2) == nil)
    for row in [-1, 3, 30] {
        #expect(LibraryDragRules.insertionRow(proposed: row, onRow: false, installedCount: 2) == nil)
        #expect(LibraryDragRules.insertionRow(proposed: row, onRow: true, installedCount: 2) == nil)
    }
    #expect(LibraryDragRules.insertionRow(proposed: 0, onRow: false, installedCount: 0) == nil)
}
