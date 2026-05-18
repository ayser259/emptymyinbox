//
//  InboxMetricsStore.swift
//  EmptyMyInboxShared
//
//  Daily inbox metrics persisted under Application Support.
//

import Foundation

// MARK: - Models

public struct DailyInboxMetric: Codable, Identifiable, Sendable, Equatable {
    public var dayKey: String
    public var emailsReceived: Int
    public var uniqueSendersReceived: Int
    public var reviewSessions: Int
    public var reviewSeconds: Double
    public var emailsReviewed: Int
    public var markedAsRead: Int
    public var keptUnread: Int
    public var potentialUnsubscribeSenders: Int
    public var successfulUnsubscribes: Int

    public var id: String { dayKey }

    public init(
        dayKey: String,
        emailsReceived: Int = 0,
        uniqueSendersReceived: Int = 0,
        reviewSessions: Int = 0,
        reviewSeconds: Double = 0,
        emailsReviewed: Int = 0,
        markedAsRead: Int = 0,
        keptUnread: Int = 0,
        potentialUnsubscribeSenders: Int = 0,
        successfulUnsubscribes: Int = 0
    ) {
        self.dayKey = dayKey
        self.emailsReceived = emailsReceived
        self.uniqueSendersReceived = uniqueSendersReceived
        self.reviewSessions = reviewSessions
        self.reviewSeconds = reviewSeconds
        self.emailsReviewed = emailsReviewed
        self.markedAsRead = markedAsRead
        self.keptUnread = keptUnread
        self.potentialUnsubscribeSenders = potentialUnsubscribeSenders
        self.successfulUnsubscribes = successfulUnsubscribes
    }
}

private struct InboxMetricsFile: Codable {
    var version: Int = 1
    var days: [DailyInboxMetric]
}

public struct InboxMetricsDayPoint: Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let label: String
    public let emailsReceived: Int
    public let emailsReviewed: Int
    public let reviewMinutes: Double

    public init(day: DailyInboxMetric, calendar: Calendar = .current) {
        id = day.dayKey
        date = InboxMetricsStore.dayKeyToDate(day.dayKey, calendar: calendar) ?? Date()
        label = InboxMetricsStore.shortDayLabel(for: date, calendar: calendar)
        emailsReceived = day.emailsReceived
        emailsReviewed = day.emailsReviewed
        reviewMinutes = day.reviewSeconds / 60.0
    }
}

public struct InboxMetricsWeekdayBucket: Identifiable, Sendable {
    public let id: Int
    public let weekdaySymbol: String
    public let thisWeekValue: Double
    public let previousWeekValue: Double

    public var delta: Double { thisWeekValue - previousWeekValue }
}

public enum InboxMetricsChartMetric: String, CaseIterable, Identifiable, Sendable {
    case received = "Received"
    case reviewed = "Reviewed"
    case reviewTime = "Review time"

    public var id: String { rawValue }

    public var unitLabel: String {
        switch self {
        case .received, .reviewed: return "emails"
        case .reviewTime: return "min"
        }
    }
}

// MARK: - Store

public actor InboxMetricsStore {
    public static let shared = InboxMetricsStore()

    private static let retentionDays = 90
    private let fileName = "inbox_metrics.json"
    private var cached: [DailyInboxMetric] = []
    private var didLoad = false

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Calendar.current.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoParserNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Public API

    public func metric(forDayContaining date: Date, calendar: Calendar = .current) async -> DailyInboxMetric? {
        await ensureLoaded()
        let key = dayKey(for: date, calendar: calendar)
        return cached.first { $0.dayKey == key }
    }

    public func last14DayPoints(calendar: Calendar = .current) async -> [InboxMetricsDayPoint] {
        await ensureLoaded()
        let today = calendar.startOfDay(for: Date())
        var points: [InboxMetricsDayPoint] = []
        for offset in (0..<14).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = dayKey(for: day, calendar: calendar)
            let metric = cached.first { $0.dayKey == key } ?? DailyInboxMetric(dayKey: key)
            points.append(InboxMetricsDayPoint(day: metric, calendar: calendar))
        }
        return points
    }

    public func weekdayBuckets(
        metric: InboxMetricsChartMetric,
        calendar: Calendar = .current
    ) async -> [InboxMetricsWeekdayBucket] {
        await ensureLoaded()
        let today = calendar.startOfDay(for: Date())
        var thisWeek = Array(repeating: 0.0, count: 7)
        var previousWeek = Array(repeating: 0.0, count: 7)

        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = dayKey(for: day, calendar: calendar)
            let record = cached.first { $0.dayKey == key }
            let value = chartValue(from: record, metric: metric)
            let weekdayIndex = normalizedWeekdayIndex(for: day, calendar: calendar)
            if offset < 7 {
                thisWeek[weekdayIndex] += value
            } else {
                previousWeek[weekdayIndex] += value
            }
        }

        let symbols = orderedWeekdaySymbols(calendar: calendar)
        return (0..<7).map { idx in
            InboxMetricsWeekdayBucket(
                id: idx,
                weekdaySymbol: symbols[idx],
                thisWeekValue: thisWeek[idx],
                previousWeekValue: previousWeek[idx]
            )
        }
    }

    /// Rebuild received-email counts for days present in the snapshot (last 14 days window).
    public func updateReceivedCounts(from emails: [EmailListItem], calendar: Calendar = .current) async {
        await ensureLoaded()
        let today = calendar.startOfDay(for: Date())
        guard let windowStart = calendar.date(byAdding: .day, value: -13, to: today) else { return }

        var counts: [String: Int] = [:]
        var senders: [String: Set<String>] = [:]

        for email in emails {
            guard let received = parseReceivedAt(email.received_at) else { continue }
            let dayStart = calendar.startOfDay(for: received)
            guard dayStart >= windowStart, dayStart <= today else { continue }
            let key = dayKey(for: dayStart, calendar: calendar)
            counts[key, default: 0] += 1
            senders[key, default: []].insert(email.sender.lowercased())
        }

        for (key, count) in counts {
            var day = dayRecord(forKey: key)
            day.emailsReceived = count
            day.uniqueSendersReceived = senders[key]?.count ?? 0
            upsert(day)
        }

        pruneOldRecords(calendar: calendar)
        await persist()
        await postUpdate()
    }

    public func recordCatchUpSession(
        stats: CatchUpSessionStats,
        sessionStart: Date?,
        sessionEnd: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard stats.reviewed > 0 else { return }
        await ensureLoaded()

        let key = dayKey(for: sessionEnd, calendar: calendar)
        var day = dayRecord(forKey: key)

        let duration: Double
        if let start = sessionStart {
            duration = max(0, sessionEnd.timeIntervalSince(start))
        } else {
            duration = 0
        }

        day.reviewSessions += 1
        day.reviewSeconds += duration
        day.emailsReviewed += stats.reviewed
        day.markedAsRead += stats.markedAsRead
        day.keptUnread += stats.keptUnread
        day.potentialUnsubscribeSenders += stats.potentialUnsubscribeSenders.count
        day.successfulUnsubscribes += stats.successfulUnsubscribes

        upsert(day)
        pruneOldRecords(calendar: calendar)
        await persist()
        await postUpdate()
    }

    // MARK: - Helpers

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        dayKeyFormatter.calendar = calendar
        dayKeyFormatter.timeZone = calendar.timeZone
        return dayKeyFormatter.string(from: calendar.startOfDay(for: date))
    }

    public static func dayKeyToDate(_ key: String, calendar: Calendar = .current) -> Date? {
        dayKeyFormatter.calendar = calendar
        dayKeyFormatter.timeZone = calendar.timeZone
        return dayKeyFormatter.date(from: key)
    }

    public static func shortDayLabel(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEE d")
        return formatter.string(from: date)
    }

    private func chartValue(from record: DailyInboxMetric?, metric: InboxMetricsChartMetric) -> Double {
        guard let record else { return 0 }
        switch metric {
        case .received: return Double(record.emailsReceived)
        case .reviewed: return Double(record.emailsReviewed)
        case .reviewTime: return record.reviewSeconds / 60.0
        }
    }

    private func normalizedWeekdayIndex(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        let first = calendar.firstWeekday
        return (weekday - first + 7) % 7
    }

    private func orderedWeekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        guard start > 0, start < symbols.count else { return symbols }
        return Array(symbols[start...] + symbols[..<start])
    }

    private func dayKey(for date: Date, calendar: Calendar) -> String {
        Self.dayKey(for: date, calendar: calendar)
    }

    private func dayRecord(forKey key: String) -> DailyInboxMetric {
        cached.first { $0.dayKey == key } ?? DailyInboxMetric(dayKey: key)
    }

    private func upsert(_ day: DailyInboxMetric) {
        if let idx = cached.firstIndex(where: { $0.dayKey == day.dayKey }) {
            cached[idx] = day
        } else {
            cached.append(day)
        }
        cached.sort { $0.dayKey < $1.dayKey }
    }

    private func pruneOldRecords(calendar: Calendar) {
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: today) else { return }
        let cutoffKey = dayKey(for: cutoff, calendar: calendar)
        cached.removeAll { $0.dayKey < cutoffKey }
    }

    private func parseReceivedAt(_ string: String) -> Date? {
        if let d = Self.isoParser.date(from: string) { return d }
        if let d = Self.isoParserNoFrac.date(from: string) { return d }
        return nil
    }

    private func postUpdate() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .inboxMetricsDidUpdate, object: nil)
        }
    }

    // MARK: - Persistence

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true
        cached = await loadFromDisk()
    }

    private func loadFromDisk() async -> [DailyInboxMetric] {
        let fileURL = appSupportURL().appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let file = (try? JSONDecoder().decode(InboxMetricsFile.self, from: data))
        return file?.days ?? []
    }

    private func persist() async {
        let fileURL = appSupportURL().appendingPathComponent(fileName)
        let file = InboxMetricsFile(days: cached)
        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logError("Failed to persist inbox metrics: \(error)", category: "Metrics")
        }
    }

    private func appSupportURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("emptyMyInbox", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
