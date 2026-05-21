//
//  EmailThreadModels.swift
//  EmptyMyInboxShared
//
//  Thread identity, summaries, and conversation state for grouped mail UX.
//

import Foundation

// MARK: - Thread key

/// Stable grouping key: one Gmail thread per account.
public struct EmailThreadKey: Hashable, Sendable, Codable {
    public let accountEmail: String
    public let threadId: String

    public init(accountEmail: String, threadId: String) {
        self.accountEmail = accountEmail
        self.threadId = threadId
    }

    public init(from item: EmailListItem) {
        accountEmail = item.account_email
        threadId = item.thread_id
    }

    public init(from metadata: EmailMetadata) {
        accountEmail = metadata.account_email
        threadId = metadata.thread_id
    }

    /// Deterministic numeric id for list selection / navigation tags.
    public var stableListId: Int {
        var hasher = Hasher()
        hasher.combine(accountEmail.lowercased())
        hasher.combine(threadId)
        return abs(hasher.finalize())
    }

    public var hasValidThreadId: Bool {
        !threadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Thread summary (list row)

public struct EmailThreadSummary: Identifiable, Sendable {
    public let key: EmailThreadKey
    /// Latest message in the group (for row display).
    public let latestMessage: EmailListItem
    public let unreadCount: Int
    public let messageCount: Int
    /// All message ids in this group (for cache updates).
    public let messageIds: [Int]
    public let gmailMessageIds: [String]

    public var id: Int { key.stableListId }

    public var threadId: String { key.threadId }
    public var accountEmail: String { key.accountEmail }

    public var isUnread: Bool { unreadCount > 0 }
}

// MARK: - Conversation (reading view)

public enum EmailThreadLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// Full thread for reading UI with action-target selection.
public struct EmailThreadConversation: Sendable {
    public let key: EmailThreadKey
    public let summary: EmailThreadSummary?
    public private(set) var messages: [EmailDetail]
    public private(set) var selectedMessageId: Int

    public init(
        key: EmailThreadKey,
        summary: EmailThreadSummary? = nil,
        messages: [EmailDetail] = [],
        selectedMessageId: Int? = nil
    ) {
        self.key = key
        self.summary = summary
        self.messages = messages.sorted { lhs, rhs in
            let left = EmailListItemDisplay.parseReceivedAt(lhs.received_at) ?? .distantPast
            let right = EmailListItemDisplay.parseReceivedAt(rhs.received_at) ?? .distantPast
            return left < right
        }
        self.selectedMessageId = selectedMessageId
            ?? EmailThreadConversation.defaultActionTargetId(in: self.messages)
    }

    public var unreadMessageIds: Set<Int> {
        Set(messages.filter { !$0.is_read }.map(\.id))
    }

    public var unreadCount: Int { unreadMessageIds.count }

    public var selectedMessage: EmailDetail? {
        messages.first { $0.id == selectedMessageId }
    }

    public var hasUnread: Bool { unreadCount > 0 }

    public mutating func selectMessage(id: Int) {
        guard messages.contains(where: { $0.id == id }) else { return }
        selectedMessageId = id
    }

    public mutating func replaceMessages(_ newMessages: [EmailDetail]) {
        messages = newMessages.sorted { lhs, rhs in
            let left = EmailListItemDisplay.parseReceivedAt(lhs.received_at) ?? .distantPast
            let right = EmailListItemDisplay.parseReceivedAt(rhs.received_at) ?? .distantPast
            return left < right
        }
        if !messages.contains(where: { $0.id == selectedMessageId }) {
            selectedMessageId = Self.defaultActionTargetId(in: messages)
        }
    }

    public mutating func updateMessage(_ detail: EmailDetail) {
        guard let index = messages.firstIndex(where: { $0.id == detail.id }) else { return }
        messages[index] = detail
    }

    public static func defaultActionTargetId(in messages: [EmailDetail]) -> Int {
        let unread = messages.filter { !$0.is_read }
        if let newestUnread = unread.max(by: { lhs, rhs in
            let left = EmailListItemDisplay.parseReceivedAt(lhs.received_at) ?? .distantPast
            let right = EmailListItemDisplay.parseReceivedAt(rhs.received_at) ?? .distantPast
            return left < right
        }) {
            return newestUnread.id
        }
        if let newest = messages.max(by: { lhs, rhs in
            let left = EmailListItemDisplay.parseReceivedAt(lhs.received_at) ?? .distantPast
            let right = EmailListItemDisplay.parseReceivedAt(rhs.received_at) ?? .distantPast
            return left < right
        }) {
            return newest.id
        }
        return messages.first?.id ?? 0
    }
}

// MARK: - Catch Up thread deck item

/// One Catch Up card = one unread thread.
public struct CatchUpThreadItem: Identifiable, Sendable {
    public let key: EmailThreadKey
    public let summary: EmailThreadSummary
    public let unreadMetadata: [EmailMetadata]

    public var id: Int { key.stableListId }

    public var unreadCount: Int { summary.unreadCount }
}
