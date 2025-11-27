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
    @State private var errorMessage: String?
    @State private var lastRefreshTime: Date?
    @State private var mostRecentEmailTime: Date?
    @State private var selectedEmailIds: Set<Int> = []
    @State private var editMode: EditMode = .inactive
    @State private var isProcessing = false
    @State private var accounts: [EmailAccount] = []
    
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
                                    HStack(spacing: AppTheme.spacingMedium) {
                                        if editMode == .active {
                                            Button {
                                                toggleSelection(for: email.id)
                                            } label: {
                                                Image(systemName: selectedEmailIds.contains(email.id) ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(selectedEmailIds.contains(email.id) ? AppTheme.accent : AppTheme.secondaryText.opacity(0.5))
                                                    .font(.system(size: 22))
                                                    .frame(width: 30)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        
                                        GmailStyleEmailRow(email: email)
                                            .opacity(editMode == .active && !selectedEmailIds.contains(email.id) ? 0.6 : 1.0)
                                    }
                                    .padding(.horizontal, AppTheme.spacingMedium)
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding(.vertical, AppTheme.spacingSmall)
                        }
                    }
                .refreshable {
                    await performManualRefresh()
                }
                }
            }
            .navigationTitle("All Emails")
            .navigationBarTitleDisplayMode(.large)
            .customBackButton()
            .primaryBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if editMode == .inactive {
                        Button {
                            editMode = .active
                        } label: {
                            Text("Select")
                        }
                    } else {
                        HStack {
                            if !selectedEmailIds.isEmpty {
                                Button {
                                    Task {
                                        await markSelectedAsUnread()
                                    }
                                } label: {
                                    Image(systemName: "envelope.badge")
                                        .foregroundColor(AppTheme.accent)
                                }
                                .disabled(isProcessing)
                            }
                            
                            Button {
                                selectedEmailIds.removeAll()
                                editMode = .inactive
                            } label: {
                                Text("Done")
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
        .task {
            await loadCachedEmails()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshDashboard"))) { _ in
            Task {
                await loadCachedEmails()
            }
        }
    }
    
    private func loadCachedEmails() async {
        isLoading = true
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            await MainActor.run {
                applySnapshot(snapshot)
                errorMessage = nil
            }
        }
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func performManualRefresh() async {
        if let snapshot = await DashboardDataManager.shared.refreshData(shouldSync: true) {
            await MainActor.run {
                applySnapshot(snapshot)
                errorMessage = nil
            }
            NotificationCenter.default.post(name: NSNotification.Name("RefreshDashboard"), object: nil)
        } else {
            await MainActor.run {
                self.errorMessage = "Failed to refresh. Please try again."
            }
        }
    }
    
    private func applySnapshot(_ snapshot: DashboardDataSnapshot) {
        self.emails = snapshot.allEmails
        self.accounts = snapshot.accounts
        self.lastRefreshTime = snapshot.timestamp
        if let mostRecent = snapshot.allEmails.first {
            self.mostRecentEmailTime = parseDate(mostRecent.received_at)
        } else {
            self.mostRecentEmailTime = nil
        }
    }
    
    private func toggleSelection(for emailId: Int) {
        if selectedEmailIds.contains(emailId) {
            selectedEmailIds.remove(emailId)
        } else {
            selectedEmailIds.insert(emailId)
        }
    }
    
    private func getAccountId(for accountEmail: String) -> Int? {
        return accounts.first(where: { $0.email == accountEmail })?.id
    }
    
    private func markSelectedAsUnread() async {
        guard !selectedEmailIds.isEmpty, !isProcessing else { return }
        
        isProcessing = true
        defer { 
            Task { @MainActor in
                isProcessing = false
                selectedEmailIds.removeAll()
                editMode = .inactive
            }
        }
        
        let emailIds = Array(selectedEmailIds)
        var successfulIds: [Int] = []
        
        // Mark each email as unread
        for emailId in emailIds {
            do {
                _ = try await APIService.shared.markEmailAsUnread(emailId: emailId)
                
                // Get account ID for this email
                let email = emails.first { $0.id == emailId }
                let accountId = email.flatMap { getAccountId(for: $0.account_email) }
                
                // Update local cache
                await DashboardDataManager.shared.markEmailAsUnread(emailId: emailId, accountId: accountId)
                
                successfulIds.append(emailId)
            } catch {
                print("Error marking email \(emailId) as unread: \(error)")
            }
        }
        
        // Refresh the email list
        await MainActor.run {
            NotificationCenter.default.post(name: NSNotification.Name("RefreshDashboard"), object: nil)
        }
        
        await loadCachedEmails()
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
        let calendar = Calendar.current
        let now = Date()
        
        // If refreshed within the last minute, show "just now"
        if calendar.dateComponents([.second], from: date, to: now).second ?? 0 < 60 {
            return "just now"
        }
        
        // If refreshed today, show time
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Today at \(timeFormatter.string(from: date))"
        }
        
        // If refreshed yesterday, show yesterday and time
        if calendar.isDateInYesterday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Yesterday at \(timeFormatter.string(from: date))"
        }
        
        // Otherwise show full date and time
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: date)
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
            await loadCachedEmails()
        }
        .refreshable {
            await refreshEmails()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshDashboard"))) { _ in
            Task {
                await loadCachedEmails()
            }
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
            NotificationCenter.default.post(name: NSNotification.Name("RefreshDashboard"), object: nil)
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

