import Foundation

/// Pure helpers for calendar week/month UI; covered by unit tests.
enum GoogleCalendarDerivedMetrics {
    /// Seven start-of-day keys Monday–Sunday (or calendar-first-weekday order) for the week containing `selectedDate`.
    static func weekStartDays(containing selectedDate: Date, calendar: Calendar = .current) -> [Date] {
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) else {
            return []
        }
        let ws = calendar.startOfDay(for: weekStart)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: ws) }.map { calendar.startOfDay(for: $0) }
    }

    /// Events overlapping each day in `days` (start-of-day keys), sorted by start within each bucket.
    static func eventsByDay(
        days: [Date],
        events: [GoogleCalendarDisplayEvent],
        calendar: Calendar = .current
    ) -> [Date: [GoogleCalendarDisplayEvent]] {
        var result: [Date: [GoogleCalendarDisplayEvent]] = [:]
        for d in days {
            let start = calendar.startOfDay(for: d)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let list = events.filter { $0.start < end && $0.end > start }.sorted { $0.start < $1.start }
            result[start] = list
        }
        return result
    }

    /// 1-based day number within month -> count of events overlapping that day.
    static func monthDayEventCounts(
        monthContaining selectedDate: Date,
        events: [GoogleCalendarDisplayEvent],
        calendar: Calendar = .current
    ) -> [Int: Int] {
        let comps = calendar.dateComponents([.year, .month], from: selectedDate)
        guard let monthStart = calendar.date(from: comps) else { return [:] }
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<29
        var counts: [Int: Int] = [:]
        for dayNum in range {
            guard let dayDate = calendar.date(byAdding: .day, value: dayNum - 1, to: monthStart) else { continue }
            let start = calendar.startOfDay(for: dayDate)
            guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let n = events.filter { $0.start < next && $0.end > start }.count
            if n > 0 {
                counts[dayNum] = n
            }
        }
        return counts
    }
}
