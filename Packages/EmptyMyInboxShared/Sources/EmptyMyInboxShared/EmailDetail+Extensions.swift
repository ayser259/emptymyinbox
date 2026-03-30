//
//  EmailDetail+Extensions.swift
//  emptyMyInbox
//
//  Convenience helpers for immutably updating email details.
//

import Foundation

public extension EmailDetail {
    public func updating(
        isRead: Bool? = nil,
        isStarred: Bool? = nil
    ) -> EmailDetail {
        EmailDetail(
            id: id,
            gmail_id: gmail_id,
            thread_id: thread_id,
            subject: subject,
            sender: sender,
            sender_name: sender_name,
            recipients_to: recipients_to,
            recipients_cc: recipients_cc,
            recipients_bcc: recipients_bcc,
            body_text: body_text,
            body_html: body_html,
            snippet: snippet,
            is_read: isRead ?? self.is_read,
            is_starred: isStarred ?? self.is_starred,
            labels: labels,
            received_at: received_at,
            account_email: account_email,
            created_at: created_at
        )
    }
}

// MARK: - Debug copy

public extension EmailDetail {
    var debugCopyContent: String {
        """
        === DEBUG EMAIL CONTENT ===

        ID: \(id)
        Gmail ID: \(gmail_id)
        Thread ID: \(thread_id)
        Account: \(account_email)

        --- HEADERS ---
        From: \(sender_name ?? "N/A") <\(sender)>
        To: \(recipients_to ?? "N/A")
        CC: \(recipients_cc ?? "N/A")
        Subject: \(subject)
        Date: \(received_at)
        Is Read: \(is_read)
        Is Starred: \(is_starred)
        Labels: \(labels.joined(separator: ", "))

        --- SNIPPET ---
        \(snippet)

        --- BODY TEXT ---
        \(body_text.isEmpty ? "(empty)" : body_text)

        --- BODY HTML ---
        \(body_html ?? "(empty)")

        === END DEBUG CONTENT ===
        """
    }
}


