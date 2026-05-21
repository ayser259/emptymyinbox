import XCTest
@testable import EmptyMyInboxShared

final class SentMailDisplayTests: XCTestCase {
    func testSentMailShowsToPrefix() {
        let sent = EmailListItem(
            id: 1,
            gmail_id: "g1",
            thread_id: "t1",
            subject: "Hello",
            sender: "recipient@example.com",
            sender_name: "Recipient",
            snippet: "Snippet",
            is_read: true,
            is_starred: false,
            labels: ["SENT"],
            received_at: "2026-05-19T10:00:00.000Z",
            account_email: "me@test.com",
            marked_read_at: nil
        )

        XCTAssertTrue(EmailListItemDisplay.isSentMail(sent))
        XCTAssertEqual(EmailListItemDisplay.senderDisplayName(for: sent), "To: Recipient")
    }

    func testParseSentMetadataUsesToHeader() {
        let headers = [
            GmailHeader(name: "From", value: "Me <me@test.com>"),
            GmailHeader(name: "To", value: "Recipient <recipient@example.com>"),
            GmailHeader(name: "Subject", value: "Hello")
        ]
        let payload = GmailPayload(mimeType: "text/plain", headers: headers, parts: nil, body: nil)
        let message = GmailMessage(
            id: "sent-1",
            threadId: "thread-1",
            snippet: "Snippet",
            payload: payload,
            labelIds: ["SENT"],
            internalDate: String(Int(Date().timeIntervalSince1970 * 1000))
        )

        let metadata = GmailAPIService.shared.parseEmailMetadata(
            from: message,
            accountEmail: "me@test.com",
            emailId: 42
        )

        XCTAssertEqual(metadata.sender, "recipient@example.com")
        XCTAssertEqual(metadata.sender_name, "Recipient")
    }
}
