import Foundation
import Testing
import EmptyMyInboxShared

struct PluginPromptStoreTests {
    private func makeStore(testName: String) -> (PluginPromptStore, UserDefaults, String) {
        let suiteName = "emptyMyInbox.tests.prompts.\(testName)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return (PluginPromptStore(userDefaults: defaults), defaults, suiteName)
    }

    @Test("Plugin prompt store resolves built-in defaults when unset")
    func testResolvedDefaultsWhenUnset() async {
        let (store, _, _) = makeStore(testName: "defaults")
        let brief = await store.resolvedBriefPrompts()
        let stories = await store.resolvedStoriesPrompts()
        let quickReply = await store.resolvedQuickReplyPrompts()

        #expect(brief.system == PluginPromptStore.defaultBriefSystemPrompt)
        #expect(brief.userTemplate == PluginPromptStore.defaultBriefUserPromptTemplate)
        #expect(stories.system == PluginPromptStore.defaultStoriesSystemPrompt)
        #expect(stories.userTemplate == PluginPromptStore.defaultStoriesUserPromptTemplate)
        #expect(quickReply.system == PluginPromptStore.defaultQuickReplySystemPrompt)
        #expect(quickReply.userTemplate == PluginPromptStore.defaultQuickReplyUserPromptTemplate)
    }

    @Test("Plugin prompt store persists custom prompts")
    func testSaveAndReadCustomPrompts() async {
        let (store, _, _) = makeStore(testName: "custom")
        let briefSystem = "brief-system-custom"
        let briefUser = "brief-user \(PluginPromptPlaceholder.inputJSON)"
        let storiesSystem = "stories-system-custom"
        let storiesUser = "stories-user \(PluginPromptPlaceholder.inputJSON)"
        let quickReplySystem = "quick-reply-system-custom"
        let quickReplyUser = "quick-reply-user \(PluginPromptPlaceholder.inputJSON)"

        await store.saveBriefPrompts(system: briefSystem, userTemplate: briefUser)
        await store.saveStoriesPrompts(system: storiesSystem, userTemplate: storiesUser)
        await store.saveQuickReplyPrompts(system: quickReplySystem, userTemplate: quickReplyUser)

        let brief = await store.resolvedBriefPrompts()
        let stories = await store.resolvedStoriesPrompts()
        let quickReply = await store.resolvedQuickReplyPrompts()
        #expect(brief.system == briefSystem)
        #expect(brief.userTemplate == briefUser)
        #expect(stories.system == storiesSystem)
        #expect(stories.userTemplate == storiesUser)
        #expect(quickReply.system == quickReplySystem)
        #expect(quickReply.userTemplate == quickReplyUser)
    }

    @Test("Plugin prompt store reset restores defaults")
    func testResetToDefaults() async {
        let (store, _, _) = makeStore(testName: "reset")
        await store.saveBriefPrompts(system: "x", userTemplate: "y")
        await store.saveStoriesPrompts(system: "x2", userTemplate: "y2")
        await store.saveQuickReplyPrompts(system: "x3", userTemplate: "y3")

        await store.resetBriefPromptsToDefaults()
        await store.resetStoriesPromptsToDefaults()
        await store.resetQuickReplyPromptsToDefaults()

        let brief = await store.resolvedBriefPrompts()
        let stories = await store.resolvedStoriesPrompts()
        let quickReply = await store.resolvedQuickReplyPrompts()
        #expect(brief.system == PluginPromptStore.defaultBriefSystemPrompt)
        #expect(brief.userTemplate == PluginPromptStore.defaultBriefUserPromptTemplate)
        #expect(stories.system == PluginPromptStore.defaultStoriesSystemPrompt)
        #expect(stories.userTemplate == PluginPromptStore.defaultStoriesUserPromptTemplate)
        #expect(quickReply.system == PluginPromptStore.defaultQuickReplySystemPrompt)
        #expect(quickReply.userTemplate == PluginPromptStore.defaultQuickReplyUserPromptTemplate)
    }
}
