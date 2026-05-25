import XCTest
@testable import EmptyMyInboxShared

final class InboxMetricsStoreTests: XCTestCase {
    private var testDirectory: URL!
    private var store: InboxMetricsStore!

    override func setUp() async throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InboxMetricsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        store = InboxMetricsStore(fileName: "metrics_test.json", persistenceDirectory: testDirectory)
        await store.resetForTesting()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testDirectory)
    }

    func testDayKeyRoundTrip() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 18
        let date = calendar.date(from: components)!
        let key = InboxMetricsStore.dayKey(for: date, calendar: calendar)
        XCTAssertEqual(key, "2026-05-18")
        let parsed = InboxMetricsStore.dayKeyToDate(key, calendar: calendar)
        XCTAssertEqual(calendar.startOfDay(for: parsed!), calendar.startOfDay(for: date))
    }

    func testStableEmailIdMatchesGmailId() {
        let gmailId = "abc123thread"
        let item = makeEmail(gmailId: gmailId, receivedAt: isoToday())
        XCTAssertEqual(item.id, StableID.emailId(gmailId: gmailId))
    }

    func testDedupeByGmailId() {
        let a = IndexedReceivedEmail(
            gmailId: "g1",
            localEmailId: 1,
            accountEmail: "a@test.com",
            senderKey: "sender@test.com",
            receivedAt: isoToday()
        )
        let b = IndexedReceivedEmail(
            gmailId: "g1",
            localEmailId: 999,
            accountEmail: "b@test.com",
            senderKey: "other@test.com",
            receivedAt: isoToday()
        )
        let deduped = InboxMetricsStore.dedupeReceivedEmails([a, b])
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.gmailId, "g1")
    }

    func testReconcileIsIdempotent() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let key = InboxMetricsStore.dayKey(for: today, calendar: calendar)

        let emails = [
            makeEmail(gmailId: "msg-a", sender: "alice@test.com", receivedAt: isoToday()),
            makeEmail(gmailId: "msg-b", sender: "bob@test.com", receivedAt: isoToday())
        ]

        await store.reconcileReceivedEmails(from: emails, calendar: calendar)
        await store.reconcileReceivedEmails(from: emails, calendar: calendar)

        let metric = await store.metric(forDayContaining: today, calendar: calendar)
        XCTAssertEqual(metric?.emailsReceived, 2)
        XCTAssertEqual(metric?.uniqueSendersReceived, 2)
        XCTAssertEqual(metric?.receivedEmails.count, 2)
        XCTAssertEqual(Set(metric?.receivedEmails.map(\.gmailId) ?? []), ["msg-a", "msg-b"])
        XCTAssertEqual(metric?.dayKey, key)
    }

    func testMultiAccountSameDay() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let emails = [
            makeEmail(gmailId: "g1", account: "one@test.com", sender: "s1@test.com", receivedAt: isoToday()),
            makeEmail(gmailId: "g2", account: "two@test.com", sender: "s2@test.com", receivedAt: isoToday())
        ]
        await store.reconcileReceivedEmails(from: emails, calendar: calendar)
        let metric = await store.metric(forDayContaining: today, calendar: calendar)
        XCTAssertEqual(metric?.emailsReceived, 2)
        XCTAssertEqual(Set(metric?.receivedEmails.map(\.accountEmail) ?? []), ["one@test.com", "two@test.com"])
    }

    func testReconcilePreservesCatchUpFields() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let stats = CatchUpSessionStats(
            reviewed: 3,
            markedAsRead: 2,
            keptUnread: 1,
            reviewedSenders: [],
            potentialUnsubscribeSenders: [],
            successfulUnsubscribes: 0
        )
        await store.recordCatchUpSession(stats: stats, sessionStart: Date().addingTimeInterval(-120), sessionEnd: Date(), calendar: calendar)

        await store.reconcileReceivedEmails(from: [makeEmail(gmailId: "inbox-1", receivedAt: isoToday())], calendar: calendar)

        let metric = await store.metric(forDayContaining: today, calendar: calendar)
        XCTAssertEqual(metric?.emailsReceived, 1)
        XCTAssertEqual(metric?.emailsReviewed, 3)
        XCTAssertEqual(metric?.markedAsRead, 2)
        XCTAssertEqual(metric?.reviewSessions, 1)
        XCTAssertGreaterThan(metric?.reviewSeconds ?? 0, 0)
    }

    func testChartQueriesReadIndexedAggregates() async throws {
        let calendar = Calendar(identifier: .gregorian)
        await store.reconcileReceivedEmails(
            from: [makeEmail(gmailId: "chart-1", receivedAt: isoToday())],
            calendar: calendar
        )
        let points = await store.last14DayPoints(calendar: calendar)
        XCTAssertEqual(points.count, 14)
        let todayKey = InboxMetricsStore.dayKey(for: Date(), calendar: calendar)
        let todayPoint = points.first { $0.id == todayKey }
        XCTAssertEqual(todayPoint?.emailsReceived, 1)

        let buckets = await store.weekdayBuckets(metric: .received, calendar: calendar)
        XCTAssertEqual(buckets.count, 7)
        let totalThisWeek = buckets.reduce(0.0) { $0 + $1.thisWeekValue }
        XCTAssertGreaterThanOrEqual(totalThisWeek, 1)
    }

    func testMigrationPreservesV1AggregatesWithoutInventingIds() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let key = InboxMetricsStore.dayKey(for: Date(), calendar: calendar)
        let v1JSON = """
        {"version":1,"days":[{"dayKey":"\(key)","emailsReceived":7,"uniqueSendersReceived":3,"reviewSessions":0,"reviewSeconds":0,"emailsReviewed":0,"markedAsRead":0,"keptUnread":0,"potentialUnsubscribeSenders":0,"successfulUnsubscribes":0}]}
        """
        let fileURL = testDirectory.appendingPathComponent("metrics_test.json")
        try v1JSON.data(using: .utf8)!.write(to: fileURL)

        let reloaded = InboxMetricsStore(fileName: "metrics_test.json", persistenceDirectory: testDirectory)
        let metric = await reloaded.metric(forDayContaining: Date(), calendar: calendar)
        XCTAssertEqual(metric?.emailsReceived, 7)
        XCTAssertEqual(metric?.uniqueSendersReceived, 3)
        XCTAssertTrue(metric?.receivedEmails.isEmpty ?? false)

        await reloaded.reconcileReceivedEmails(
            from: [makeEmail(gmailId: "new-msg", receivedAt: isoToday())],
            calendar: calendar
        )
        let after = await reloaded.metric(forDayContaining: Date(), calendar: calendar)
        XCTAssertEqual(after?.emailsReceived, 1)
        XCTAssertEqual(after?.receivedEmails.count, 1)
        XCTAssertEqual(after?.receivedEmails.first?.gmailId, "new-msg")
    }

    func testEmptyDayInWindowZeroesReceivedIndex() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        await store.reconcileReceivedEmails(from: [makeEmail(gmailId: "only-today", receivedAt: isoToday())], calendar: calendar)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            XCTFail("Could not build yesterday")
            return
        }
        let yesterdayMetric = await store.metric(forDayContaining: yesterday, calendar: calendar)
        XCTAssertEqual(yesterdayMetric?.emailsReceived, 0)
        XCTAssertTrue(yesterdayMetric?.receivedEmails.isEmpty ?? false)
    }

    // MARK: - Helpers

    private func isoToday() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func makeEmail(
        gmailId: String,
        account: String = "user@test.com",
        sender: String = "sender@test.com",
        receivedAt: String
    ) -> EmailListItem {
        EmailListItem(
            id: StableID.emailId(gmailId: gmailId),
            gmail_id: gmailId,
            subject: "Subject",
            sender: sender,
            sender_name: "Sender",
            snippet: "Snippet",
            is_read: false,
            is_starred: false,
            labels: ["INBOX", "UNREAD"],
            received_at: receivedAt,
            account_email: account,
            marked_read_at: nil
        )
    }
}
