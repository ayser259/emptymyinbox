//
//  InboxMetricsStore.swift
//  EmptyMyInboxShared
//
//  Daily inbox metrics persisted under Application Support.
//  Version 2 indexes received emails by Gmail message id; refresh reconciles observed inbox.
//

import Foundation

// MARK: - Models

/// One observed inbox message contributing to a day's received metrics (keyed by `gmailId`).
public struct IndexedReceivedEmail: Codable, Sendable, Equatable, Hashable {
    public let gmailId: String
    public let localEmailId: Int
    public let accountEmail: String
    public let senderKey: String
    public let receivedAt: String

    public init(
        gmailId: String,
        localEmailId: Int,
        accountEmail: String,
        senderKey: String,
        receivedAt: String
    ) {
        self.gmailId = gmailId
        self.localEmailId = localEmailId
        self.accountEmail = accountEmail
        self.senderKey = senderKey
        self.receivedAt = receivedAt
    }

    public init(from email: EmailListItem) {
        self.init(
            gmailId: email.gmail_id,
            localEmailId: email.id,
            accountEmail: email.account_email,
            senderKey: email.sender.lowercased(),
            receivedAt: email.received_at
        )
    }
}

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
    /// Indexed observed messages for this day (v2). Empty for legacy aggregate-only days until next refresh.
    public var receivedEmails: [IndexedReceivedEmail]

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
        successfulUnsubscribes: Int = 0,
        receivedEmails: [IndexedReceivedEmail] = []
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
        self.receivedEmails = receivedEmails
    }

    enum CodingKeys: String, CodingKey {
        case dayKey, emailsReceived, uniqueSendersReceived
        case reviewSessions, reviewSeconds, emailsReviewed
        case markedAsRead, keptUnread
        case potentialUnsubscribeSenders, successfulUnsubscribes
        case receivedEmails
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        emailsReceived = try c.decode(Int.self, forKey: .emailsReceived)
        uniqueSendersReceived = try c.decode(Int.self, forKey: .uniqueSendersReceived)
        reviewSessions = try c.decode(Int.self, forKey: .reviewSessions)
        reviewSeconds = try c.decode(Double.self, forKey: .reviewSeconds)
        emailsReviewed = try c.decode(Int.self, forKey: .emailsReviewed)
        markedAsRead = try c.decode(Int.self, forKey: .markedAsRead)
        keptUnread = try c.decode(Int.self, forKey: .keptUnread)
        potentialUnsubscribeSenders = try c.decode(Int.self, forKey: .potentialUnsubscribeSenders)
        successfulUnsubscribes = try c.decode(Int.self, forKey: .successfulUnsubscribes)
        receivedEmails = try c.decodeIfPresent([IndexedReceivedEmail].self, forKey: .receivedEmails) ?? []
    }
}

private struct InboxMetricsFileV1: Codable {
    var version: Int = 1
    var days: [DailyInboxMetric]
}

private struct InboxMetricsFile: Codable {
    static let currentVersion = 2

    var version: Int
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

    /// Days reconciled from each mailbox refresh (covers trailing + weekday charts).
    public static let reconciliationWindowDays = 14

    private static let retentionDays = 90
    private let fileName: String
    private let persistenceDirectory: URL
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

    public init(
        fileName: String = "inbox_metrics.json",
        persistenceDirectory: URL? = nil
    ) {
        self.fileName = fileName
        if let persistenceDirectory {
            self.persistenceDirectory = persistenceDirectory
        } else {
            let fm = FileManager.default
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.persistenceDirectory = base.appendingPathComponent("emptyMyInbox", isDirectory: true)
        }
    }

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
        for offset in (0..<Self.reconciliationWindowDays).reversed() {
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

        for offset in 0..<Self.reconciliationWindowDays {
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

    /// Idempotently reconcile observed inbox messages into the local index for the chart window.
    public func reconcileReceivedEmails(from emails: [EmailListItem], calendar: Calendar = .current) async {
        await ensureLoaded()
        let today = calendar.startOfDay(for: Date())
        guard let windowStart = calendar.date(
            byAdding: .day,
            value: -(Self.reconciliationWindowDays - 1),
            to: today
        ) else { return }

        var indexedByDay: [String: [IndexedReceivedEmail]] = [:]

        for email in emails {
            guard !email.gmail_id.isEmpty else { continue }
            guard let received = parseReceivedAt(email.received_at) else { continue }
            let dayStart = calendar.startOfDay(for: received)
            guard dayStart >= windowStart, dayStart <= today else { continue }
            let key = dayKey(for: dayStart, calendar: calendar)
            indexedByDay[key, default: []].append(IndexedReceivedEmail(from: email))
        }

        for offset in 0..<Self.reconciliationWindowDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = dayKey(for: day, calendar: calendar)
            let deduped = Self.dedupeReceivedEmails(indexedByDay[key] ?? [])
            var dayRecord = dayRecord(forKey: key)
            Self.applyReceivedIndex(&dayRecord, emails: deduped)
            upsert(dayRecord)
        }

        pruneOldRecords(calendar: calendar)
        await persist()
        await postUpdate()
    }

    /// Backward-compatible entry point used by dashboard refresh.
    public func updateReceivedCounts(from emails: [EmailListItem], calendar: Calendar = .current) async {
        await reconcileReceivedEmails(from: emails, calendar: calendar)
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

    // MARK: - Pure helpers (testable)

    public static func dedupeReceivedEmails(_ emails: [IndexedReceivedEmail]) -> [IndexedReceivedEmail] {
        var byGmailId: [String: IndexedReceivedEmail] = [:]
        for email in emails {
            byGmailId[email.gmailId] = email
        }
        return byGmailId.values.sorted { $0.receivedAt > $1.receivedAt }
    }

    public static func aggregates(from receivedEmails: [IndexedReceivedEmail]) -> (received: Int, uniqueSenders: Int) {
        let deduped = dedupeReceivedEmails(receivedEmails)
        let senders = Set(deduped.map(\.senderKey))
        return (deduped.count, senders.count)
    }

    public static func applyReceivedIndex(_ day: inout DailyInboxMetric, emails: [IndexedReceivedEmail]) {
        let deduped = dedupeReceivedEmails(emails)
        day.receivedEmails = deduped
        let agg = aggregates(from: deduped)
        day.emailsReceived = agg.received
        day.uniqueSendersReceived = agg.uniqueSenders
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
        let fileURL = metricsFileURL()
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        if let v2 = try? JSONDecoder().decode(InboxMetricsFile.self, from: data),
           v2.version >= InboxMetricsFile.currentVersion {
            return v2.days
        }

        if let v1 = try? JSONDecoder().decode(InboxMetricsFileV1.self, from: data) {
            logInfo("InboxMetricsStore: migrated v1 aggregate metrics (\(v1.days.count) days)", category: "Metrics")
            return v1.days
        }

        logWarning("InboxMetricsStore: failed to decode metrics file", category: "Metrics")
        return []
    }

    private func persist() async {
        let fileURL = metricsFileURL()
        let fm = FileManager.default
        if !fm.fileExists(atPath: persistenceDirectory.path) {
            try? fm.createDirectory(at: persistenceDirectory, withIntermediateDirectories: true)
        }
        let file = InboxMetricsFile(version: InboxMetricsFile.currentVersion, days: cached)
        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logError("Failed to persist inbox metrics: \(error)", category: "Metrics")
        }
    }

    private func metricsFileURL() -> URL {
        persistenceDirectory.appendingPathComponent(fileName)
    }

    private func appSupportURL() -> URL {
        persistenceDirectory
    }
}

#if DEBUG
extension InboxMetricsStore {
    /// Clears in-memory state and deletes the metrics file (unit tests only).
    public func resetForTesting() async {
        didLoad = true
        cached = []
        let url = metricsFileURL()
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
