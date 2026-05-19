//
//  EmailListItemDisplay.swift
//  EmptyMyInboxShared
//
//  Shared formatting helpers for mailbox list rows.
//

import Foundation

public enum EmailListItemDisplay {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func senderDisplayName(for email: EmailListItem) -> String {
        if let name = email.sender_name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return email.sender
    }

    public static func subjectDisplay(for email: EmailListItem) -> String {
        email.subject.isEmpty ? "(No Subject)" : email.subject
    }

    public static func parseReceivedAt(_ dateString: String) -> Date? {
        isoFormatter.date(from: dateString)
            ?? isoFormatterNoFraction.date(from: dateString)
            ?? legacyDateFormatter.date(from: dateString)
    }

    /// Compact relative date for list rows (Today → time, Yesterday, weekday, or MMM d).
    public static func relativeListDate(from dateString: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date = parseReceivedAt(dateString) else { return "" }

        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return timeFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) == true {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"
            return dayFormatter.string(from: date)
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        return dateFormatter.string(from: date)
    }

    /// Abbreviated date for macOS list density.
    public static func abbreviatedListDate(from dateString: String) -> String {
        guard let date = parseReceivedAt(dateString) else { return "" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private static let legacyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
