import Foundation

/// Greedy lane assignment for overlapping timed events on a single day (minimum lanes).
enum CalendarDayTimelineLayout {
    /// Clamps an event to `[dayStart, dayEnd)`; returns `nil` if there is no overlap.
    static func clippedRange(
        for event: GoogleCalendarDisplayEvent,
        dayStart: Date,
        dayEnd: Date
    ) -> (Date, Date)? {
        let s = max(event.start, dayStart)
        let e = min(event.end, dayEnd)
        guard s < e else { return nil }
        return (s, e)
    }

    /// Returns `(event, start, end, laneIndex, laneCount)` sorted by start time.
    static func assignLanes(
        events: [(GoogleCalendarDisplayEvent, Date, Date)]
    ) -> [(GoogleCalendarDisplayEvent, Date, Date, Int, Int)] {
        let sorted = events.sorted { $0.1 < $1.1 }
        var laneEnds: [Date] = []
        var out: [(GoogleCalendarDisplayEvent, Date, Date, Int)] = []
        for (ev, start, end) in sorted {
            if let idx = laneEnds.firstIndex(where: { $0 <= start }) {
                laneEnds[idx] = end
                out.append((ev, start, end, idx))
            } else {
                laneEnds.append(end)
                out.append((ev, start, end, laneEnds.count - 1))
            }
        }
        let laneCount = max(laneEnds.count, 1)
        return out.map { ($0.0, $0.1, $0.2, $0.3, laneCount) }
    }
}
