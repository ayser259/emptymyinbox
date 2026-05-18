import Foundation
import Testing
import EmptyMyInboxShared

struct DailyBriefingEngineTests {
    @Test("Daily briefing requires an API key")
    func testDailyBriefingRequiresAPIKey() async {
        let hasKey = await LLMProviderRouter.shared.hasSelectedProviderAPIKey()
        guard !hasKey else { return }

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
            )
        ]

        let payload = await DailyBriefingEngine.shared.buildPayload(from: emails, sinceDate: nil)
        #expect(payload.items.isEmpty)
    }
}
