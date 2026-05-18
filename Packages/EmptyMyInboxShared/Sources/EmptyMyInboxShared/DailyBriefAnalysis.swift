import Foundation

// MARK: - Candidate buckets (engine → LLM)

public struct DailyBriefEmailCandidate: Codable {
    public let emailId: Int
    public let sender: String
    public let senderName: String?
    public let subject: String
    public let snippet: String
    public let receivedAt: String
    public let isRead: Bool
    public let labels: [String]
}

public struct DailyBriefCandidates: Codable {
    public let todayDate: String
    public let yesterdayDate: String
    public let urgentToday: [DailyBriefEmailCandidate]
    public let criticalReminders: [DailyBriefEmailCandidate]
    public let unreadFromYesterday: [DailyBriefEmailCandidate]
    public let receiptsAndTransactions: [DailyBriefEmailCandidate]
}

// MARK: - LLM response (parsed → payload)

public struct DailyBriefLLMResponse: Codable {
    public let introText: String
    public let sections: [DailyBriefLLMSection]
}

public struct DailyBriefLLMSection: Codable {
    public let kind: BriefingSectionKind
    public let title: String?
    public let items: [DailyBriefLLMItem]
}

public struct DailyBriefLLMItem: Codable {
    public let emailId: Int
    public let summary: String
    public let actionItems: [String]?
    public let sourceLabel: String?
}

enum DailyBriefMapper {
    static func payload(
        from response: DailyBriefLLMResponse,
        emailById: [Int: EmailListItem],
        generatedAt: Date,
        sinceDate: Date?
    ) -> DailyBriefingPayload {
        let sections = response.sections.compactMap { section -> DailyBriefingSection? in
            let items = section.items.compactMap { llmItem -> DailyBriefingItem? in
                guard let email = emailById[llmItem.emailId] else { return nil }
                return item(from: llmItem, email: email, section: section.kind)
            }
            guard !items.isEmpty else { return nil }
            return DailyBriefingSection(
                kind: section.kind,
                title: section.title,
                items: items
            )
        }
        return DailyBriefingPayload(
            generatedAt: generatedAt,
            sinceDate: sinceDate,
            introText: response.introText,
            sections: sections
        )
    }

    private static func item(
        from llmItem: DailyBriefLLMItem,
        email: EmailListItem,
        section: BriefingSectionKind
    ) -> DailyBriefingItem {
        DailyBriefingItem(
            id: email.id,
            emailId: email.id,
            gmailId: email.gmail_id,
            threadId: nil,
            accountEmail: email.account_email,
            sender: email.sender,
            senderName: email.sender_name,
            subject: email.subject,
            snippet: email.snippet,
            receivedAt: email.received_at,
            type: itemType(for: section),
            section: section,
            summary: llmItem.summary,
            actionItems: llmItem.actionItems ?? [],
            sourceLabel: llmItem.sourceLabel
        )
    }

    private static func itemType(for section: BriefingSectionKind) -> BriefingItemType {
        switch section {
        case .urgentToday:
            return .urgentNotification
        case .criticalReminders:
            return .calendarInvite
        case .unreadFromYesterday:
            return .directCommunication
        case .receiptsAndTransactions:
            return .receipt
        }
    }
}
