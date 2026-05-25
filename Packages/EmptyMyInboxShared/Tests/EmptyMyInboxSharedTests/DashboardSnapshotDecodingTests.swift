import XCTest
@testable import EmptyMyInboxShared

final class DashboardSnapshotDecodingTests: XCTestCase {
    func testLegacySnapshotWithoutSentEmailsDecodesAsEmpty() throws {
        let json = """
        {
          "timestamp": "2026-05-19T10:00:00.000Z",
          "accounts": [],
          "emails": [],
          "allEmails": [],
          "starredEmails": [],
          "labels": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(DashboardDataSnapshot.self, from: data)
        XCTAssertTrue(snapshot.sentEmails.isEmpty)
    }

    func testSnapshotWithSentEmailsRoundTrips() throws {
        let sent = EmailListItem(
            id: 1,
            gmail_id: "g1",
            thread_id: "t1",
            subject: "Sent",
            sender: "recipient@example.com",
            sender_name: nil,
            snippet: "Snippet",
            is_read: true,
            is_starred: false,
            labels: ["SENT"],
            received_at: "2026-05-19T10:00:00.000Z",
            account_email: "me@test.com",
            marked_read_at: nil
        )
        let snapshot = DashboardDataSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            accounts: [],
            emails: [],
            allEmails: [],
            starredEmails: [],
            sentEmails: [sent],
            labels: []
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DashboardDataSnapshot.self, from: data)
        XCTAssertEqual(decoded.sentEmails.count, 1)
        XCTAssertEqual(decoded.sentEmails.first?.gmail_id, "g1")
    }
}
