import Foundation

public actor LLMProviderRouter {
    public static let shared = LLMProviderRouter()

    public func selectedProvider() async -> LLMProvider {
        let settings = await LLMSettingsStore.shared.currentSettings()
        return settings.provider
    }

    public func hasSelectedProviderAPIKey() async -> Bool {
        let provider = await selectedProvider()
        switch provider {
        case .openAI:
            return await LLMSettingsStore.shared.hasAPIKey()
        case .claude:
            return await ClaudeAPIKeyStore.shared.hasAPIKey()
        }
    }

    public func classifyBriefingItem(subject: String, snippet: String, sender: String) async throws -> BriefingItemType {
        let provider = await selectedProvider()
        switch provider {
        case .openAI:
            return try await OpenAIService.shared.classifyBriefingItem(subject: subject, snippet: snippet, sender: sender)
        case .claude:
            return try await ClaudeService.shared.classifyBriefingItem(subject: subject, snippet: snippet, sender: sender)
        }
    }

    public func summarizeNewsletterStories(
        subject: String,
        snippet: String,
        sender: String,
        body: String?,
        preferenceContext: String
    ) async throws -> [InsightGenerationResult] {
        let provider = await selectedProvider()
        switch provider {
        case .openAI:
            return try await OpenAIService.shared.summarizeNewsletterStories(
                subject: subject,
                snippet: snippet,
                sender: sender,
                body: body,
                preferenceContext: preferenceContext
            )
        case .claude:
            return try await ClaudeService.shared.summarizeNewsletterStories(
                subject: subject,
                snippet: snippet,
                sender: sender,
                body: body,
                preferenceContext: preferenceContext
            )
        }
    }

    public func quickReply(
        subject: String,
        sender: String,
        snippet: String,
        body: String,
        userAsk: String
    ) async throws -> String {
        let provider = await selectedProvider()
        switch provider {
        case .openAI:
            return try await OpenAIService.shared.quickReply(
                subject: subject,
                sender: sender,
                snippet: snippet,
                body: body,
                userAsk: userAsk
            )
        case .claude:
            return try await ClaudeService.shared.quickReply(
                subject: subject,
                sender: sender,
                snippet: snippet,
                body: body,
                userAsk: userAsk
            )
        }
    }
}
