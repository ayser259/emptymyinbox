//
//  StarredEmailsView.swift
//  ProjectJade
//
//  Saved (starred) emails — unified mailbox list.
//

import SwiftUI
import ProjectJadeShared

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
