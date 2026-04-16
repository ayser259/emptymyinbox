import XCTest
@testable import EmptyMyInboxShared

final class GoogleCalendarDerivedMetricsTests: XCTestCase {
    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testWeekStartDays_returnsSevenDays() {
        let anchor = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 00:00 UTC
        let days = GoogleCalendarDerivedMetrics.weekStartDays(containing: anchor, calendar: utc)
        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days.allSatisfy { utc.component(.hour, from: $0) == 0 && utc.component(.minute, from: $0) == 0 })
    }

    func testEventsByDay_sortsAndBuckets() {
        let cal = utc
        let day0 = Date(timeIntervalSince1970: 1_704_067_200)
        let day1 = cal.date(byAdding: .day, value: 1, to: day0)!
        let day2 = cal.date(byAdding: .day, value: 2, to: day0)!
        let days = [day0, day1, day2].map { cal.startOfDay(for: $0) }

        let eEarly = GoogleCalendarDisplayEvent(
            eventId: "a",
            calendarId: "c",
            accountEmail: "u@test.com",
            title: "Early",
            start: cal.date(byAdding: .hour, value: 9, to: day0)!,
            end: cal.date(byAdding: .hour, value: 10, to: day0)!,
            isAllDay: false,
            calendarTitle: "Cal",
            colorHex: nil
        )
        let eLate = GoogleCalendarDisplayEvent(
            eventId: "b",
            calendarId: "c",
            accountEmail: "u@test.com",
            title: "Late",
            start: cal.date(byAdding: .hour, value: 14, to: day0)!,
            end: cal.date(byAdding: .hour, value: 15, to: day0)!,
            isAllDay: false,
            calendarTitle: "Cal",
            colorHex: nil
        )
        let eNext = GoogleCalendarDisplayEvent(
            eventId: "c",
            calendarId: "c",
            accountEmail: "u@test.com",
            title: "Next day",
            start: cal.date(byAdding: .hour, value: 10, to: day1)!,
            end: cal.date(byAdding: .hour, value: 11, to: day1)!,
            isAllDay: false,
            calendarTitle: "Cal",
            colorHex: nil
        )

        let buckets = GoogleCalendarDerivedMetrics.eventsByDay(days: days, events: [eLate, eEarly, eNext], calendar: cal)
        XCTAssertEqual(buckets[days[0]]?.map(\.title), ["Early", "Late"])
        XCTAssertEqual(buckets[days[1]]?.map(\.title), ["Next day"])
        XCTAssertEqual(buckets[days[2]]?.count ?? 0, 0)
    }

    func testMonthDayEventCounts_overlappingDays() {
        let cal = utc
        let monthStart = Date(timeIntervalSince1970: 1_704_067_200)
        let day3Start = cal.startOfDay(for: cal.date(byAdding: .day, value: 2, to: monthStart)!)
        let day6Start = cal.startOfDay(for: cal.date(byAdding: .day, value: 5, to: monthStart)!)

        let multiDay = GoogleCalendarDisplayEvent(
            eventId: "m",
            calendarId: "c",
            accountEmail: "u@test.com",
            title: "Span",
            start: day3Start,
            end: day6Start,
            isAllDay: false,
            calendarTitle: "Cal",
            colorHex: nil
        )

        let counts = GoogleCalendarDerivedMetrics.monthDayEventCounts(monthContaining: monthStart, events: [multiDay], calendar: cal)
        XCTAssertEqual(counts[3], 1)
        XCTAssertEqual(counts[4], 1)
        XCTAssertEqual(counts[5], 1)
    }
}
