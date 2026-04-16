import Foundation
import XCTest
@testable import EmptyMyInboxShared

final class CalendarCacheTests: XCTestCase {
    private func makeCache() -> (CalendarCache, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (CalendarCache(baseDirectoryURL: url), url)
    }

    private func event(
        eventId: String,
        calendarId: String = "primary",
        start: Date,
        end: Date
    ) -> GoogleCalendarDisplayEvent {
        GoogleCalendarDisplayEvent(
            eventId: eventId,
            calendarId: calendarId,
            accountEmail: "user@example.com",
            title: eventId,
            start: start,
            end: end,
            isAllDay: false,
            calendarTitle: "Primary",
            colorHex: "#3366ff"
        )
    }

    func testCalendarList_roundTrips() async {
        let (cache, directory) = makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        let list = [
            GoogleCalendarListItem(id: "primary", summary: "Primary", backgroundColor: "#3366ff", isPrimary: true)
        ]

        await cache.saveCalendarList(list, accountEmail: "user@example.com")
        let loaded = await cache.loadCalendarList(accountEmail: "user@example.com", maxAge: 60)

        XCTAssertEqual(loaded, list)
    }

    func testEventWindows_mergeAndCoverCombinedRange() async {
        let (cache, directory) = makeCache()
        defer { try? FileManager.default.removeItem(at: directory) }

        let start = Date(timeIntervalSince1970: 1_704_067_200)
        let middle = start.addingTimeInterval(86_400)
        let end = middle.addingTimeInterval(86_400)

        let first = event(eventId: "a", start: start.addingTimeInterval(3_600), end: start.addingTimeInterval(7_200))
        let second = event(eventId: "b", start: middle.addingTimeInterval(3_600), end: middle.addingTimeInterval(7_200))

        await cache.saveEvents([first], accountEmail: "user@example.com", calendarId: "primary", timeMin: start, timeMax: middle)
        await cache.saveEvents([second], accountEmail: "user@example.com", calendarId: "primary", timeMin: middle, timeMax: end)

        let loaded = await cache.loadEvents(
            accountEmail: "user@example.com",
            calendarId: "primary",
            covering: (start, end),
            maxAge: 60
        )

        XCTAssertEqual(loaded?.map(\.eventId), ["a", "b"])
    }
}
