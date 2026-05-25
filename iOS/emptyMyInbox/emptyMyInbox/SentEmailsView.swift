//
//  SentEmailsView.swift
//  emptyMyInbox
//
//  Sent emails — unified mailbox list.
//

import SwiftUI
import EmptyMyInboxShared

struct SentEmailsView: View {
    var body: some View {
        MailboxListView(
            scope: .sent,
            refreshStrategy: .dashboardSync
        )
    }
}

#Preview {
    SentEmailsView()
}
