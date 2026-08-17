import XCTest
@testable import ProjectJadeShared

final class CatchUpLoadSupportTests: XCTestCase {
    private func makeUnreadItem(
        id: Int,
        gmailId: String,
        accountEmail: String = "user@example.com",
        isStarred: Bool = false,
        receivedAt: String = "2026-05-20T12:00:00.000Z"
    ) -> EmailListItem {
        EmailListItem(
            id: id,
            gmail_id: gmailId,
            thread_id: "thread-\(gmailId)",
            subject: "Subject \(id)",
            sender: "sender@example.com",
            sender_name: "Sender",
            snippet: "Snippet",
            is_read: false,
            is_starred: isStarred,
            labels: isStarred ? ["INBOX", "UNREAD", "STARRED"] : ["INBOX", "UNREAD"],
            received_at: receivedAt,
            account_email: accountEmail,
            marked_read_at: nil
        )
    }

    private func makeSnapshot(emails: [EmailListItem]) -> DashboardDataSnapshot {
        DashboardDataSnapshot(
            timestamp: Date(),
            accounts: [],
            emails: emails,
            allEmails: emails,
            starredEmails: emails.filter(\.is_starred),
            sentEmails: [],
            labels: []
        )
    }

    func testSeedMetadata_returnsCatchUpEligibleUnreadOnly() {
        let emails = [
            makeUnreadItem(id: 1, gmailId: "m1"),
            makeUnreadItem(id: 2, gmailId: "m2", isStarred: true),
            EmailListItem(
                id: 3,
                gmail_id: "m3",
                thread_id: "t3",
                subject: "Read",
                sender: "sender@example.com",
                sender_name: nil,
                snippet: "",
                is_read: true,
                is_starred: false,
                labels: ["INBOX"],
                received_at: "2026-05-20T11:00:00.000Z",
                account_email: "user@example.com",
                marked_read_at: nil
            ),
        ]

        let seeded = CatchUpLoadSupport.seedMetadata(
            from: makeSnapshot(emails: emails),
            accountEmail: nil,
            allowedAccountEmails: ["user@example.com"]
        )

        XCTAssertEqual(seeded.count, 1)
        XCTAssertEqual(seeded[0].gmail_id, "m1")
    }

    func testSeedMetadata_filtersByAccountEmail() {
        let emails = [
            makeUnreadItem(id: 1, gmailId: "m1", accountEmail: "a@example.com"),
            makeUnreadItem(id: 2, gmailId: "m2", accountEmail: "b@example.com"),
        ]

        let seeded = CatchUpLoadSupport.seedMetadata(
            from: makeSnapshot(emails: emails),
            accountEmail: "a@example.com",
            allowedAccountEmails: ["a@example.com", "b@example.com"]
        )

        XCTAssertEqual(seeded.count, 1)
        XCTAssertEqual(seeded[0].account_email, "a@example.com")
    }

    func testMergeUniqueMetadata_doesNotDuplicateGmailIds() {
        let existing = [
            EmailMetadata(
                id: 1, gmail_id: "m1", thread_id: "t1", subject: "A", sender: "a@x.com",
                sender_name: nil, snippet: "", is_read: false, is_starred: false,
                labels: ["INBOX", "UNREAD"], received_at: "2026-05-20T12:00:00.000Z", account_email: "u@x.com"
            )
        ]
        let adding = [
            EmailMetadata(
                id: 1, gmail_id: "m1", thread_id: "t1", subject: "A", sender: "a@x.com",
                sender_name: nil, snippet: "", is_read: false, is_starred: false,
                labels: ["INBOX", "UNREAD"], received_at: "2026-05-20T12:00:00.000Z", account_email: "u@x.com"
            ),
            EmailMetadata(
                id: 2, gmail_id: "m2", thread_id: "t2", subject: "B", sender: "b@x.com",
                sender_name: nil, snippet: "", is_read: false, is_starred: false,
                labels: ["INBOX", "UNREAD"], received_at: "2026-05-20T11:00:00.000Z", account_email: "u@x.com"
            ),
        ]

        let merged = CatchUpLoadSupport.mergeUniqueMetadata(existing: existing, adding: adding)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.map(\.gmail_id)), Set(["m1", "m2"]))
    }

    func testMessageRefsNeedingMetadata_skipsAlreadySeededIds() {
        let account = GmailAccount(
            id: "user@example.com",
            email: "user@example.com",
            name: nil,
            accessToken: "token",
            refreshToken: "refresh",
            tokenExpiry: Date().addingTimeInterval(3600),
            lastSync: nil,
            unreadEmailsNextPageToken: nil
        )
        let refs = [
            (account: account, id: "m1", threadId: "t1"),
            (account: account, id: "m2", threadId: "t2"),
        ]
        let existing = [
            EmailMetadata(
                id: 1, gmail_id: "m1", thread_id: "t1", subject: "A", sender: "a@x.com",
                sender_name: nil, snippet: "", is_read: false, is_starred: false,
                labels: ["INBOX", "UNREAD"], received_at: "2026-05-20T12:00:00.000Z", account_email: account.email
            )
        ]

        let needing = CatchUpLoadSupport.messageRefsNeedingMetadata(refs: refs, existingMetadata: existing)
        XCTAssertEqual(needing.map(\.id), ["m2"])
    }

    func testAccumulateMessageRefs_paginatesUntilCap() {
        let page1 = (0..<500).map { GmailMessageReference(id: "m\($0)", threadId: "t\($0)") }
        let page2 = (500..<700).map { GmailMessageReference(id: "m\($0)", threadId: "t\($0)") }

        let accumulated = CatchUpLoadSupport.accumulateMessageRefs(
            pages: [page1, page2],
            maxTotal: 600
        )

        XCTAssertEqual(accumulated.count, 600)
        XCTAssertEqual(accumulated.first?.id, "m0")
        XCTAssertEqual(accumulated.last?.id, "m599")
    }

    func testMetadataBatchRetryDelay_increasesExponentially() {
        XCTAssertEqual(CatchUpLoadSupport.metadataBatchRetryDelayNanoseconds(attempt: 0), 0)
        XCTAssertEqual(CatchUpLoadSupport.metadataBatchRetryDelayNanoseconds(attempt: 1), 500_000_000)
        XCTAssertEqual(CatchUpLoadSupport.metadataBatchRetryDelayNanoseconds(attempt: 2), 1_000_000_000)
    }

    func testDisplayUnreadCount_prefersGmailWhileLocalSyncIsPartial() {
        XCTAssertEqual(CatchUpLoadSupport.displayUnreadCount(localNonStarred: 50, gmailInboxUnread: 612), 612)
        XCTAssertEqual(CatchUpLoadSupport.displayUnreadCount(localNonStarred: 612, gmailInboxUnread: 612), 612)
    }

    func testMergeUnreadIntoAllEmails_doesNotDuplicateSharedIds() {
        let shared = EmailListItem(
            id: 1,
            gmail_id: "shared",
            thread_id: "t1",
            subject: "Shared",
            sender: "a@x.com",
            sender_name: nil,
            snippet: "",
            is_read: false,
            is_starred: false,
            labels: ["INBOX", "UNREAD"],
            received_at: "2026-08-15T12:00:00.000Z",
            account_email: "user@example.com",
            marked_read_at: nil
        )
        let merged = CatchUpLoadSupport.mergeUnreadIntoAllEmails(
            inboxEmails: [shared],
            unreadEmails: [shared]
        )
        XCTAssertEqual(merged.count, 1)
    }

    func testShouldDeferLiveFetch_whenSnapshotIsRecent() {
        let now = Date()
        let recent = now.addingTimeInterval(-10)
        XCTAssertTrue(CatchUpLoadSupport.shouldDeferLiveFetch(snapshotTimestamp: recent, now: now))
        XCTAssertFalse(CatchUpLoadSupport.shouldDeferLiveFetch(snapshotTimestamp: now.addingTimeInterval(-120), now: now))
    }
}
