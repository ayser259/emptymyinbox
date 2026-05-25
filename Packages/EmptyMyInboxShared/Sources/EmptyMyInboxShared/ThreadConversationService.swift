//
//  ThreadConversationService.swift
//  EmptyMyInboxShared
//
//  Loads full Gmail threads with cache-first behavior.
//

import Foundation
import Combine

@MainActor
public final class ThreadConversationService: ObservableObject {
    public static let shared = ThreadConversationService()

    private let gmailService = GmailAPIService.shared
    private var inflight: [EmailThreadKey: Task<[EmailDetail], Error>] = [:]

    private init() {}

    /// Load conversation: cache hits first, then Gmail thread API.
    public func loadConversation(
        key: EmailThreadKey,
        summary: EmailThreadSummary? = nil,
        knownMessages: [EmailDetail] = []
    ) async throws -> EmailThreadConversation {
        if !key.hasValidThreadId {
            let messages = knownMessages.isEmpty ? await loadKnownFromCache(key: key, summary: summary) : knownMessages
            var conversation = EmailThreadConversation(key: key, summary: summary, messages: messages)
            return conversation
        }

        if let existing = inflight[key] {
            let messages = try await existing.value
            return EmailThreadConversation(key: key, summary: summary, messages: messages)
        }

        let task = Task<[EmailDetail], Error> {
            try await self.fetchFullThread(key: key, summary: summary, seed: knownMessages)
        }
        inflight[key] = task
        defer { inflight[key] = nil }

        let messages = try await task.value
        return EmailThreadConversation(key: key, summary: summary, messages: messages)
    }

    /// Refresh an existing conversation from Gmail.
    public func refreshConversation(_ conversation: EmailThreadConversation) async throws -> EmailThreadConversation {
        var updated = conversation
        let messages = try await fetchFullThread(
            key: conversation.key,
            summary: conversation.summary,
            seed: conversation.messages
        )
        updated.replaceMessages(messages)
        if let target = conversation.selectedMessage,
           messages.contains(where: { $0.id == target.id }) {
            updated.selectMessage(id: target.id)
        }
        return updated
    }

    // MARK: - Fetch

    private func fetchFullThread(
        key: EmailThreadKey,
        summary: EmailThreadSummary?,
        seed: [EmailDetail]
    ) async throws -> [EmailDetail] {
        guard key.hasValidThreadId,
              let account = gmailService.getAccount(byEmail: key.accountEmail) else {
            return seed.isEmpty ? await loadKnownFromCache(key: key, summary: summary) : seed
        }

        var cached: [EmailDetail] = []
        if let summary {
            for messageId in summary.messageIds {
                if let detail = await EmailCache.shared.loadEmailDetail(emailId: messageId) {
                    cached.append(detail)
                }
            }
        }
        for detail in seed where !cached.contains(where: { $0.id == detail.id }) {
            cached.append(detail)
        }

        do {
            let remote = try await gmailService.loadThreadConversation(
                for: account,
                threadId: key.threadId
            )
            await EmailCache.shared.saveEmailDetails(remote)
            return remote
        } catch {
            if !cached.isEmpty {
                logError("ThreadConversationService: Gmail fetch failed, using cache: \(error)", category: "Email")
                return cached.sorted { lhs, rhs in
                    let left = EmailListItemDisplay.parseReceivedAt(lhs.received_at) ?? .distantPast
                    let right = EmailListItemDisplay.parseReceivedAt(rhs.received_at) ?? .distantPast
                    return left < right
                }
            }
            throw error
        }
    }

    private func loadKnownFromCache(
        key: EmailThreadKey,
        summary: EmailThreadSummary?
    ) async -> [EmailDetail] {
        guard let summary else { return [] }
        var results: [EmailDetail] = []
        for messageId in summary.messageIds {
            if let detail = await EmailCache.shared.loadEmailDetail(emailId: messageId) {
                results.append(detail)
            }
        }
        return results.sorted { lhs, rhs in
            let left = EmailListItemDisplay.parseReceivedAt(lhs.received_at) ?? .distantPast
            let right = EmailListItemDisplay.parseReceivedAt(rhs.received_at) ?? .distantPast
            return left < right
        }
    }
}
