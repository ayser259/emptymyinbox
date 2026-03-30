import Foundation
import Testing
import EmptyMyInboxShared

struct DailyBriefingEngineTests {
    @Test("Daily briefing excludes newsletters and keeps urgent/calendar/direct items")
    func testDailyBriefingFilteringAndClassification() async {
        let now = ISO8601DateFormatter().string(from: Date())
        let emails = [
            EmailListItem(
                id: 1,
                gmail_id: "msg-1",
                subject: "Urgent: security alert",
                sender: "alerts@example.com",
                sender_name: "Security",
                snippet: "Please review immediately",
                is_read: false,
                is_starred: false,
                labels: ["INBOX", "UNREAD"],
                received_at: now,
                account_email: "briefing@example.com",
                marked_read_at: nil
            ),
            EmailListItem(
                id: 2,
                gmail_id: "msg-2",
                subject: "Calendar invite: Team Sync",
                sender: "calendar@google.com",
                sender_name: "Calendar",
                snippet: "Meeting invitation",
                is_read: false,
                is_starred: false,
                labels: ["INBOX", "UNREAD"],
                received_at: now,
                account_email: "briefing@example.com",
                marked_read_at: nil
            ),
            EmailListItem(
                id: 3,
                gmail_id: "msg-3",
                subject: "Weekly newsletter digest",
                sender: "newsletter@updates.com",
                sender_name: "Updates",
                snippet: "Top stories",
                is_read: false,
                is_starred: false,
                labels: ["INBOX", "UNREAD", "CATEGORY_PROMOTIONS"],
                received_at: now,
                account_email: "briefing@example.com",
                marked_read_at: nil
            )
        ]

        let payload = await DailyBriefingEngine.shared.buildPayload(from: emails, sinceDate: nil)

        #expect(payload.items.count == 2)
        #expect(payload.items.contains(where: { $0.type == .urgentNotification }))
        #expect(payload.items.contains(where: { $0.type == .calendarInvite }))
        #expect(!payload.items.contains(where: { $0.subject.lowercased().contains("newsletter") }))
    }

    @Test("Daily briefing respects since date and max item cap")
    func testDailyBriefingSinceDateAndCap() async {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = Date()
        var emails: [EmailListItem] = []
        for index in 0..<10 {
            let date = now.addingTimeInterval(Double(-index * 60))
            emails.append(
                EmailListItem(
                    id: index + 100,
                    gmail_id: "msg-\(index + 100)",
                    subject: "Action required \(index)",
                    sender: "sender\(index)@example.com",
                    sender_name: "Sender \(index)",
                    snippet: "Please respond",
                    is_read: false,
                    is_starred: false,
                    labels: ["INBOX", "UNREAD"],
                    received_at: formatter.string(from: date),
                    account_email: "briefing@example.com",
                    marked_read_at: nil
                )
            )
        }

        let sinceDate = now.addingTimeInterval(-5 * 60)
        let payload = await DailyBriefingEngine.shared.buildPayload(from: emails, sinceDate: sinceDate)

        #expect(payload.items.count <= 6)
        #expect(payload.items.count <= 8)
        for item in payload.items {
            let parsed = formatter.date(from: item.receivedAt)
            #expect(parsed == nil || parsed! >= sinceDate)
        }
    }
}
