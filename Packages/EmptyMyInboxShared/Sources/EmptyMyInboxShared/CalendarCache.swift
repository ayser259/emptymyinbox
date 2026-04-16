import CryptoKit
import Foundation

/// Persistent cache for Google Calendar lists and per-calendar event windows.
public actor CalendarCache {
    public static let shared = CalendarCache()

    private struct CachedCalendarList: Codable {
        let fetchedAt: Date
        let items: [GoogleCalendarListItem]
    }

    private struct CachedEventWindow: Codable {
        let fetchedAt: Date
        let timeMin: Date
        let timeMax: Date
        let events: [GoogleCalendarDisplayEvent]
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let baseDirectoryURL: URL
    private let calendarListsDirectoryURL: URL
    private let eventWindowsDirectoryURL: URL

    public init(baseDirectoryURL: URL? = nil) {
        let root = baseDirectoryURL
            ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory)

        self.baseDirectoryURL = root.appendingPathComponent("CalendarCache", isDirectory: true)
        self.calendarListsDirectoryURL = self.baseDirectoryURL.appendingPathComponent("calendar_lists", isDirectory: true)
        self.eventWindowsDirectoryURL = self.baseDirectoryURL.appendingPathComponent("event_windows", isDirectory: true)

        let fm = FileManager.default
        if !fm.fileExists(atPath: self.baseDirectoryURL.path) {
            try? fm.createDirectory(at: self.baseDirectoryURL, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: self.calendarListsDirectoryURL.path) {
            try? fm.createDirectory(at: self.calendarListsDirectoryURL, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: self.eventWindowsDirectoryURL.path) {
            try? fm.createDirectory(at: self.eventWindowsDirectoryURL, withIntermediateDirectories: true)
        }
    }

    public func loadCalendarList(accountEmail: String, maxAge: TimeInterval) async -> [GoogleCalendarListItem]? {
        let url = calendarListURL(for: accountEmail)
        guard let record: CachedCalendarList = readRecord(at: url) else { return nil }
        guard Date().timeIntervalSince(record.fetchedAt) <= maxAge else { return nil }
        return record.items
    }

    public func saveCalendarList(_ items: [GoogleCalendarListItem], accountEmail: String) async {
        let url = calendarListURL(for: accountEmail)
        let record = CachedCalendarList(fetchedAt: Date(), items: items)
        writeRecord(record, to: url, label: "calendar list")
    }

    public func loadEvents(
        accountEmail: String,
        calendarId: String,
        covering range: (Date, Date),
        maxAge: TimeInterval
    ) async -> [GoogleCalendarDisplayEvent]? {
        let url = eventWindowURL(accountEmail: accountEmail, calendarId: calendarId)
        guard let record: CachedEventWindow = readRecord(at: url) else { return nil }
        guard Date().timeIntervalSince(record.fetchedAt) <= maxAge else { return nil }
        guard record.timeMin <= range.0, record.timeMax >= range.1 else { return nil }
        return record.events
    }

    public func saveEvents(
        _ events: [GoogleCalendarDisplayEvent],
        accountEmail: String,
        calendarId: String,
        timeMin: Date,
        timeMax: Date
    ) async {
        let url = eventWindowURL(accountEmail: accountEmail, calendarId: calendarId)
        let existing: CachedEventWindow? = readRecord(at: url)
        let merged = mergeEventWindow(
            existing: existing,
            newEvents: events,
            timeMin: timeMin,
            timeMax: timeMax
        )
        writeRecord(merged, to: url, label: "event window")
    }

    public func clear(accountEmail: String) async {
        let fm = FileManager.default
        try? fm.removeItem(at: calendarListURL(for: accountEmail))
        let accountId = StableID.accountId(email: accountEmail)
        let prefix = "account_\(accountId)_"
        if let contents = try? fm.contentsOfDirectory(at: eventWindowsDirectoryURL, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.hasPrefix(prefix) {
                try? fm.removeItem(at: url)
            }
        }
    }

    public func clearAll() async {
        let fm = FileManager.default
        try? fm.removeItem(at: baseDirectoryURL)
        try? fm.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: calendarListsDirectoryURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: eventWindowsDirectoryURL, withIntermediateDirectories: true)
    }

    private func mergeEventWindow(
        existing: CachedEventWindow?,
        newEvents: [GoogleCalendarDisplayEvent],
        timeMin: Date,
        timeMax: Date
    ) -> CachedEventWindow {
        let mergedEvents = dedupeEvents((existing?.events ?? []) + newEvents)
        return CachedEventWindow(
            fetchedAt: Date(),
            timeMin: min(existing?.timeMin ?? timeMin, timeMin),
            timeMax: max(existing?.timeMax ?? timeMax, timeMax),
            events: mergedEvents
        )
    }

    private func dedupeEvents(_ events: [GoogleCalendarDisplayEvent]) -> [GoogleCalendarDisplayEvent] {
        var byCompositeId: [String: GoogleCalendarDisplayEvent] = [:]
        for event in events {
            byCompositeId[event.compositeId] = event
        }
        return byCompositeId.values.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.compositeId < rhs.compositeId
            }
            return lhs.start < rhs.start
        }
    }

    private func calendarListURL(for accountEmail: String) -> URL {
        let accountId = StableID.accountId(email: accountEmail)
        return calendarListsDirectoryURL.appendingPathComponent("account_\(accountId).json")
    }

    private func eventWindowURL(accountEmail: String, calendarId: String) -> URL {
        let accountId = StableID.accountId(email: accountEmail)
        let calendarHash = sha256Hex(calendarId)
        return eventWindowsDirectoryURL.appendingPathComponent("account_\(accountId)_\(calendarHash).json")
    }

    private func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func readRecord<T: Decodable>(at url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            logError("CalendarCache read error at \(url.lastPathComponent): \(error)", category: "Cache")
            return nil
        }
    }

    private func writeRecord<T: Encodable>(_ value: T, to url: URL, label: String) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            logError("CalendarCache write \(label) error: \(error)", category: "Cache")
        }
    }
}
