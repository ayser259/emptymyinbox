//
//  EmailListItem+Extensions.swift
//  emptyMyInbox
//
//  Convenience helpers for mutating EmailListItem values immutably.
//

import Foundation

public extension EmailListItem {
    public func updating(isRead: Bool? = nil, isStarred: Bool? = nil, markedReadAt: String? = nil) -> EmailListItem {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var updatedLabels = labels
        
        if let isRead {
            if isRead {
                updatedLabels.removeAll { $0 == "UNREAD" }
            } else if !updatedLabels.contains("UNREAD") {
                updatedLabels.append("UNREAD")
            }
        }
        
        if let isStarred {
            if isStarred {
                if !updatedLabels.contains("STARRED") {
                    updatedLabels.append("STARRED")
                }
            } else {
                updatedLabels.removeAll { $0 == "STARRED" }
            }
        }
        
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
            thread_id: thread_id,
            subject: subject,
            sender: sender,
            sender_name: sender_name,
            snippet: snippet,
            is_read: isRead ?? self.is_read,
            is_starred: isStarred ?? self.is_starred,
            labels: updatedLabels,
            received_at: received_at,
            account_email: account_email,
            marked_read_at: newMarkedReadAt
        )
    }
    
    /// Convert to EmailMetadata for modern cache operations
    func toEmailMetadata() -> EmailMetadata {
        EmailMetadata(
            id: id,
            gmail_id: gmail_id,
            thread_id: thread_id,
            subject: subject,
            sender: sender,
            sender_name: sender_name,
            snippet: snippet,
            is_read: is_read,
            is_starred: is_starred,
            labels: labels,
            received_at: received_at,
            account_email: account_email
        )
    }
}


