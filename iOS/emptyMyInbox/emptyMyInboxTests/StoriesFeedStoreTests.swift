import Foundation
import Testing
import EmptyMyInboxShared

@Suite(.serialized)
struct StoriesFeedStoreTests {
    private func makeStore(testName: String) -> StoriesFeedStore {
        let suffix = "\(testName)-\(UUID().uuidString)"
        return StoriesFeedStore(
            fileName: "stories_\(suffix).json",
            appSupportFolderName: "emptyMyInboxTests-\(suffix)"
        )
    }

    private func makeCard(id: Int, emailId: Int) -> InsightCard {
        InsightCard(
            id: id,
            emailId: emailId,
            gmailId: "gmail-\(emailId)",
            accountEmail: "stories@example.com",
            sender: "newsletter@example.com",
            senderName: "Newsletter",
            subject: "Subject \(id)",
            summary: "Summary \(id)",
            keyPoints: ["A", "B", "C"],
            theme: NewsletterTheme(tag: "AI", confidence: 0.9)
        )
    }

    @Test("Stories feed deduplicates and caps retained cards")
    func testStoriesDedupAndCap() async {
        let store = makeStore(testName: "dedup-cap")
        for i in 0..<220 {
            await store.appendStories([makeCard(id: i, emailId: i)])
        }
        // Duplicate append should not increase count.
        await store.appendStories([makeCard(id: 219, emailId: 219)])

        let stories = await store.stories()
        #expect(stories.count == 200)
        #expect(stories.contains(where: { $0.id == 219 }))
    }

    @Test("Stories feed tracks success and failure prompt outcomes")
    func testPromptOutcomeLifecycle() async {
        let store = makeStore(testName: "outcomes")
        await store.applyPromptOutcome(StoryPromptOutcome(emailId: 1, result: .failed(reason: "network")))
        await store.applyPromptOutcome(StoryPromptOutcome(emailId: 2, result: .empty))
        await store.applyPromptOutcome(StoryPromptOutcome(emailId: 3, result: .success))

        let states = await store.promptStates()
        #expect(states[1]?.status == .failed)
        #expect(states[1]?.cooldownUntil != nil)
        #expect(states[2]?.status == .failed)
        #expect(states[3]?.status == .succeeded)
        #expect(states[3]?.lastSuccessAt != nil)
    }
}
