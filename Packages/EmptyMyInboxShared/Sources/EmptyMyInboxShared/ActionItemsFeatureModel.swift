//
//  ActionItemsFeatureModel.swift
//  EmptyMyInboxShared
//
//  Filtering, grouping, and sorting for vault-backed action items (shared by iOS and macOS).
//

import Foundation

/// Filtering, grouping, and sorting for vault-backed action items.
/// Call sites should pass **active** items from `VaultManager.listActionItems()` (completed items are in `ActionItems/completed_items.json`).
public enum ActionItemsFeatureModel {
    // MARK: - Subject / context

    /// Canonical bucket for items without a named context (sidebar grouping).
    public static let unspecifiedSubjectKey = "Unspecified"

    /// Display key for sidebar grouping; empty, legacy inbox/uncategorized → `unspecifiedSubjectKey`.
    public static func normalizedSubjectKey(_ label: String?) -> String {
        let t = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty { return unspecifiedSubjectKey }
        let lower = t.lowercased()
        if lower == "inbox" || lower == "uncategorized" { return unspecifiedSubjectKey }
        return t
    }

    /// Sorted `(subjectKey, items)` for context/channel UI.
    public static func groupedBySubject(_ items: [VaultActionItemRecord]) -> [(key: String, items: [VaultActionItemRecord])] {
        let dict = Dictionary(grouping: items) { normalizedSubjectKey($0.subjectLabel) }
        return dict.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { key in (key, defaultSorted(dict[key] ?? [])) }
    }

    // MARK: - Calendar day overlap (start/end model)

    /// Whether the item’s start/end window overlaps the given calendar day.
    public static func overlapsCalendarDay(
        _ item: VaultActionItemRecord,
        day: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let dayInterval = calendar.dateInterval(of: .day, for: day) else { return false }
        let dayStart = dayInterval.start
        let dayEnd = dayInterval.end

        let rangeStart = item.startDate ?? item.endDate
        let rangeEnd = item.endDate ?? item.startDate

        if rangeStart == nil && rangeEnd == nil {
            return false
        }

        if let s = item.startDate, let e = item.endDate {
            return s < dayEnd && e > dayStart
        }
        if let s = item.startDate {
            return s >= dayStart && s < dayEnd
        }
        if let e = item.endDate {
            return e >= dayStart && e < dayEnd
        }
        return false
    }

    /// Items scheduled for `referenceDay`, plus unscheduled items (no start and no end).
    public static func itemsForTodayList(
        _ items: [VaultActionItemRecord],
        referenceDay: Date = Date(),
        calendar: Calendar = .current
    ) -> (scheduled: [VaultActionItemRecord], unscheduled: [VaultActionItemRecord]) {
        var scheduled: [VaultActionItemRecord] = []
        var unscheduled: [VaultActionItemRecord] = []
        for item in items {
            if item.startDate == nil && item.endDate == nil {
                unscheduled.append(item)
            } else if overlapsCalendarDay(item, day: referenceDay, calendar: calendar) {
                scheduled.append(item)
            }
        }
        return (defaultSorted(scheduled), defaultSorted(unscheduled))
    }

    /// Items whose time window intersects `[rangeStart, rangeEnd)` (half-open on end), or single anchor date inside range.
    public static func itemsIntersectingRange(
        _ items: [VaultActionItemRecord],
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar = .current
    ) -> [VaultActionItemRecord] {
        let rs = min(rangeStart, rangeEnd)
        let re = max(rangeStart, rangeEnd)
        let filtered = items.filter { item in
            if item.startDate == nil && item.endDate == nil { return false }
            if let s = item.startDate, let e = item.endDate {
                return s < re && e > rs
            }
            if let s = item.startDate {
                return s >= rs && s < re
            }
            if let e = item.endDate {
                return e >= rs && e < re
            }
            return false
        }
        return defaultSortedForCalendar(filtered, calendar: calendar)
    }

    // MARK: - Sorting

    /// Primary list sort: incomplete first, higher priority, earlier start, then title.
    public static func defaultSorted(_ items: [VaultActionItemRecord]) -> [VaultActionItemRecord] {
        items.sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone && b.isDone }
            let pa = a.priority ?? -1
            let pb = b.priority ?? -1
            if pa != pb { return pa > pb }
            let sa = a.startDate ?? .distantFuture
            let sb = b.startDate ?? .distantFuture
            if sa != sb { return sa < sb }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    /// Calendar-style sort: by start, then end, then title.
    public static func defaultSortedForCalendar(_ items: [VaultActionItemRecord], calendar _: Calendar = .current) -> [VaultActionItemRecord] {
        items.sorted { a, b in
            let sa = a.startDate ?? a.endDate ?? .distantFuture
            let sb = b.startDate ?? b.endDate ?? .distantFuture
            if sa != sb { return sa < sb }
            let ea = a.endDate ?? .distantFuture
            let eb = b.endDate ?? .distantFuture
            if ea != eb { return ea < eb }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }
}
