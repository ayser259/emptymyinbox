import XCTest
@testable import EmptyMyInboxShared

final class ActionItemsNavigationTests: XCTestCase {
    func testPriorityBucketIdNilAndRange() {
        let none = VaultActionItemRecord(title: "a", priority: nil)
        XCTAssertEqual(ActionItemsFeatureModel.priorityBucketId(for: none), "none")

        for p in 0 ... 4 {
            let item = VaultActionItemRecord(title: "t", priority: p)
            XCTAssertEqual(ActionItemsFeatureModel.priorityBucketId(for: item), "p\(p)")
        }

        let other = VaultActionItemRecord(title: "x", priority: 99)
        XCTAssertEqual(ActionItemsFeatureModel.priorityBucketId(for: other), "other")
    }

    func testUrgencyBucketIdNilAndRange() {
        let none = VaultActionItemRecord(title: "a", urgency: nil)
        XCTAssertEqual(ActionItemsFeatureModel.urgencyBucketId(for: none), "none")

        for u in 0 ... 4 {
            let item = VaultActionItemRecord(title: "t", urgency: u)
            XCTAssertEqual(ActionItemsFeatureModel.urgencyBucketId(for: item), "u\(u)")
        }

        let other = VaultActionItemRecord(title: "x", urgency: -1)
        XCTAssertEqual(ActionItemsFeatureModel.urgencyBucketId(for: other), "other")
    }

    func testBoardColumnsForPriorityOrdersBuckets() {
        let items: [VaultActionItemRecord] = [
            VaultActionItemRecord(id: "1", title: "n", priority: nil),
            VaultActionItemRecord(id: "2", title: "p0", priority: 0),
            VaultActionItemRecord(id: "3", title: "p4", priority: 4),
            VaultActionItemRecord(id: "4", title: "bad", priority: 7)
        ]
        let cols = ActionItemsFeatureModel.boardColumnsForPriority(items)
        XCTAssertEqual(cols.map(\.boardId), ["p0", "p1", "p2", "p3", "p4", "none", "other"])
        XCTAssertEqual(cols.first(where: { $0.boardId == "p0" })?.items.count, 1)
        XCTAssertEqual(cols.first(where: { $0.boardId == "none" })?.items.count, 1)
        XCTAssertEqual(cols.first(where: { $0.boardId == "other" })?.items.count, 1)
    }

    func testBoardColumnsForUrgencyOrdersBuckets() {
        let items: [VaultActionItemRecord] = [
            VaultActionItemRecord(id: "1", title: "n", urgency: nil),
            VaultActionItemRecord(id: "2", title: "u1", urgency: 1)
        ]
        let cols = ActionItemsFeatureModel.boardColumnsForUrgency(items)
        XCTAssertEqual(cols.map(\.boardId), ["u0", "u1", "u2", "u3", "u4", "none"])
        XCTAssertEqual(cols.first(where: { $0.boardId == "u1" })?.items.count, 1)
        XCTAssertEqual(cols.first(where: { $0.boardId == "none" })?.items.count, 1)
    }

    func testActionItemsSectionCategoryCasesExcludesPlanner() {
        XCTAssertTrue(ActionItemsSection.categoryCases.allSatisfy { $0 != .planner })
        XCTAssertTrue(ActionItemsSection.categoryCases.contains(.labels))
    }

    func testDashboardRouteTitle() {
        XCTAssertEqual(ActionItemsSidebarDestination.dashboard.navigationTitle, "Dashboard")
    }

    func testStickyBoardAndTodayRouteTitles() {
        XCTAssertEqual(ActionItemsSidebarDestination.stickyBoard.navigationTitle, "Sticky Board")
        XCTAssertEqual(ActionItemsSidebarDestination.today.navigationTitle, "Today")
    }
}
