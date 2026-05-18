import XCTest
@testable import EmptyMyInboxShared

final class InboxMetricsStoreTests: XCTestCase {
    func testDayKeyRoundTrip() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 18
        let date = calendar.date(from: components)!
        let key = InboxMetricsStore.dayKey(for: date, calendar: calendar)
        XCTAssertEqual(key, "2026-05-18")
        let parsed = InboxMetricsStore.dayKeyToDate(key, calendar: calendar)
        XCTAssertEqual(calendar.startOfDay(for: parsed!), calendar.startOfDay(for: date))
    }

    func testLast14DayPointsReturns14Entries() async {
        let points = await InboxMetricsStore.shared.last14DayPoints()
        XCTAssertEqual(points.count, 14)
    }

    func testWeekdayBucketsReturnsSevenEntries() async {
        let buckets = await InboxMetricsStore.shared.weekdayBuckets(metric: .received)
        XCTAssertEqual(buckets.count, 7)
    }
}
