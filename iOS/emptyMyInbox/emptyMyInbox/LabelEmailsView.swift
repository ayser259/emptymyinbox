//
//  LabelEmailsView.swift
//  emptyMyInbox
//
//  View for displaying emails filtered by label
//

import SwiftUI

struct LabelEmailsView: View {
    let label: Label
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
        
        do {
            let fetchedEmails = try await APIService.shared.getEmailsByLabel(labelId: label.id)
            await MainActor.run {
                self.emails = fetchedEmails
                self.lastRefreshTime = Date()
                if let mostRecent = fetchedEmails.first {
                    self.mostRecentEmailTime = parseDate(mostRecent.received_at)
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func refreshEmails() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        do {
            // Sync all accounts first
            let syncResponse = try await APIService.shared.syncAllAccounts()
            
            // Then reload emails for this label
            let fetchedEmails = try await APIService.shared.getEmailsByLabel(labelId: label.id)
            
            await MainActor.run {
                self.emails = fetchedEmails
                self.lastRefreshTime = Date()
                
                if let mostRecentTimeStr = syncResponse.most_recent_email_at {
                    self.mostRecentEmailTime = parseDate(mostRecentTimeStr)
                } else if let mostRecent = fetchedEmails.first {
                    self.mostRecentEmailTime = parseDate(mostRecent.received_at)
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
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
    LabelEmailsView(label: Label(
        id: "INBOX",
        name: "Inbox",
        unread_count: 5
    ))
}

