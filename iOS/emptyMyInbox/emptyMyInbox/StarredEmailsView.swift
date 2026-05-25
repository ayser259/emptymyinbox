//
//  StarredEmailsView.swift
//  emptyMyInbox
//
//  Saved (starred) emails — unified mailbox list.
//

import SwiftUI
import EmptyMyInboxShared

struct StarredEmailsView: View {
    var body: some View {
        MailboxListView(
            scope: .saved,
            refreshStrategy: .starredSync,
            syncStarredOnAppear: true
        )
    }
}

#Preview {
    StarredEmailsView()
}
