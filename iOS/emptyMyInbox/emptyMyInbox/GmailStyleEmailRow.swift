//
//  GmailStyleEmailRow.swift
//  emptyMyInbox
//
//  Legacy alias for the unified mailbox row.
//

import SwiftUI
import EmptyMyInboxShared

struct GmailStyleEmailRow: View {
    let email: EmailListItem

    var body: some View {
        MailboxEmailRow(email: email)
    }
}

#Preview {
    GmailStyleEmailRow(email: EmailListItem(
        id: 1,
        gmail_id: "123",
        subject: "Test Email",
        sender: "test@example.com",
        sender_name: "Test User",
        snippet: "This is a test email snippet",
        is_read: false,
        is_starred: false,
        labels: [],
        received_at: "2024-01-01T12:00:00Z",
        account_email: "user@example.com",
        marked_read_at: nil
    ))
    .padding()
    .primaryBackground()
}
