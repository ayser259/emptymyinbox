//
//  EmailListView.swift
//  emptyMyInbox
//
//  View for displaying and managing emails
//

import SwiftUI

struct AllEmailsView: View {
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
                        Image(systemName: "envelope")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.secondaryText)
                            .padding()
                        
                        Text("No emails")
                            .font(AppTheme.title3)
                            .primaryText()
                        
                        Text("Your inbox is empty")
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
                        await refreshEmails()
                    }
                }
            }
            .navigationTitle("All Emails")
            .navigationBarTitleDisplayMode(.large)
            .customBackButton()
            .primaryBackground()
        .task {
            await loadEmails()
        }
    }
    
    private func loadEmails() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let fetchedEmails = try await APIService.shared.getEmails()
            await MainActor.run {
                self.emails = fetchedEmails
                self.lastRefreshTime = Date()
                // Get most recent email time
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
            
            // Then reload emails
            let fetchedEmails = try await APIService.shared.getEmails()
            
            await MainActor.run {
                self.emails = fetchedEmails
                self.lastRefreshTime = Date()
                
                // Use most recent email time from sync response or from emails
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

struct RefreshStatusView: View {
    let lastRefreshTime: Date
    let mostRecentEmailTime: Date?
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                
                Text("Last refreshed: \(formatRefreshTime(lastRefreshTime))")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                
                Spacer()
            }
            
            if let mostRecent = mostRecentEmailTime {
                HStack {
                    Image(systemName: "envelope")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                    
                    Text("Most recent: \(formatEmailTime(mostRecent))")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                    
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatRefreshTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatEmailTime(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Today at \(timeFormatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Yesterday at \(timeFormatter.string(from: date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: date)
        }
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
            await loadEmails()
        }
    }
    
    private func loadEmails() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let fetchedEmails = try await APIService.shared.getEmails()
            await MainActor.run {
                self.emails = fetchedEmails
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
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
        
        do {
            let updatedEmail: EmailDetail
            if isStarred {
                updatedEmail = try await APIService.shared.unstarEmail(emailId: email.id)
            } else {
                updatedEmail = try await APIService.shared.starEmail(emailId: email.id)
            }
            
            await MainActor.run {
                self.isStarred = updatedEmail.is_starred
                onStarChanged?()
            }
        } catch {
            print("Error toggling star: \(error)")
        }
    }
}

#Preview {
    EmailListView()
}

