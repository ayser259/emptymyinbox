//
//  EmailThreadGrouping.swift
//  EmptyMyInboxShared
//
//  Group flat message lists into Gmail-style thread summaries.
//

import Foundation

public enum EmailThreadGrouping {
    /// Group messages into thread summaries, newest thread first.
    public static func summarizeThreads(from emails: [EmailListItem]) -> [EmailThreadSummary] {
        guard !emails.isEmpty else { return [] }

        var groups: [String: [EmailListItem]] = [:]

        for email in emails {
            let groupKey = groupingKey(for: email)
            groups[groupKey, default: []].append(email)
        }

        let summaries = groups.values.compactMap { group -> EmailThreadSummary? in
            guard let latest = latestMessage(in: group) else { return nil }
            let key = threadKey(for: latest, group: group)
            let unreadCount = group.filter { !$0.is_read }.count
            return EmailThreadSummary(
                key: key,
                latestMessage: latest,
                unreadCount: unreadCount,
                messageCount: group.count,
                messageIds: group.map(\.id),
                gmailMessageIds: group.map(\.gmail_id)
            )
        }

        return summaries.sorted { lhs, rhs in
            let left = EmailListItemDisplay.parseReceivedAt(lhs.latestMessage.received_at) ?? .distantPast
            let right = EmailListItemDisplay.parseReceivedAt(rhs.latestMessage.received_at) ?? .distantPast
            return left > right
        }
    }

    /// Group metadata into Catch Up thread deck items (unread threads only).
    public static func catchUpThreads(
        from metadata: [EmailMetadata],
        accountOrder: [String] = []
    ) -> [CatchUpThreadItem] {
        let unread = metadata.filter { metadata in
            metadata.labels.contains("UNREAD")
                && metadata.labels.contains("INBOX")
                && !metadata.labels.contains("STARRED")
        }

        var groups: [String: [EmailMetadata]] = [:]
        for item in unread {
            let key = metadataGroupingKey(for: item)
            groups[key, default: []].append(item)
        }

        var items: [CatchUpThreadItem] = []
        for group in groups.values {
            guard let latestMeta = latestMetadata(in: group) else { continue }
            let listItems = group.map { $0.toEmailListItem() }
            guard let latestList = latestMessage(in: listItems) else { continue }
            let key = threadKey(for: latestList, group: listItems)
            let summary = EmailThreadSummary(
                key: key,
                latestMessage: latestList,
                unreadCount: group.count,
                messageCount: group.count,
                messageIds: group.map(\.id),
                gmailMessageIds: group.map(\.gmail_id)
            )
            items.append(CatchUpThreadItem(
                key: key,
                summary: summary,
                unreadMetadata: group.sorted { lhs, rhs in
                    lhs.received_at > rhs.received_at
                }
            ))
        }

        if accountOrder.isEmpty {
            return items.sorted { lhs, rhs in
                let left = EmailListItemDisplay.parseReceivedAt(lhs.summary.latestMessage.received_at) ?? .distantPast
                let right = EmailListItemDisplay.parseReceivedAt(rhs.summary.latestMessage.received_at) ?? .distantPast
                return left > right
            }
        }

        return items.sorted { lhs, rhs in
            let ai = accountOrder.firstIndex(of: lhs.key.accountEmail) ?? accountOrder.count
            let bi = accountOrder.firstIndex(of: rhs.key.accountEmail) ?? accountOrder.count
            if ai != bi { return ai < bi }
            let left = EmailListItemDisplay.parseReceivedAt(lhs.summary.latestMessage.received_at) ?? .distantPast
            let right = EmailListItemDisplay.parseReceivedAt(rhs.summary.latestMessage.received_at) ?? .distantPast
            return left > right
        }
    }

    // MARK: - Private

    private static func groupingKey(for email: EmailListItem) -> String {
        let account = email.account_email.lowercased()
        if !email.thread_id.isEmpty {
            return "\(account)|thread|\(email.thread_id)"
        }
        return "\(account)|message|\(email.gmail_id)"
    }

    private static func metadataGroupingKey(for metadata: EmailMetadata) -> String {
        let account = metadata.account_email.lowercased()
        if !metadata.thread_id.isEmpty {
            return "\(account)|thread|\(metadata.thread_id)"
        }
        return "\(account)|message|\(metadata.gmail_id)"
    }

    private static func threadKey(for latest: EmailListItem, group: [EmailListItem]) -> EmailThreadKey {
        if !latest.thread_id.isEmpty {
            return EmailThreadKey(accountEmail: latest.account_email, threadId: latest.thread_id)
        }
        return EmailThreadKey(accountEmail: latest.account_email, threadId: latest.gmail_id)
    }

    private static func latestMessage(in group: [EmailListItem]) -> EmailListItem? {
        group.max { lhs, rhs in
            let left = EmailListItemDisplay.parseReceivedAt(lhs.received_at) ?? .distantPast
            let right = EmailListItemDisplay.parseReceivedAt(rhs.received_at) ?? .distantPast
            return left < right
        }
    }

    private static func latestMetadata(in group: [EmailMetadata]) -> EmailMetadata? {
        group.max { lhs, rhs in
            lhs.received_at < rhs.received_at
        }
    }
}
