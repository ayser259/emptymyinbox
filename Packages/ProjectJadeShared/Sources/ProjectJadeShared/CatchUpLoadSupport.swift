//
//  CatchUpLoadSupport.swift
//  ProjectJadeShared
//
//  Pure helpers for Catch Up unread backlog loading (testable without Gmail I/O).
//

import Foundation

public enum CatchUpLoadSupport {
    public static let defaultUnreadListingCap = 2000
    public static let defaultPageSize = 500
    public static let metadataBatchSize = 10
    public static let metadataBatchMaxRetries = 3

    /// Whether an inbox list item belongs in the Catch Up deck.
    public static func isCatchUpEligible(_ item: EmailListItem) -> Bool {
        !item.is_read
            && item.labels.contains("INBOX")
            && item.labels.contains("UNREAD")
            && !item.is_starred
    }

    /// Whether metadata belongs in the Catch Up deck.
    public static func isCatchUpEligible(_ metadata: EmailMetadata) -> Bool {
        metadata.labels.contains("UNREAD")
            && metadata.labels.contains("INBOX")
            && !metadata.labels.contains("STARRED")
    }

    /// Seed Catch Up metadata from the dashboard unread snapshot.
    public static func seedMetadata(
        from snapshot: DashboardDataSnapshot,
        accountEmail: String?,
        allowedAccountEmails: Set<String>
    ) -> [EmailMetadata] {
        snapshot.emails.compactMap { item -> EmailMetadata? in
            guard isCatchUpEligible(item) else { return nil }
            if let accountEmail {
                guard item.account_email == accountEmail else { return nil }
            } else if !allowedAccountEmails.contains(item.account_email) {
                return nil
            }
            return item.toEmailMetadata()
        }
    }

    /// Merge metadata arrays without duplicate Gmail IDs.
    public static func mergeUniqueMetadata(
        existing: [EmailMetadata],
        adding newItems: [EmailMetadata]
    ) -> [EmailMetadata] {
        var result = existing
        var knownIds = Set(existing.map(\.gmail_id))
        for item in newItems where knownIds.insert(item.gmail_id).inserted {
            result.append(item)
        }
        return result
    }

    /// Message refs that still need a metadata fetch.
    public static func messageRefsNeedingMetadata(
        refs: [(account: GmailAccount, id: String, threadId: String)],
        existingMetadata: [EmailMetadata]
    ) -> [(account: GmailAccount, id: String, threadId: String)] {
        let knownIds = Set(existingMetadata.map(\.gmail_id))
        return refs.filter { !knownIds.contains($0.id) }
    }

    /// Accumulate paginated Gmail message refs up to a cap.
    public static func accumulateMessageRefs(
        pages: [[GmailMessageReference]],
        maxTotal: Int
    ) -> [GmailMessageReference] {
        var result: [GmailMessageReference] = []
        for page in pages {
            for ref in page {
                guard result.count < maxTotal else { return result }
                result.append(ref)
            }
        }
        return result
    }

    /// Exponential backoff delay before retrying a failed metadata batch.
    public static func metadataBatchRetryDelayNanoseconds(attempt: Int) -> UInt64 {
        guard attempt > 0 else { return 0 }
        let seconds = pow(2.0, Double(attempt - 1)) * 0.5
        return UInt64(seconds * 1_000_000_000)
    }

    /// Whether Catch Up should defer live Gmail fetches while dashboard sync is likely still running.
    public static func shouldDeferLiveFetch(snapshotTimestamp: Date?, now: Date = Date()) -> Bool {
        guard let snapshotTimestamp else { return false }
        return now.timeIntervalSince(snapshotTimestamp) < 30
    }

    /// Delay before starting live metadata fetches after a very recent snapshot seed.
    public static func liveFetchDeferDelayNanoseconds(snapshotTimestamp: Date?, now: Date = Date()) -> UInt64 {
        shouldDeferLiveFetch(snapshotTimestamp: snapshotTimestamp, now: now) ? 1_000_000_000 : 0
    }

    /// Merge unread messages into an inbox list so buried unread appear in `allEmails`.
    public static func mergeUnreadIntoAllEmails(
        inboxEmails: [EmailListItem],
        unreadEmails: [EmailListItem]
    ) -> [EmailListItem] {
        var byGmailId: [String: EmailListItem] = [:]
        for item in inboxEmails {
            byGmailId[item.gmail_id] = item
        }
        for item in unreadEmails {
            byGmailId[item.gmail_id] = item
        }
        return byGmailId.values.sorted { lhs, rhs in
            let left = EmailListItemDisplay.parseReceivedAt(lhs.received_at) ?? .distantPast
            let right = EmailListItemDisplay.parseReceivedAt(rhs.received_at) ?? .distantPast
            return left > right
        }
    }

    /// Non-starred unread count for display, preferring Gmail's INBOX unread while local sync catches up.
    public static func displayUnreadCount(localNonStarred: Int, gmailInboxUnread: Int?) -> Int {
        guard let gmailInboxUnread else { return localNonStarred }
        return max(localNonStarred, gmailInboxUnread)
    }

    /// Count non-starred unread emails for an account from the unread snapshot list.
    public static func localUnreadCount(for accountEmail: String, in emails: [EmailListItem]) -> Int {
        emails.filter {
            $0.account_email.lowercased() == accountEmail.lowercased()
                && isCatchUpEligible($0)
        }.count
    }
}
