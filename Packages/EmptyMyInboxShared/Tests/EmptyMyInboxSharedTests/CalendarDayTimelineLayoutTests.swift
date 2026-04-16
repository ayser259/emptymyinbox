import XCTest
@testable import EmptyMyInboxShared

final class CalendarDayTimelineLayoutTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private let dayStart = Date(timeIntervalSince1970: 1_704_067_200) // 2023-12-27 00:00 UTC
    private var dayEnd: Date {
        cal.date(byAdding: .day, value: 1, to: dayStart)!
    }

    private func event(
        id: String,
        start: Date,
        end: Date
    ) -> GoogleCalendarDisplayEvent {
        GoogleCalendarDisplayEvent(
            eventId: id,
            calendarId: "cal",
            accountEmail: "u@test.com",
            title: id,
            start: start,
            end: end,
            isAllDay: false,
            calendarTitle: "Cal",
            colorHex: nil
        )
    }

    func testClippedRange_noOverlap_returnsNil() {
        let ev = event(
            id: "a",
            start: cal.date(byAdding: .day, value: -2, to: dayStart)!,
            end: cal.date(byAdding: .day, value: -1, to: dayStart)!
        )
        let r = CalendarDayTimelineLayout.clippedRange(for: ev, dayStart: dayStart, dayEnd: dayEnd)
        XCTAssertNil(r)
    }

    func testClippedRange_midnightSpan_clampsToDay() {
        let ev = event(
            id: "a",
            start: cal.date(byAdding: .hour, value: 22, to: cal.date(byAdding: .day, value: -1, to: dayStart)!)!,
            end: cal.date(byAdding: .hour, value: 2, to: dayStart)!
        )
        let r = CalendarDayTimelineLayout.clippedRange(for: ev, dayStart: dayStart, dayEnd: dayEnd)
        XCTAssertEqual(r?.0, dayStart)
        XCTAssertEqual(r?.1, cal.date(byAdding: .hour, value: 2, to: dayStart)!)
    }

    func testAssignLanes_nonOverlapping_singleLane() {
        let a = event(id: "a", start: dayStart, end: cal.date(byAdding: .hour, value: 1, to: dayStart)!)
        let b = event(id: "b", start: cal.date(byAdding: .hour, value: 2, to: dayStart)!, end: cal.date(byAdding: .hour, value: 3, to: dayStart)!)
        let placed = CalendarDayTimelineLayout.assignLanes(events: [(a, a.start, a.end), (b, b.start, b.end)])
        XCTAssertEqual(placed.count, 2)
        XCTAssertEqual(placed[0].3, 0)
        XCTAssertEqual(placed[1].3, 0)
        XCTAssertEqual(placed[0].4, 1)
    }

    func testAssignLanes_overlapping_twoLanes() {
        let a = event(id: "a", start: dayStart, end: cal.date(byAdding: .hour, value: 2, to: dayStart)!)
        let b = event(id: "b", start: cal.date(byAdding: .hour, value: 1, to: dayStart)!, end: cal.date(byAdding: .hour, value: 3, to: dayStart)!)
        let placed = CalendarDayTimelineLayout.assignLanes(events: [(a, a.start, a.end), (b, b.start, b.end)])
        XCTAssertEqual(placed.count, 2)
        let lanes = Set(placed.map(\.3))
        XCTAssertEqual(lanes.count, 2)
        XCTAssertEqual(placed[0].4, 2)
        XCTAssertEqual(placed[1].4, 2)
    }
}
