import XCTest
@testable import EmptyMyInboxShared

final class MailboxQueryTests: XCTestCase {
    private func makeEmail(
        id: Int,
        account: String,
        isRead: Bool = false,
        isStarred: Bool = false,
        receivedAt: String
    ) -> EmailListItem {
        EmailListItem(
            id: id,
            gmail_id: "g\(id)",
            thread_id: "thread-\(id)",
            subject: "Subject \(id)",
            sender: "sender\(id)@example.com",
            sender_name: nil,
            snippet: "Snippet",
            is_read: isRead,
            is_starred: isStarred,
            labels: [],
            received_at: receivedAt,
            account_email: account,
            marked_read_at: nil
        )
    }

    private func makeSnapshot(
        emails: [EmailListItem] = [],
        allEmails: [EmailListItem] = [],
        starredEmails: [EmailListItem] = [],
        sentEmails: [EmailListItem] = []
    ) -> DashboardDataSnapshot {
        DashboardDataSnapshot(
            timestamp: Date(),
            accounts: [],
            emails: emails,
            allEmails: allEmails,
            starredEmails: starredEmails,
            sentEmails: sentEmails,
            labels: []
        )
    }

    func testAllScopeUsesAllEmails() {
        let older = makeEmail(id: 1, account: "a@test.com", receivedAt: "2026-05-18T10:00:00.000Z")
        let newer = makeEmail(id: 2, account: "b@test.com", receivedAt: "2026-05-19T10:00:00.000Z")
        let snapshot = makeSnapshot(allEmails: [older, newer])

        let result = MailboxQuery.emails(in: snapshot, scope: .all)
        XCTAssertEqual(result.map(\.id), [2, 1])
    }

    func testAllUnreadScopeUsesUnreadCollection() {
        let unread = makeEmail(id: 1, account: "a@test.com", isRead: false, receivedAt: "2026-05-19T10:00:00.000Z")
        let read = makeEmail(id: 2, account: "a@test.com", isRead: true, receivedAt: "2026-05-19T11:00:00.000Z")
        let snapshot = makeSnapshot(
            emails: [unread],
            allEmails: [unread, read]
        )

        let result = MailboxQuery.emails(in: snapshot, scope: .allUnread)
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testSavedScopeUsesStarredEmails() {
        let starred = makeEmail(id: 1, account: "a@test.com", isStarred: true, receivedAt: "2026-05-19T10:00:00.000Z")
        let inboxOnly = makeEmail(id: 2, account: "a@test.com", isStarred: false, receivedAt: "2026-05-19T11:00:00.000Z")
        let snapshot = makeSnapshot(
            allEmails: [inboxOnly],
            starredEmails: [starred]
        )

        let result = MailboxQuery.emails(in: snapshot, scope: .saved)
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testAccountScopeFiltersCaseInsensitively() {
        let match = makeEmail(id: 1, account: "User@Test.com", receivedAt: "2026-05-19T10:00:00.000Z")
        let other = makeEmail(id: 2, account: "other@test.com", receivedAt: "2026-05-19T11:00:00.000Z")
        let snapshot = makeSnapshot(allEmails: [match, other])

        let result = MailboxQuery.emails(in: snapshot, scope: .account(email: "user@test.com"))
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testReadFilterUnreadOnAccountScope() {
        let unread = makeEmail(id: 1, account: "a@test.com", isRead: false, receivedAt: "2026-05-19T10:00:00.000Z")
        let read = makeEmail(id: 2, account: "a@test.com", isRead: true, receivedAt: "2026-05-19T11:00:00.000Z")
        let snapshot = makeSnapshot(allEmails: [unread, read])

        let result = MailboxQuery.emails(
            in: snapshot,
            scope: .account(email: "a@test.com"),
            readFilter: .unread
        )
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testAccountSavedScope() {
        let starredA = makeEmail(id: 1, account: "a@test.com", isStarred: true, receivedAt: "2026-05-19T10:00:00.000Z")
        let starredB = makeEmail(id: 2, account: "b@test.com", isStarred: true, receivedAt: "2026-05-19T11:00:00.000Z")
        let snapshot = makeSnapshot(starredEmails: [starredA, starredB])

        let result = MailboxQuery.emails(in: snapshot, scope: .accountSaved(email: "A@test.com"))
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testSentScopeUsesSentEmails() {
        var sent = makeEmail(id: 1, account: "a@test.com", receivedAt: "2026-05-19T10:00:00.000Z")
        sent = EmailListItem(
            id: sent.id,
            gmail_id: sent.gmail_id,
            thread_id: sent.thread_id,
            subject: sent.subject,
            sender: sent.sender,
            sender_name: sent.sender_name,
            snippet: sent.snippet,
            is_read: sent.is_read,
            is_starred: sent.is_starred,
            labels: ["SENT"],
            received_at: sent.received_at,
            account_email: sent.account_email,
            marked_read_at: nil
        )
        let inboxOnly = makeEmail(id: 2, account: "a@test.com", receivedAt: "2026-05-19T11:00:00.000Z")
        let snapshot = makeSnapshot(allEmails: [inboxOnly], sentEmails: [sent])

        let result = MailboxQuery.emails(in: snapshot, scope: .sent)
        XCTAssertEqual(result.map(\.id), [1])
    }

    func testAccountSentScopeFiltersCaseInsensitively() {
        let sentA = EmailListItem(
            id: 1,
            gmail_id: "g1",
            thread_id: "t1",
            subject: "Hi",
            sender: "recipient@example.com",
            sender_name: nil,
            snippet: "Snippet",
            is_read: true,
            is_starred: false,
            labels: ["SENT"],
            received_at: "2026-05-19T10:00:00.000Z",
            account_email: "User@Test.com",
            marked_read_at: nil
        )
        let sentB = EmailListItem(
            id: 2,
            gmail_id: "g2",
            thread_id: "t2",
            subject: "Hi",
            sender: "other@example.com",
            sender_name: nil,
            snippet: "Snippet",
            is_read: true,
            is_starred: false,
            labels: ["SENT"],
            received_at: "2026-05-19T11:00:00.000Z",
            account_email: "other@test.com",
            marked_read_at: nil
        )
        let snapshot = makeSnapshot(sentEmails: [sentA, sentB])

        let result = MailboxQuery.emails(in: snapshot, scope: .accountSent(email: "user@test.com"))
        XCTAssertEqual(result.map(\.id), [1])
    }
}
