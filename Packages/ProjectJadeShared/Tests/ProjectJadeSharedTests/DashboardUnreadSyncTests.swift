import XCTest
@testable import ProjectJadeShared

final class DashboardUnreadSyncTests: XCTestCase {
    private func makeUnreadItem(
        id: Int,
        gmailId: String,
        receivedAt: String,
        accountEmail: String = "user@example.com"
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
            is_starred: false,
            labels: ["INBOX", "UNREAD"],
            received_at: receivedAt,
            account_email: accountEmail,
            marked_read_at: nil
        )
    }

    private func makeReadItem(
        id: Int,
        gmailId: String,
        receivedAt: String,
        accountEmail: String = "user@example.com"
    ) -> EmailListItem {
        EmailListItem(
            id: id,
            gmail_id: gmailId,
            thread_id: "thread-\(gmailId)",
            subject: "Read \(id)",
            sender: "sender@example.com",
            sender_name: "Sender",
            snippet: "Snippet",
            is_read: true,
            is_starred: false,
            labels: ["INBOX"],
            received_at: receivedAt,
            account_email: accountEmail,
            marked_read_at: nil
        )
    }

    func testMergeUnreadIntoAllEmails_includesBuriedUnreadNotInFirstInboxPage() {
        let recentRead = makeReadItem(id: 1, gmailId: "read-1", receivedAt: "2026-08-15T12:00:00.000Z")
        let buriedUnread = makeUnreadItem(id: 2, gmailId: "old-unread", receivedAt: "2026-01-01T08:00:00.000Z")

        let merged = CatchUpLoadSupport.mergeUnreadIntoAllEmails(
            inboxEmails: [recentRead],
            unreadEmails: [buriedUnread]
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains(where: { $0.gmail_id == "old-unread" }))
    }

    func testDisplayUnreadCount_prefersGmailWhileLocalSyncIsPartial() {
        XCTAssertEqual(
            CatchUpLoadSupport.displayUnreadCount(localNonStarred: 50, gmailInboxUnread: 612),
            612
        )
        XCTAssertEqual(
            CatchUpLoadSupport.displayUnreadCount(localNonStarred: 612, gmailInboxUnread: 612),
            612
        )
    }

    func testAccumulateMessageRefs_supportsPaginatedUnreadListingBeyondFirstPage() {
        let page1 = (0..<500).map { GmailMessageReference(id: "m\($0)", threadId: "t\($0)") }
        let page2 = (500..<620).map { GmailMessageReference(id: "m\($0)", threadId: "t\($0)") }

        let accumulated = CatchUpLoadSupport.accumulateMessageRefs(
            pages: [page1, page2],
            maxTotal: CatchUpLoadSupport.defaultUnreadListingCap
        )

        XCTAssertEqual(accumulated.count, 620)
    }

    func testSeedMetadata_matchesDashboardUnreadSnapshot() {
        let buried = makeUnreadItem(id: 10, gmailId: "buried", receivedAt: "2026-01-01T08:00:00.000Z")
        let snapshot = DashboardDataSnapshot(
            timestamp: Date(),
            accounts: [],
            emails: [buried],
            allEmails: [buried],
            starredEmails: [],
            sentEmails: [],
            labels: []
        )

        let seeded = CatchUpLoadSupport.seedMetadata(
            from: snapshot,
            accountEmail: nil,
            allowedAccountEmails: ["user@example.com"]
        )

        XCTAssertEqual(seeded.count, 1)
        XCTAssertEqual(seeded[0].gmail_id, "buried")
    }

    func testLocalUnreadCount_excludesStarredUnread() {
        let emails = [
            makeUnreadItem(id: 1, gmailId: "m1", receivedAt: "2026-08-15T12:00:00.000Z"),
            EmailListItem(
                id: 2,
                gmail_id: "m2",
                thread_id: "t2",
                subject: "Starred",
                sender: "sender@example.com",
                sender_name: nil,
                snippet: "",
                is_read: false,
                is_starred: true,
                labels: ["INBOX", "UNREAD", "STARRED"],
                received_at: "2026-08-14T12:00:00.000Z",
                account_email: "user@example.com",
                marked_read_at: nil
            ),
        ]

        XCTAssertEqual(CatchUpLoadSupport.localUnreadCount(for: "user@example.com", in: emails), 1)
    }
}
