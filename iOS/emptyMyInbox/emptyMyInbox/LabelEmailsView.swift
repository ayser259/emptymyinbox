//
//  LabelEmailsView.swift
//  emptyMyInbox
//
//  View for displaying emails filtered by label
//

import SwiftUI
import EmptyMyInboxShared

struct LabelEmailsView: View {
    let label: GmailLabel
    @State private var emails: [EmailListItem] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var lastRefreshTime: Date?
    @State private var mostRecentEmailTime: Date?
    
    var body: some View {
        ZStack {
            AppTheme.primaryBackground
                .ignoresSafeArea()
                
                if isLoading && emails.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if emails.isEmpty {
                    VStack {
                        Image(systemName: "tag")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.secondaryText)
                            .padding()
                        
                        Text("No emails in \(label.name)")
                            .font(AppTheme.title3)
                            .primaryText()
                        
                        Text("Emails with this label will appear here")
                            .font(AppTheme.body)
                            .secondaryText()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Refresh status header
                            if let lastRefresh = lastRefreshTime {
                                RefreshStatusView(
                                    lastRefreshTime: lastRefresh,
                                    mostRecentEmailTime: mostRecentEmailTime
                                )
                                .padding(.horizontal, AppTheme.spacingMedium)
                                .padding(.vertical, AppTheme.spacingSmall)
                            }
                            
                            // Unread count header
                            if label.unread_count > 0 {
                                HStack {
                                    Text("\(label.unread_count) unread")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppTheme.accent)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, AppTheme.spacingMedium)
                                .padding(.vertical, AppTheme.spacingSmall)
                            }
                            
                            LazyVStack(spacing: 0) {
                                ForEach(emails, id: \.id) { email in
                                    GmailStyleEmailRow(email: email)
                                        .padding(.horizontal, AppTheme.spacingMedium)
                                        .padding(.vertical, 4)
                                }
                            }
                            .padding(.vertical, AppTheme.spacingSmall)
                        }
                    }
                    .refreshable {
                        await refreshEmails()
                    }
                }
            }
        .navigationTitle(label.name)
        .navigationBarTitleDisplayMode(.large)
        .primaryBackground()
        .task {
            await loadEmails()
        }
    }
    
    private func loadEmails() async {
        isLoading = true
        defer { isLoading = false }
        
        // Try loading from cache first
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            let cachedEmails = snapshot.allEmails.filter { email in
                if label.id == "__UNCATEGORIZED__" {
                    // For uncategorized, filter emails with no user labels
                    let systemLabels = Set(["INBOX", "SENT", "DRAFT", "SPAM", "TRASH", "UNREAD", "STARRED", "IMPORTANT"])
                    let userLabels = email.labels.filter { !systemLabels.contains($0) }
                    return userLabels.isEmpty
                } else {
                    return email.labels.contains(label.id)
                }
            }
            
            await MainActor.run {
                self.emails = cachedEmails
                self.lastRefreshTime = snapshot.timestamp
                if let mostRecent = cachedEmails.first {
                    self.mostRecentEmailTime = parseDate(mostRecent.received_at)
                }
            }
        }
        
        // Then refresh from Gmail
        await refreshEmails()
    }
    
    private func refreshEmails() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        // Refresh dashboard data first
        _ = await DashboardDataManager.shared.refreshData(shouldSync: true)
        
        // Then load from updated cache
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            let filteredEmails = snapshot.allEmails.filter { email in
                if label.id == "__UNCATEGORIZED__" {
                    // For uncategorized, filter emails with no user labels
                    let systemLabels = Set(["INBOX", "SENT", "DRAFT", "SPAM", "TRASH", "UNREAD", "STARRED", "IMPORTANT"])
                    let userLabels = email.labels.filter { !systemLabels.contains($0) }
                    return userLabels.isEmpty
                } else {
                    return email.labels.contains(label.id)
                }
            }
            
            await MainActor.run {
                self.emails = filteredEmails
                self.lastRefreshTime = snapshot.timestamp
                if let mostRecent = filteredEmails.first {
                    self.mostRecentEmailTime = parseDate(mostRecent.received_at)
                }
            }
        }
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString)
    }
}

#Preview {
    let previewLabel = GmailLabel(id: "INBOX", name: "Inbox", unread_count: 5)
    return LabelEmailsView(label: previewLabel)
}

