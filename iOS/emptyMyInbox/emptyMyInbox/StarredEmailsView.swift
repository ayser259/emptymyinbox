//
//  StarredEmailsView.swift
//  emptyMyInbox
//
//  View for displaying all starred emails
//

import SwiftUI

struct StarredEmailsView: View {
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
                        Image(systemName: "star")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.secondaryText)
                            .padding()
                        
                        Text("No starred emails")
                            .font(AppTheme.title3)
                            .primaryText()
                        
                        Text("Star emails to save them for later")
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
                        await refreshStarredEmails()
                    }
                }
            }
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.large)
        .primaryBackground()
        .task {
            await loadStarredEmails()
        }
    }
    
    private func loadStarredEmails() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let fetchedEmails = try await APIService.shared.getStarredEmails()
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
    
    private func refreshStarredEmails() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        do {
            // Sync all accounts first
            let syncResponse = try await APIService.shared.syncAllAccounts()
            
            // Then reload starred emails
            let fetchedEmails = try await APIService.shared.getStarredEmails()
            
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
    StarredEmailsView()
}

