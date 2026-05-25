import XCTest
@testable import EmptyMyInboxShared

final class EmailThreadGroupingTests: XCTestCase {
    private func makeItem(
        id: Int,
        gmailId: String,
        threadId: String,
        subject: String = "Subject",
        sender: String = "alice@example.com",
        isRead: Bool = false,
        receivedAt: String = "2026-05-20T12:00:00.000Z"
    ) -> EmailListItem {
        EmailListItem(
            id: id,
            gmail_id: gmailId,
            thread_id: threadId,
            subject: subject,
            sender: sender,
            sender_name: "Alice",
            snippet: "Snippet",
            is_read: isRead,
            is_starred: false,
            labels: isRead ? ["INBOX"] : ["INBOX", "UNREAD"],
            received_at: receivedAt,
            account_email: "user@example.com",
            marked_read_at: nil
        )
    }

    func testSummarizeThreads_groupsByThreadId() {
        let emails = [
            makeItem(id: 1, gmailId: "m1", threadId: "t1", receivedAt: "2026-05-20T10:00:00.000Z"),
            makeItem(id: 2, gmailId: "m2", threadId: "t1", isRead: false, receivedAt: "2026-05-20T12:00:00.000Z"),
            makeItem(id: 3, gmailId: "m3", threadId: "t2", receivedAt: "2026-05-20T11:00:00.000Z"),
        ]

        let summaries = EmailThreadGrouping.summarizeThreads(from: emails)
        XCTAssertEqual(summaries.count, 2)

        let thread1 = summaries.first { $0.threadId == "t1" }
        XCTAssertEqual(thread1?.unreadCount, 2)
        XCTAssertEqual(thread1?.messageCount, 2)
        XCTAssertEqual(thread1?.latestMessage.gmail_id, "m2")
    }

    func testSummarizeThreads_fallbackPerMessageWhenThreadIdMissing() {
        let emails = [
            makeItem(id: 1, gmailId: "m1", threadId: ""),
            makeItem(id: 2, gmailId: "m2", threadId: ""),
        ]
        let summaries = EmailThreadGrouping.summarizeThreads(from: emails)
        XCTAssertEqual(summaries.count, 2)
    }

    func testDefaultActionTargetPrefersNewestUnread() {
        let details = [
            EmailDetail(
                id: 1, gmail_id: "m1", thread_id: "t1", subject: "A", sender: "a@x.com",
                sender_name: nil, recipients_to: nil, recipients_cc: nil, recipients_bcc: nil,
                body_text: "", body_html: nil, snippet: "", is_read: true, is_starred: false,
                labels: [], received_at: "2026-05-20T10:00:00.000Z", account_email: "u@x.com", created_at: ""
            ),
            EmailDetail(
                id: 2, gmail_id: "m2", thread_id: "t1", subject: "B", sender: "b@x.com",
                sender_name: nil, recipients_to: nil, recipients_cc: nil, recipients_bcc: nil,
                body_text: "", body_html: nil, snippet: "", is_read: false, is_starred: false,
                labels: ["UNREAD"], received_at: "2026-05-20T12:00:00.000Z", account_email: "u@x.com", created_at: ""
            ),
            EmailDetail(
                id: 3, gmail_id: "m3", thread_id: "t1", subject: "C", sender: "c@x.com",
                sender_name: nil, recipients_to: nil, recipients_cc: nil, recipients_bcc: nil,
                body_text: "", body_html: nil, snippet: "", is_read: false, is_starred: false,
                labels: ["UNREAD"], received_at: "2026-05-20T11:00:00.000Z", account_email: "u@x.com", created_at: ""
            ),
        ]

        let target = EmailThreadConversation.defaultActionTargetId(in: details)
        XCTAssertEqual(target, 2)
    }

    func testCatchUpThreads_filtersStarredAndRead() {
        let metadata = [
            EmailMetadata(
                id: 1, gmail_id: "m1", thread_id: "t1", subject: "S", sender: "a@x.com",
                sender_name: nil, snippet: "", is_read: false, is_starred: false,
                labels: ["INBOX", "UNREAD"], received_at: "2026-05-20T12:00:00.000Z", account_email: "u@x.com"
            ),
            EmailMetadata(
                id: 2, gmail_id: "m2", thread_id: "t1", subject: "S2", sender: "a@x.com",
                sender_name: nil, snippet: "", is_read: false, is_starred: true,
                labels: ["INBOX", "UNREAD", "STARRED"], received_at: "2026-05-20T11:00:00.000Z", account_email: "u@x.com"
            ),
        ]

        let items = EmailThreadGrouping.catchUpThreads(from: metadata)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].unreadCount, 1)
    }
}
