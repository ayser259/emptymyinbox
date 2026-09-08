import Foundation
import FoundationModels

@Generable
private struct OnDeviceDailyBriefItem {
    @Guide(description: "The emailId from the input candidate list.")
    var emailId: Int
    var summary: String
    var actionItems: [String]?
    var sourceLabel: String?
}

@Generable
private enum OnDeviceBriefSectionKind: String {
    case urgentToday
    case criticalReminders
    case unreadFromYesterday
    case receiptsAndTransactions
}

@Generable
private struct OnDeviceDailyBriefSection {
    var kind: OnDeviceBriefSectionKind
    var title: String?
    var items: [OnDeviceDailyBriefItem]
}

@Generable
private struct OnDeviceDailyBriefResponse {
    var introText: String
    var sections: [OnDeviceDailyBriefSection]
}

@Generable
private struct OnDeviceStoryInsight {
    var summary: String
    var keyPoints: [String]
    var themeTag: String
    var confidence: Double
}

@Generable
private struct OnDeviceStoryInsightsResponse {
    var insights: [OnDeviceStoryInsight]
}

@Generable
private struct OnDeviceQuickReplyResponse {
    var reply: String
}

public enum OnDeviceAIServiceError: LocalizedError, Sendable {
    case unavailable(SystemLanguageModel.Availability)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Intelligence is unavailable on this device. Turn it on in System Settings, or switch to a cloud model."
        case .invalidResponse:
            return "The on-device model returned an empty response."
        }
    }
}

public enum AIGenerationCapability: Sendable, Equatable {
    case ready
    case onDeviceUnavailable
    case missingAPIKey(provider: LLMProvider)
}

public actor OnDeviceAIService {
    public static let shared = OnDeviceAIService()

    public static let maxCandidatesPerBucket = 8
    private static let maxBodyCharacters = 2_000

    public static func isAvailable() -> Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    public func generateDailyBrief(candidates: DailyBriefCandidates) async throws -> DailyBriefLLMResponse {
        try ensureAvailable()
        let trimmed = Self.trimCandidatesForOnDevice(candidates)
        let inputJSON = LLMPromptEncoding.encodeJSON(trimmed)
        let (systemPrompt, userTemplate) = await PluginPromptStore.shared.resolvedBriefPrompts()
        let userPrompt = LLMPromptEncoding.userPromptWithInputJSON(template: userTemplate, inputJSON: inputJSON)
        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: userPrompt, generating: OnDeviceDailyBriefResponse.self)
        return Self.mapBriefResponse(response.content)
    }

    public func summarizeNewsletterStories(
        subject: String,
        snippet: String,
        sender: String,
        body: String?,
        preferenceContext: String
    ) async throws -> [InsightGenerationResult] {
        try ensureAvailable()
        let inputJSON = LLMPromptEncoding.encodeJSON([
            "sender": sender,
            "subject": subject,
            "snippet": snippet,
            "body": Self.truncatedBody(body),
            "preferenceContext": preferenceContext
        ])
        let (systemPrompt, userTemplate) = await PluginPromptStore.shared.resolvedStoriesPrompts()
        let userPrompt = LLMPromptEncoding.userPromptWithInputJSON(template: userTemplate, inputJSON: inputJSON)
        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: userPrompt, generating: OnDeviceStoryInsightsResponse.self)
        return response.content.insights.map {
            InsightGenerationResult(
                summary: $0.summary,
                keyPoints: $0.keyPoints,
                themeTag: $0.themeTag,
                confidence: $0.confidence
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
        try ensureAvailable()
        var input: [String: String] = [
            "sender": sender,
            "subject": subject,
            "snippet": snippet,
            "body": Self.truncatedBody(body),
            "quickReplyAsk": userAsk
        ]
        if !currentDraft.isEmpty { input["currentDraft"] = currentDraft }
        if !recipientsTo.isEmpty { input["recipientsTo"] = recipientsTo }
        if !recipientsCc.isEmpty { input["recipientsCc"] = recipientsCc }
        let inputJSON = LLMPromptEncoding.encodeJSON(input)
        let (systemPrompt, userTemplate) = await PluginPromptStore.shared.resolvedQuickReplyPrompts()
        let userPrompt = LLMPromptEncoding.userPromptWithInputJSON(template: userTemplate, inputJSON: inputJSON)
        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: userPrompt, generating: OnDeviceQuickReplyResponse.self)
        let reply = response.content.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else {
            throw OnDeviceAIServiceError.invalidResponse
        }
        return reply
    }

    private func ensureAvailable() throws {
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else {
            throw OnDeviceAIServiceError.unavailable(availability)
        }
    }

    static func trimCandidatesForOnDevice(_ candidates: DailyBriefCandidates) -> DailyBriefCandidates {
        DailyBriefCandidates(
            todayDate: candidates.todayDate,
            yesterdayDate: candidates.yesterdayDate,
            urgentToday: Array(candidates.urgentToday.prefix(maxCandidatesPerBucket)),
            criticalReminders: Array(candidates.criticalReminders.prefix(maxCandidatesPerBucket)),
            unreadFromYesterday: Array(candidates.unreadFromYesterday.prefix(maxCandidatesPerBucket)),
            receiptsAndTransactions: Array(candidates.receiptsAndTransactions.prefix(maxCandidatesPerBucket))
        )
    }

    private static func truncatedBody(_ body: String?) -> String {
        guard let body else { return "" }
        if body.count <= maxBodyCharacters {
            return body
        }
        return String(body.prefix(maxBodyCharacters))
    }

    private static func mapBriefResponse(_ response: OnDeviceDailyBriefResponse) -> DailyBriefLLMResponse {
        DailyBriefLLMResponse(
            introText: response.introText,
            sections: response.sections.compactMap { section in
                guard let kind = mapSectionKind(section.kind) else { return nil }
                return DailyBriefLLMSection(
                    kind: kind,
                    title: section.title,
                    items: section.items.map {
                        DailyBriefLLMItem(
                            emailId: $0.emailId,
                            summary: $0.summary,
                            actionItems: $0.actionItems,
                            sourceLabel: $0.sourceLabel
                        )
                    }
                )
            }
        )
    }

    private static func mapSectionKind(_ kind: OnDeviceBriefSectionKind) -> BriefingSectionKind? {
        switch kind {
        case .urgentToday:
            return .urgentToday
        case .criticalReminders:
            return .criticalReminders
        case .unreadFromYesterday:
            return .unreadFromYesterday
        case .receiptsAndTransactions:
            return .receiptsAndTransactions
        }
    }
}

public extension AIGenerationCapability {
    var allowsGeneration: Bool {
        self == .ready
    }

    var upsellTitle: String {
        switch self {
        case .ready:
            return ""
        case .onDeviceUnavailable:
            return "Apple Intelligence Unavailable"
        case .missingAPIKey:
            return "Set up AI"
        }
    }

    var upsellSubtitle: String {
        switch self {
        case .ready:
            return ""
        case .onDeviceUnavailable:
            return "Turn on Apple Intelligence in System Settings, or switch to a cloud model in Settings."
        case .missingAPIKey(let provider):
            return "Add a \(provider.displayName) API key to enable this feature."
        }
    }

    var upsellActionTitle: String {
        switch self {
        case .ready:
            return ""
        case .onDeviceUnavailable:
            return "Model Settings"
        case .missingAPIKey:
            return "Add API Key"
        }
    }
}
