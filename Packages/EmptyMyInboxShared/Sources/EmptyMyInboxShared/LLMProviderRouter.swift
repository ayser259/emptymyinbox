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

    /// True if the selected provider has a key, or any provider has a key (Quick Reply can still run).
    public func hasUsableAPIKeyForQuickReply() async -> Bool {
        if await hasSelectedProviderAPIKey() { return true }
        let hasOpenAI = await LLMSettingsStore.shared.hasAPIKey()
        let hasClaude = await ClaudeAPIKeyStore.shared.hasAPIKey()
        return hasOpenAI || hasClaude
    }

    public func generateDailyBrief(candidates: DailyBriefCandidates) async throws -> DailyBriefLLMResponse {
        let provider = await selectedProvider()
        switch provider {
        case .openAI:
            return try await OpenAIService.shared.generateDailyBrief(candidates: candidates)
        case .claude:
            return try await ClaudeService.shared.generateDailyBrief(candidates: candidates)
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
        userAsk: String,
        currentDraft: String = "",
        recipientsTo: String = "",
        recipientsCc: String = ""
    ) async throws -> String {
        let args = (
            subject: subject,
            sender: sender,
            snippet: snippet,
            body: body,
            userAsk: userAsk,
            currentDraft: currentDraft,
            recipientsTo: recipientsTo,
            recipientsCc: recipientsCc
        )
        let selected = await selectedProvider()
        switch selected {
        case .openAI:
            if await LLMSettingsStore.shared.hasAPIKey() {
                return try await openAIQuickReply(args)
            }
            if await ClaudeAPIKeyStore.shared.hasAPIKey() {
                return try await claudeQuickReply(args)
            }
        case .claude:
            if await ClaudeAPIKeyStore.shared.hasAPIKey() {
                return try await claudeQuickReply(args)
            }
            if await LLMSettingsStore.shared.hasAPIKey() {
                return try await openAIQuickReply(args)
            }
        }
        throw LLMProviderRouterError.missingAPIKey(provider: selected)
    }

    private typealias QuickReplyArgs = (
        subject: String,
        sender: String,
        snippet: String,
        body: String,
        userAsk: String,
        currentDraft: String,
        recipientsTo: String,
        recipientsCc: String
    )

    private func openAIQuickReply(_ args: QuickReplyArgs) async throws -> String {
        try await OpenAIService.shared.quickReply(
            subject: args.subject,
            sender: args.sender,
            snippet: args.snippet,
            body: args.body,
            userAsk: args.userAsk,
            currentDraft: args.currentDraft,
            recipientsTo: args.recipientsTo,
            recipientsCc: args.recipientsCc
        )
    }

    private func claudeQuickReply(_ args: QuickReplyArgs) async throws -> String {
        try await ClaudeService.shared.quickReply(
            subject: args.subject,
            sender: args.sender,
            snippet: args.snippet,
            body: args.body,
            userAsk: args.userAsk,
            currentDraft: args.currentDraft,
            recipientsTo: args.recipientsTo,
            recipientsCc: args.recipientsCc
        )
    }
}

public enum LLMProviderRouterError: LocalizedError, Sendable {
    case missingAPIKey(provider: LLMProvider)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Add a \(provider.displayName) API key under Settings → Keys."
        }
    }
}
