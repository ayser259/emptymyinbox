import Foundation

public actor LLMProviderRouter {
    public static let shared = LLMProviderRouter()

    public func selectedProvider() async -> LLMProvider {
        let settings = await LLMSettingsStore.shared.currentSettings()
        return settings.provider
    }

    public func briefProvider() async -> LLMProvider {
        let settings = await LLMSettingsStore.shared.currentSettings()
        return settings.briefProvider
    }

    public func storiesProvider() async -> LLMProvider {
        let settings = await LLMSettingsStore.shared.currentSettings()
        return settings.storiesProvider
    }

    public func quickReplyProvider() async -> LLMProvider {
        let settings = await LLMSettingsStore.shared.currentSettings()
        return settings.quickReplyProvider
    }

    public func hasSelectedProviderAPIKey() async -> Bool {
        let provider = await selectedProvider()
        return await hasAPIKey(for: provider)
    }

    public func hasAPIKey(for provider: LLMProvider) async -> Bool {
        switch provider {
        case .onDevice:
            return false
        case .openAI:
            return await LLMSettingsStore.shared.hasAPIKey()
        case .claude:
            return await ClaudeAPIKeyStore.shared.hasAPIKey()
        }
    }

    public func briefGenerationCapability() async -> AIGenerationCapability {
        let settings = await LLMSettingsStore.shared.currentSettings()
        return await capability(for: settings.briefProvider)
    }

    public func storiesGenerationCapability() async -> AIGenerationCapability {
        let settings = await LLMSettingsStore.shared.currentSettings()
        return await capability(for: settings.storiesProvider)
    }

    public func quickReplyGenerationCapability() async -> AIGenerationCapability {
        let settings = await LLMSettingsStore.shared.currentSettings()
        return await capability(for: settings.quickReplyProvider)
    }

    public func canGenerateBrief() async -> Bool {
        await briefGenerationCapability() == .ready
    }

    public func canGenerateStories() async -> Bool {
        await storiesGenerationCapability() == .ready
    }

    public func canGenerateQuickReply() async -> Bool {
        await quickReplyGenerationCapability() == .ready
    }

    public func generateDailyBrief(candidates: DailyBriefCandidates) async throws -> DailyBriefLLMResponse {
        let settings = await LLMSettingsStore.shared.currentSettings()
        switch settings.briefProvider {
        case .onDevice:
            return try await OnDeviceAIService.shared.generateDailyBrief(candidates: candidates)
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
        let settings = await LLMSettingsStore.shared.currentSettings()
        switch settings.storiesProvider {
        case .onDevice:
            return try await OnDeviceAIService.shared.summarizeNewsletterStories(
                subject: subject,
                snippet: snippet,
                sender: sender,
                body: body,
                preferenceContext: preferenceContext
            )
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
        let settings = await LLMSettingsStore.shared.currentSettings()
        switch settings.quickReplyProvider {
        case .onDevice:
            return try await OnDeviceAIService.shared.quickReply(
                subject: subject,
                sender: sender,
                snippet: snippet,
                body: body,
                userAsk: userAsk,
                currentDraft: currentDraft,
                recipientsTo: recipientsTo,
                recipientsCc: recipientsCc
            )
        case .openAI:
            return try await OpenAIService.shared.quickReply(
                subject: subject,
                sender: sender,
                snippet: snippet,
                body: body,
                userAsk: userAsk,
                currentDraft: currentDraft,
                recipientsTo: recipientsTo,
                recipientsCc: recipientsCc
            )
        case .claude:
            return try await ClaudeService.shared.quickReply(
                subject: subject,
                sender: sender,
                snippet: snippet,
                body: body,
                userAsk: userAsk,
                currentDraft: currentDraft,
                recipientsTo: recipientsTo,
                recipientsCc: recipientsCc
            )
        }
    }

    private func capability(for provider: LLMProvider) async -> AIGenerationCapability {
        switch provider {
        case .onDevice:
            return OnDeviceAIService.isAvailable() ? .ready : .onDeviceUnavailable
        case .openAI, .claude:
            if await hasAPIKey(for: provider) {
                return .ready
            }
            return .missingAPIKey(provider: provider)
        }
    }
}

public enum LLMProviderRouterError: LocalizedError, Sendable {
    case missingAPIKey(provider: LLMProvider)
    case unsupportedProvider(provider: LLMProvider)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Add a \(provider.displayName) API key under Settings → Keys."
        case .unsupportedProvider(let provider):
            return "\(provider.displayName) is not supported for this feature. Choose OpenAI or Claude under Settings."
        }
    }
}
