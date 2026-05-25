import XCTest
@testable import EmptyMyInboxShared

final class DashboardRefreshPolicyTests: XCTestCase {
    private func makeSnapshot(timestamp: Date) -> DashboardDataSnapshot {
        DashboardDataSnapshot(
            timestamp: timestamp,
            accounts: [],
            emails: [],
            allEmails: [],
            starredEmails: [],
            sentEmails: [],
            labels: []
        )
    }

    func testShouldAutoSyncWhenSnapshotNil() {
        XCTAssertTrue(DashboardRefreshPolicy.shouldAutoSync(snapshot: nil, now: Date()))
    }

    func testShouldNotAutoSyncWhenSnapshotFresh() {
        let now = Date()
        let snapshot = makeSnapshot(timestamp: now.addingTimeInterval(-60))
        XCTAssertFalse(DashboardRefreshPolicy.shouldAutoSync(snapshot: snapshot, now: now))
    }

    func testShouldAutoSyncWhenSnapshotStale() {
        let now = Date()
        let interval = DashboardRefreshPolicy.mailAutoRefreshInterval
        let snapshot = makeSnapshot(timestamp: now.addingTimeInterval(-interval - 1))
        XCTAssertTrue(DashboardRefreshPolicy.shouldAutoSync(snapshot: snapshot, now: now))
    }

    func testShouldAutoSyncAtFreshnessBoundary() {
        let now = Date()
        let interval = DashboardRefreshPolicy.mailAutoRefreshInterval
        let snapshot = makeSnapshot(timestamp: now.addingTimeInterval(-interval))
        XCTAssertTrue(DashboardRefreshPolicy.shouldAutoSync(snapshot: snapshot, now: now))
    }
}
