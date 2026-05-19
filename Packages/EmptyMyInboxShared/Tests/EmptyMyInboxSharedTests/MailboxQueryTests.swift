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
        starredEmails: [EmailListItem] = []
    ) -> DashboardDataSnapshot {
        DashboardDataSnapshot(
            timestamp: Date(),
            accounts: [],
            emails: emails,
            allEmails: allEmails,
            starredEmails: starredEmails,
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
}
