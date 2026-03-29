//
//  EmailListView.swift
//  emptyMyInbox
//
//  View for displaying and managing emails
//

import SwiftUI
import EmptyMyInboxShared

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
            
            mainContent
        }
        .navigationTitle("All Emails")
        .navigationBarTitleDisplayMode(.large)
        .customBackButton()
        .primaryBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if editMode == .active {
                        Button {
                            if selectedEmailIds.count == emails.count {
                                selectedEmailIds.removeAll()
                            } else {
                                selectAllEmails()
                            }
                        } label: {
                            Text(selectedEmailIds.count == emails.count ? "Deselect All" : "Select All")
                        }
                        .textButton()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if editMode == .inactive {
                        Button {
                            editMode = .active
                        } label: {
                            Text("Select")
                        }
                        .textButton()
                    } else {
                        Button {
                            selectedEmailIds.removeAll()
                            editMode = .inactive
                        } label: {
                            Text("Cancel")
                        }
                        .textButton()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if editMode == .active && !selectedEmailIds.isEmpty {
                    selectionActionBar
                }
            }
            .environment(\.editMode, $editMode)
        .task {
            await loadCachedEmails()
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
    
    @ViewBuilder
    private var mainContent: some View {
        if isLoading && emails.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if emails.isEmpty {
            emptyStateView
        } else {
            emailListView
        }
    }
    
    private var emptyStateView: some View {
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
    }
    
    private var emailListView: some View {
        ScrollView {
            VStack(spacing: 0) {
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
                        emailRowView(for: email)
                    }
                }
                .padding(.vertical, AppTheme.spacingSmall)
            }
        }
        .refreshable {
            await performManualRefresh()
        }
    }
    
    private func emailRowView(for email: EmailListItem) -> some View {
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
            
            if editMode == .active {
                GmailStyleEmailRow(email: email)
                    .opacity(!selectedEmailIds.contains(email.id) ? 0.6 : 1.0)
            } else {
                NavigationLink(destination: EmailDetailView(emailId: email.id)) {
                    GmailStyleEmailRow(email: email)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, 4)
    }
    
    private func toggleSelection(for emailId: Int) {
        if selectedEmailIds.contains(emailId) {
            selectedEmailIds.remove(emailId)
        } else {
            selectedEmailIds.insert(emailId)
        }
    }
    
    private func selectAllEmails() {
        selectedEmailIds = Set(emails.map { $0.id })
    }
    
    private var selectionActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppTheme.secondaryText.opacity(0.3))
            
            VStack(spacing: AppTheme.spacingSmall) {
                // Selection count - now on its own line
                HStack {
                    Text("\(selectedEmailIds.count) selected")
                        .font(AppTheme.subheadline)
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, AppTheme.spacingMedium)
                .padding(.top, AppTheme.spacingSmall)
                
                // Scrollable action buttons carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Mark as Read button
                        Button {
                            Task {
                                await markSelectedAsRead()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "envelope.open")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Mark Read")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(AppTheme.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppTheme.secondaryBackground)
                            .cornerRadius(20)
                        }
                        .disabled(isProcessing)
                        
                        // Mark as Unread button
                        Button {
                            Task {
                                await markSelectedAsUnread()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "envelope.badge")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Mark Unread")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(AppTheme.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppTheme.secondaryBackground)
                            .cornerRadius(20)
                        }
                        .disabled(isProcessing)
                        
                        // Remove from Device button
                        Button {
                            Task {
                                await deleteSelectedLocally()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "iphone.slash")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Remove from Device")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppTheme.secondaryBackground)
                            .cornerRadius(20)
                        }
                        .disabled(isProcessing)
                    }
                    .padding(.horizontal, AppTheme.spacingMedium)
                }
                .padding(.bottom, AppTheme.spacingSmall)
            }
            .background(AppTheme.primaryBackground)
        }
    }
    
    private func getAccountId(for accountEmail: String) -> Int? {
        return accounts.first(where: { $0.email == accountEmail })?.id
    }
    
    private func markSelectedAsRead() async {
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
        
        // Queue-first write model: enqueue intent and update local snapshot.
        for emailId in emailIds {
            guard let email = emails.first(where: { $0.id == emailId }) else {
                continue
            }
            await EmailActionSynchronizer.shared.enqueueMarkRead(
                emailId: emailId,
                gmailId: email.gmail_id,
                accountEmail: email.account_email
            )
            await DashboardDataManager.shared.markEmailAsRead(emailId: emailId)
        }
        
        // Refresh the email list
        await loadCachedEmails()
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
        
        // Queue-first write model: enqueue intent and update local snapshot.
        for emailId in emailIds {
            guard let email = emails.first(where: { $0.id == emailId }) else {
                continue
            }
            await EmailActionSynchronizer.shared.enqueueMarkUnread(
                emailId: emailId,
                gmailId: email.gmail_id,
                accountEmail: email.account_email
            )
            let accountId = getAccountId(for: email.account_email)
            await DashboardDataManager.shared.markEmailAsUnread(emailId: emailId, accountId: accountId)
        }
        
        // Refresh the email list
        await loadCachedEmails()
    }
    
    private func deleteSelectedLocally() async {
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
        
        // Delete emails locally only (doesn't affect Gmail inbox)
        guard let snapshot = await DashboardCache.shared.loadSnapshot() else {
            return
        }
        
        // Remove selected emails from all lists
        let updatedEmails = snapshot.emails.filter { !emailIds.contains($0.id) }
        let updatedAllEmails = snapshot.allEmails.filter { !emailIds.contains($0.id) }
        let updatedStarredEmails = snapshot.starredEmails.filter { !emailIds.contains($0.id) }
        
        // Save updated snapshot
        await DashboardCache.shared.saveSnapshot(
            accounts: snapshot.accounts,
            emails: updatedEmails,
            allEmails: updatedAllEmails,
            starredEmails: updatedStarredEmails,
            labels: snapshot.labels
        )
        
        // Remove from EmailCache unread emails (for CatchUpView and other features)
        // Remove from default unread cache
        var defaultMetadata = await EmailCache.shared.loadEmailMetadata(accountId: nil)
        defaultMetadata = defaultMetadata.filter { !emailIds.contains($0.id) }
        await EmailCache.shared.saveEmailMetadata(defaultMetadata, accountId: nil)
        
        // Remove from account-specific unread caches
        for account in accounts {
            var accountMetadata = await EmailCache.shared.loadEmailMetadata(accountId: account.id)
            accountMetadata = accountMetadata.filter { !emailIds.contains($0.id) }
            await EmailCache.shared.saveEmailMetadata(accountMetadata, accountId: account.id)
        }
        
        // Delete full email details from persistent cache (batch delete for efficiency)
        await EmailCache.shared.deleteEmailDetails(emailIds: emailIds)
        
        // Refresh the email list
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

