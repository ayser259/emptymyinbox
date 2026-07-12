//
//  SentEmailsView.swift
//  ProjectJade
//
//  Sent emails — unified mailbox list.
//

import SwiftUI
import ProjectJadeShared

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
