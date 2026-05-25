//
//  MailboxScope.swift
//  EmptyMyInboxShared
//
//  Shared mailbox scope and read-filter semantics for inbox list surfaces.
//

import Foundation

/// Which mailbox collection to show (Saved, All Emails, All Unread, per-account).
public enum MailboxScope: Hashable, Sendable {
    case all
    case allUnread
    case saved
    case sent
    case account(email: String)
    case accountSaved(email: String)
    case accountSent(email: String)
}

/// Optional read-state filter applied on top of a mailbox scope.
public enum MailboxReadFilter: String, CaseIterable, Sendable {
    case all = "All"
    case unread = "Unread"
    case read = "Read"
}

public enum MailboxQuery {
    /// Returns emails for the given scope and read filter, sorted newest-first.
    public static func emails(
        in snapshot: DashboardDataSnapshot,
        scope: MailboxScope,
        readFilter: MailboxReadFilter = .all
    ) -> [EmailListItem] {
        let scoped = scopedEmails(in: snapshot, scope: scope)
        let filtered = apply(readFilter: readFilter, to: scoped, scope: scope)
        return EmailListItemSort.receivedAtDescending(filtered)
    }

    /// Base collection for a scope before read filtering.
    public static func scopedEmails(
        in snapshot: DashboardDataSnapshot,
        scope: MailboxScope
    ) -> [EmailListItem] {
        switch scope {
        case .all:
            return snapshot.allEmails
        case .allUnread:
            // Authoritative unread-only list built during refresh.
            return snapshot.emails
        case .saved:
            return snapshot.starredEmails
        case .sent:
            return snapshot.sentEmails
        case .account(let email):
            return snapshot.allEmails.filter {
                $0.account_email.caseInsensitiveCompare(email) == .orderedSame
            }
        case .accountSaved(let email):
            return snapshot.starredEmails.filter {
                $0.account_email.caseInsensitiveCompare(email) == .orderedSame
            }
        case .accountSent(let email):
            return snapshot.sentEmails.filter {
                $0.account_email.caseInsensitiveCompare(email) == .orderedSame
            }
        }
    }

    private static func apply(
        readFilter: MailboxReadFilter,
        to emails: [EmailListItem],
        scope: MailboxScope
    ) -> [EmailListItem] {
        if case .allUnread = scope {
            return emails
        }
        switch readFilter {
        case .all:
            return emails
        case .unread:
            return emails.filter { !$0.is_read }
        case .read:
            return emails.filter(\.is_read)
        }
    }
}

public enum EmailListItemSort {
    public static func receivedAtDescending(_ emails: [EmailListItem]) -> [EmailListItem] {
        emails.sorted { lhs, rhs in
            let left = EmailListItemDisplay.parseReceivedAt(lhs.received_at) ?? .distantPast
            let right = EmailListItemDisplay.parseReceivedAt(rhs.received_at) ?? .distantPast
            return left > right
        }
    }
}

// MARK: - Thread list queries

public enum MailboxThreadQuery {
    /// Thread summaries for a mailbox scope, newest thread first.
    public static func threads(
        in snapshot: DashboardDataSnapshot,
        scope: MailboxScope,
        readFilter: MailboxReadFilter = .all
    ) -> [EmailThreadSummary] {
        let emails = MailboxQuery.emails(in: snapshot, scope: scope, readFilter: readFilter)
        return EmailThreadGrouping.summarizeThreads(from: emails)
    }
}
