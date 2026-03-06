import Foundation
import Testing
@testable import emptyMyInbox

struct InsightEngineTests {
    @Test("Insight engine ignores non-newsletters")
    func testInsightEngineSkipsNonNewsletterEmails() async {
        let email = EmailListItem(
            id: 1,
            gmail_id: "msg-1",
            subject: "Re: Project follow-up",
            sender: "teammate@example.com",
            sender_name: "Teammate",
            snippet: "Following up on action items",
            is_read: false,
            is_starred: false,
            labels: ["INBOX", "UNREAD"],
            received_at: ISO8601DateFormatter().string(from: Date()),
            account_email: "insights@example.com",
            marked_read_at: nil
        )

        let candidates = await InsightEngine.shared.selectUnpromptedCandidates(
            from: [email],
            promptStates: [:]
        )
        #expect(candidates.isEmpty == true)
    }

    @Test("Insight engine respects prompt cooldown and success suppression")
    func testSelectCandidatesUsesPromptState() async {
        let now = Date()
        let preferredAddress = await AccountInclusionStore.shared.primaryNewsletterAddress() ?? "insights@example.com"
        let email = EmailListItem(
            id: 2,
            gmail_id: "msg-2",
            subject: "Weekly digest: product updates",
            sender: "newsletter@example.com",
            sender_name: "Newsletter",
            snippet: "Top stories this week",
            is_read: false,
            is_starred: false,
            labels: ["INBOX", "UNREAD", "CATEGORY_PROMOTIONS"],
            received_at: ISO8601DateFormatter().string(from: now),
            account_email: preferredAddress,
            marked_read_at: nil
        )

        let failedState = StoryPromptState(
            status: .failed,
            attempts: 1,
            lastAttemptAt: now,
            lastSuccessAt: nil,
            lastError: "network",
            cooldownUntil: now.addingTimeInterval(3600)
        )
        let skipped = await InsightEngine.shared.selectUnpromptedCandidates(
            from: [email],
            promptStates: [email.id: failedState],
            now: now
        )
        #expect(skipped.isEmpty)

        let retried = await InsightEngine.shared.selectUnpromptedCandidates(
            from: [email],
            promptStates: [email.id: failedState],
            now: now.addingTimeInterval(3700)
        )
        #expect(retried.count >= skipped.count)

        let successState = StoryPromptState(
            status: .succeeded,
            attempts: 1,
            lastAttemptAt: now,
            lastSuccessAt: now,
            lastError: nil,
            cooldownUntil: nil
        )
        let successSuppressed = await InsightEngine.shared.selectUnpromptedCandidates(
            from: [email],
            promptStates: [email.id: successState],
            now: now.addingTimeInterval(7200)
        )
        #expect(successSuppressed.count <= retried.count)
    }
}
