//
//  EmailListItem+Extensions.swift
//  emptyMyInbox
//
//  Convenience helpers for mutating EmailListItem values immutably.
//

import Foundation

extension EmailListItem {
    func updating(isRead: Bool? = nil, isStarred: Bool? = nil, markedReadAt: String? = nil) -> EmailListItem {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // If marking as read and not already marked, set the timestamp
        let newMarkedReadAt: String?
        if let isRead = isRead, isRead && !self.is_read {
            newMarkedReadAt = markedReadAt ?? dateFormatter.string(from: Date())
        } else if let isRead = isRead, !isRead {
            // If marking as unread, clear the timestamp
            newMarkedReadAt = nil
        } else {
            newMarkedReadAt = markedReadAt ?? self.marked_read_at
        }
        
        return EmailListItem(
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
            account_email: account_email,
            marked_read_at: newMarkedReadAt
        )
    }
}


