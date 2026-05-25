//
//  EmailListView.swift
//  emptyMyInbox
//
//  View for displaying and managing emails
//

import SwiftUI
import EmptyMyInboxShared

struct AllEmailsView: View {
    var body: some View {
        MailboxListView(scope: .all, allowsBulkSelection: true)
    }
}

struct RefreshStatusView: View {
    let lastRefreshTime: Date
    let mostRecentEmailTime: Date?

    var body: some View {
        MailboxRefreshStatusView(
            lastRefreshTime: lastRefreshTime,
            mostRecentEmailTime: mostRecentEmailTime
        )
    }
}

struct EmailListView: View {
    @State private var emails: [EmailListItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if emails.isEmpty {
                Text("No emails")
                    .font(AppTheme.body)
                    .secondaryText()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(emails, id: \.id) { email in
                    EmailRow(email: email)
                }
            }
        }
        .primaryBackground()
        .task {
            await loadCachedEmails()
        }
        .refreshable {
            await refreshEmails()
        }
    }
    
    private func loadCachedEmails() async {
        isLoading = true
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            await MainActor.run {
                self.emails = snapshot.emails
                self.errorMessage = nil
            }
        }
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func refreshEmails() async {
        if let snapshot = await DashboardDataManager.shared.refreshData(shouldSync: true) {
            await MainActor.run {
                self.emails = snapshot.emails
                self.errorMessage = nil
            }
        } else {
            await MainActor.run {
                self.errorMessage = "Unable to refresh emails."
            }
        }
    }
}

struct EmailRow: View {
    let email: EmailListItem
    @State private var isStarred: Bool
    @State private var isUpdating = false
    var onStarChanged: (() -> Void)?
    
    init(email: EmailListItem, onStarChanged: (() -> Void)? = nil) {
        self.email = email
        self.onStarChanged = onStarChanged
        _isStarred = State(initialValue: email.is_starred)
    }
    
    var body: some View {
        HStack(spacing: AppTheme.spacingMedium) {
            // Star button
            Button {
                Task {
                    await toggleStar()
                }
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundColor(isStarred ? AppTheme.accent : AppTheme.secondaryText)
                    .font(.system(size: 18))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isUpdating)
            
            VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                Text(email.subject.isEmpty ? "(No Subject)" : email.subject)
                    .font(AppTheme.headline)
                    .primaryText()
                    .lineLimit(1)
                
                Text(email.sender_name ?? email.sender)
                    .font(AppTheme.subheadline)
                    .secondaryText()
                    .lineLimit(1)
                
                if !email.snippet.isEmpty {
                    Text(email.snippet)
                        .font(AppTheme.caption)
                        .secondaryText()
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            if !email.is_read {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, AppTheme.spacingSmall)
        .contentShape(Rectangle())
    }
    
    private func toggleStar() async {
        isUpdating = true
        defer { isUpdating = false }
        let newStarState = !isStarred
        await EmailActionSynchronizer.shared.enqueueStar(
            emailId: email.id,
            gmailId: email.gmail_id,
            accountEmail: email.account_email,
            shouldStar: newStarState
        )
        await DashboardDataManager.shared.updateEmailStarred(emailId: email.id, isStarred: newStarState)
        
        await MainActor.run {
            self.isStarred = newStarState
            onStarChanged?()
        }
    }
}

#Preview {
    EmailListView()
}

