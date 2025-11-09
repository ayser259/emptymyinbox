//
//  EmailListItem+Extensions.swift
//  emptyMyInbox
//
//  Convenience helpers for mutating EmailListItem values immutably.
//

import Foundation

extension EmailListItem {
    func updating(isRead: Bool? = nil, isStarred: Bool? = nil) -> EmailListItem {
        EmailListItem(
            id: id,
            gmail_id: gmail_id,
            subject: subject,
            sender: sender,
            sender_name: sender_name,
            snippet: snippet,
            is_read: isRead ?? self.is_read,
            is_starred: isStarred ?? self.is_starred,
            labels: labels,
            received_at: received_at,
            account_email: account_email
        )
    }
}


