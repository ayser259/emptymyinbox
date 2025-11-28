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
                                NavigationLink(destination: EmailDetailView(emailId: email.id)) {
                                    GmailStyleEmailRow(email: email)
                                }
                                .buttonStyle(PlainButtonStyle())
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
        
        // Try loading from cache first
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            await MainActor.run {
                self.emails = snapshot.starredEmails
                self.lastRefreshTime = snapshot.timestamp
                if let mostRecent = snapshot.starredEmails.first {
                    self.mostRecentEmailTime = parseDate(mostRecent.received_at)
                }
            }
        }
        
        // Then refresh from Gmail
        await refreshStarredEmails()
    }
    
    private func refreshStarredEmails() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        let gmailService = GmailAPIService.shared
        let accounts = gmailService.getAllAccounts()
        
        var allStarredEmails: [EmailListItem] = []
        
        for account in accounts {
            do {
                let starredEmails = try await gmailService.syncStarredEmails(for: account, maxResults: 500)
                allStarredEmails.append(contentsOf: starredEmails)
            } catch {
                print("Error syncing starred emails for \(account.email): \(error)")
            }
        }
        
        // Sort by received_at descending
        allStarredEmails.sort { $0.received_at > $1.received_at }
        
        await MainActor.run {
            self.emails = allStarredEmails
            self.lastRefreshTime = Date()
            if let mostRecent = allStarredEmails.first {
                self.mostRecentEmailTime = parseDate(mostRecent.received_at)
            }
        }
        
        // Update dashboard cache
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            let updatedSnapshot = DashboardDataSnapshot(
                timestamp: snapshot.timestamp,
                accounts: snapshot.accounts,
                emails: snapshot.emails,
                allEmails: snapshot.allEmails,
                starredEmails: allStarredEmails,
                labels: snapshot.labels
            )
            await DashboardCache.shared.saveSnapshot(updatedSnapshot)
            
            // Notify dashboard to update its counts
            await MainActor.run {
                NotificationCenter.default.post(name: .dashboardNeedsUpdate, object: nil)
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

