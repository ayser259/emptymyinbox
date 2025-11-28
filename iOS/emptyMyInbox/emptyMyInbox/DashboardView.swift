//
//  DashboardView.swift
//  emptyMyInbox
//
//  Main dashboard view after login
//

import SwiftUI
import UIKit

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showMenu = false
    @State private var searchText = ""
    @State private var searchResults: [EmailListItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var accounts: [EmailAccount] = []
    @State private var emails: [EmailListItem] = []
    @State private var allEmails: [EmailListItem] = [] // All emails for sender grouping
    @State private var starredEmails: [EmailListItem] = []
    @State private var labels: [Label] = []
    @State private var isLoadingInitialCache = true
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var lastRefreshTime: Date?
    @State private var selectedLabel: Label?
    @StateObject private var progressTracker = RefreshProgressTracker()
    @State private var showProgressModal = false
    
    var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()
                
                content
            }
            .navigationDestination(for: EmailFilter.self) { filter in
                FilteredEmailsView(filter: filter)
            }
            .navigationDestination(for: Label.self) { label in
                FilteredEmailsView(filter: .category(label: label))
            }
            .navigationDestination(for: Int.self) { emailId in
                EmailDetailView(emailId: emailId)
            }
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "all_emails":
                    AllEmailsView()
                case "starred":
                    StarredEmailsView()
                case "catch_up":
                    CatchUpView()
                        .environmentObject(authManager)
                case let catchUpAccount where catchUpAccount.hasPrefix("catch_up_"):
                    if let accountIdString = catchUpAccount.components(separatedBy: "_").last,
                       let accountId = Int(accountIdString),
                       let account = accounts.first(where: { $0.id == accountId }) {
                        CatchUpView(accountId: accountId, accountEmail: account.email)
                            .environmentObject(authManager)
                    } else {
                        CatchUpView()
                            .environmentObject(authManager)
                    }
                case "senders":
                    SendersView()
                default:
                    EmptyView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showMenu) {
            MenuView()
                .environmentObject(authManager)
        }
        .task {
            await loadInitialData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CacheCleared"))) { _ in
            Task { @MainActor in
                // Clear in-memory state so UI reflects empty cache immediately
                self.accounts = []
                self.emails = []
                self.allEmails = []
                self.starredEmails = []
                self.labels = []
                self.lastRefreshTime = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appShouldRefreshData)) { _ in
            // Only refresh if not already refreshing to prevent loops
            // This is only called once per day automatically
            Task {
                await refreshDashboard(shouldSync: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccountAdded"))) { _ in
            // New account was added, refresh to show it immediately
            Task {
                await refreshDashboard(shouldSync: false)
            }
        }
        .sheet(isPresented: $showProgressModal) {
            RefreshProgressModal(progressTracker: progressTracker)
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBarSection
                searchBarSection
                
                if isSearchActive {
                    searchResultsSection
                }
                
                actionButtonsSection
                    .padding(.bottom, AppTheme.spacingMedium)
                
                accountSummaryCards
                    .padding(.bottom, AppTheme.spacingLarge)
                
                Spacer()
                    .frame(height: 100)
            }
            .padding(.horizontal, AppTheme.spacingMedium)
        }
        .refreshable {
            await refreshDashboard(shouldSync: true)
        }
    }

    private var topBarSection: some View {
        HStack(alignment: .center) {
            LogoView(size: 40)
            
            Spacer()
            
            Group {
                if let firstAccount = authManager.accounts.first {
                    ScrollingText(
                        text: greetingText(for: firstAccount),
                        font: AppTheme.headline
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    Text(greeting)
                        .font(AppTheme.headline)
                        .primaryText()
                }
            }
            
            Button {
                showMenu = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20))
                    .primaryText()
            }
            .iconButton()
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, AppTheme.spacingMedium)
    }

    private var searchBarSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.secondaryText)
            
            TextField("Jump, search, or chat", text: $searchText)
                .primaryText()
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .onChange(of: searchText) { _, newValue in
                    performSearch(query: newValue)
                }
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
        }
        .padding(AppTheme.spacingMedium)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.bottom, AppTheme.spacingMedium)
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
            HStack {
                Text("Search Results")
                    .font(AppTheme.title3)
                    .primaryText()
                
                Spacer()
                
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("\(searchResults.count) found")
                        .font(AppTheme.caption)
                        .secondaryText()
                }
            }
            .padding(.horizontal, AppTheme.spacingMedium)
            .padding(.top, AppTheme.spacingMedium)
            
            if isSearching && searchResults.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if searchResults.isEmpty && !isSearching {
                VStack(spacing: AppTheme.spacingMedium) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.secondaryText)
                    
                    Text("No results found")
                        .font(AppTheme.title3)
                        .primaryText()
                    
                    Text("Try searching with different keywords")
                        .font(AppTheme.body)
                        .secondaryText()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacingLarge)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(searchResults, id: \.id) { email in
                        NavigationLink(value: email.id) {
                            GmailStyleEmailRow(email: email)
                                .padding(.horizontal, AppTheme.spacingMedium)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical, AppTheme.spacingSmall)
            }
        }
        .padding(.bottom, AppTheme.spacingMedium)
    }

    private var actionButtonsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacingMedium) {
                if shouldPrioritizeRefreshButton {
                    refreshButton
                        .padding(.leading, AppTheme.spacingMedium)
                }
                
                NavigationLink(value: "catch_up") {
                    ActionButton(
                        title: "Catch up",
                        count: unreadCount,
                        icon: "envelope.badge"
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(value: "all_emails") {
                    ActionButton(
                        title: "All emails",
                        count: emails.count,
                        icon: "envelope"
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(value: "senders") {
                    ActionButton(
                        title: "Senders",
                        count: unreadSendersCount,
                        icon: "person.2.fill"
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(value: "starred") {
                    ActionButton(
                        title: "Saved",
                        count: savedCount,
                        icon: "star.fill"
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                ActionButton(
                    title: "Drafts",
                    count: draftsCount,
                    icon: "doc.text"
                )
                
                if !shouldPrioritizeRefreshButton {
                    refreshButton
                }
            }
            .padding(.horizontal, AppTheme.spacingMedium)
        }
    }

    private var refreshButton: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                // Set refreshing state immediately on main thread
                Task { @MainActor in
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    progressTracker.reset()
                }
                Task {
                    await refreshDashboard(shouldSync: true)
                }
            } label: {
                VStack(spacing: AppTheme.spacingSmall) {
                    if isRefreshing {
                        ProgressView()
                            .tint(AppTheme.accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 24))
                            .foregroundColor(AppTheme.accent)
                    }
                    
                    Text("Refresh")
                        .font(AppTheme.subheadline)
                        .primaryText()
                    
                    if let lastRefresh = lastRefreshTime {
                        Text(formatLastRefreshTime(lastRefresh))
                            .font(AppTheme.caption)
                            .secondaryText()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("Never")
                            .font(AppTheme.caption)
                            .secondaryText()
                    }
                }
                .frame(width: 100, height: 100)
                .background(AppTheme.secondaryBackground)
                .cornerRadius(AppTheme.cornerRadiusMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
            .disabled(isRefreshing)
            
            // Info button
            Button {
                showProgressModal = true
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.accent)
                    .background(
                        Circle()
                            .fill(AppTheme.primaryBackground)
                            .frame(width: 20, height: 20)
                    )
            }
            .offset(x: -4, y: 4)
        }
        .frame(width: 100, height: 100)
    }

    private var shouldPrioritizeRefreshButton: Bool {
        guard let lastRefreshTime else { return true }
        return Date().timeIntervalSince(lastRefreshTime) >= 3600
    }

    private var accountSummaryCards: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMedium) {
            Text("Accounts")
                .font(AppTheme.title3)
                .primaryText()
                .padding(.horizontal, AppTheme.spacingMedium)
            
            if isLoading && accounts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if accounts.isEmpty {
                Text("No accounts connected")
                    .font(AppTheme.subheadline)
                    .secondaryText()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.spacingMedium)
                    .padding(.vertical, AppTheme.spacingSmall)
            } else {
                VStack(spacing: AppTheme.spacingMedium) {
                    ForEach(accounts, id: \.id) { account in
                        AccountSummaryCard(
                            account: account,
                            unreadCount: getUnreadCount(for: account),
                            starredCount: getStarredCount(for: account),
                            lastRefreshTime: getLastRefreshTime(for: account),
                            onRefresh: {
                                await refreshAccount(accountEmail: account.email)
                            }
                        )
                    }
                }
                .padding(.horizontal, AppTheme.spacingMedium)
            }
        }
    }
    
    private func getUnreadCount(for account: EmailAccount) -> Int {
        allEmails.filter { $0.account_email == account.email && !$0.is_read }.count
    }
    
    private func getStarredCount(for account: EmailAccount) -> Int {
        starredEmails.filter { $0.account_email == account.email }.count
    }
    
    private func getLastRefreshTime(for account: EmailAccount) -> Date? {
        guard let lastSyncString = account.last_sync else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: lastSyncString)
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<21:
            return "Good evening"
        default:
            return "Good night"
        }
    }
    
    private func greetingText(for account: GmailAccount) -> String {
        if let name = account.name, !name.isEmpty {
            return "\(greeting), \(name)"
        } else {
            return greeting
        }
    }
    
    private var unreadCount: Int {
        emails.filter { !$0.is_read }.count
    }
    
    private var savedCount: Int {
        // Count all starred emails (synced separately to ensure we get all of them)
        starredEmails.count
    }
    
    private var draftsCount: Int {
        // TODO: Implement drafts count
        0
    }
    
    // MARK: - Sender Grouping
    
    // Computed property for unread senders count (used in action button)
    private var unreadSendersCount: Int {
        let unreadEmails = allEmails.filter { !$0.is_read }
        let grouped = Dictionary(grouping: unreadEmails) { email in
            email.sender
        }
        return grouped.count
    }
    
    private func formatLastRefreshTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        // If refreshed within the last minute, show "just now"
        if let seconds = calendar.dateComponents([.second], from: date, to: now).second, seconds < 60 {
            return "just now"
        }
        
        // If refreshed today, show time
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return timeFormatter.string(from: date)
        }
        
        // If refreshed yesterday, show "Yesterday"
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        // Otherwise show date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        return dateFormatter.string(from: date)
    }
    
    private func performSearch(query: String) {
        // Cancel previous search task
        searchTask?.cancel()
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedQuery.isEmpty {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        // Debounce search - wait 0.5 seconds after user stops typing
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Search in cached emails
            if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
                let filtered = snapshot.allEmails.filter { email in
                    email.subject.localizedCaseInsensitiveContains(trimmedQuery) ||
                    email.sender.localizedCaseInsensitiveContains(trimmedQuery) ||
                    email.sender_name?.localizedCaseInsensitiveContains(trimmedQuery) == true ||
                    email.snippet.localizedCaseInsensitiveContains(trimmedQuery)
                }
                
                // Check again if task was cancelled
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self.searchResults = filtered
                    self.isSearching = false
                }
            } else {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                }
            }
        }
    }
    
    private func loadInitialData() async {
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            await MainActor.run {
                applySnapshot(snapshot)
            }
        }
        await refreshDashboard(shouldSync: false)
    }
    
    private func refreshDashboard(shouldSync: Bool) async {
        // Prevent concurrent refreshes
        let currentlyRefreshing = await MainActor.run {
            return isRefreshing || isLoading
        }
        if currentlyRefreshing {
            return
        }
        
        // Set loading state (only if not already set by button tap)
        if shouldSync {
            await MainActor.run {
                if !isRefreshing {
                    isRefreshing = true
                }
                progressTracker.reset()
            }
        } else if !hasCachedData {
            await MainActor.run {
                isLoading = true
            }
        }
        
        defer {
            Task { @MainActor in
                if shouldSync {
                    isRefreshing = false
                } else {
                    isLoading = false
                }
            }
        }
        
        // Create progress callback
        let progressCallback: DashboardDataManager.ProgressCallback = { stage, status, detail, accountEmail, currentCount, totalCount in
            await MainActor.run {
                progressTracker.updateStage(stage, status: status, detail: detail, accountEmail: accountEmail, currentCount: currentCount, totalCount: totalCount)
            }
        }
        
        if let snapshot = await DashboardDataManager.shared.refreshData(shouldSync: shouldSync, progressCallback: progressCallback) {
            await MainActor.run {
                applySnapshot(snapshot)
                lastRefreshTime = snapshot.timestamp
                // Views will get updated data through their own refresh calls or manual refresh
            }
        }
    }
    
    private var hasCachedData: Bool {
        !(accounts.isEmpty && emails.isEmpty && labels.isEmpty && allEmails.isEmpty && starredEmails.isEmpty)
    }
    
    private func applySnapshot(_ snapshot: DashboardDataSnapshot) {
        self.accounts = snapshot.accounts
        self.emails = snapshot.emails
        self.allEmails = snapshot.allEmails
        self.starredEmails = snapshot.starredEmails
        self.labels = snapshot.labels
        self.lastRefreshTime = snapshot.timestamp
    }
    
    private func refreshAccount(accountEmail: String) async {
        let gmailService = GmailAPIService.shared
        let gmailAccounts = gmailService.getAllAccounts()
        
        guard let gmailAccount = gmailAccounts.first(where: { $0.email == accountEmail }) else {
            print("Account not found: \(accountEmail)")
            return
        }
        
        do {
            // Sync unread and starred emails for this account
            _ = try await gmailService.syncUnreadEmails(for: gmailAccount, maxResults: 500, usePagination: false, resetPagination: false)
            _ = try await gmailService.syncStarredEmails(for: gmailAccount, maxResults: 500)
            
            // Refresh dashboard data to update the UI
            if let snapshot = await DashboardDataManager.shared.refreshData(shouldSync: false) {
                await MainActor.run {
                    applySnapshot(snapshot)
                    lastRefreshTime = snapshot.timestamp
                }
            }
        } catch {
            print("Error refreshing account \(accountEmail): \(error.localizedDescription)")
        }
    }
}

struct ActionButton: View {
    let title: String
    let count: Int
    let icon: String
    
    var body: some View {
        VStack(spacing: AppTheme.spacingSmall) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(AppTheme.accent)
            
            Text(title)
                .font(AppTheme.subheadline)
                .primaryText()
            
            Text("\(count)")
                .font(AppTheme.caption)
                .secondaryText()
        }
        .frame(width: 100, height: 100)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct LabelRow: View {
    let label: Label
    
    var body: some View {
        HStack {
            Image(systemName: "tag.fill")
                .foregroundColor(AppTheme.accent)
                .font(.system(size: 16))
            
            Text(label.name)
                .font(AppTheme.body)
                .primaryText()
            
            Spacer()
            
            if label.unread_count > 0 {
                Text("\(label.unread_count)")
                    .font(AppTheme.subheadline)
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, AppTheme.spacingUnit)
                    .padding(.vertical, 4)
                    .background(AppTheme.accentMuted)
                    .cornerRadius(AppTheme.cornerRadiusSmall)
            }
        }
        .padding(AppTheme.spacingMedium)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct SlackStyleLabelRow: View {
    let label: Label
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Hash symbol prefix (Slack-style)
            Text("#")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                .frame(width: 16, alignment: .leading)
            
            // Label name
            Text(label.name)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(isPressed ? AppTheme.accent : AppTheme.secondaryText)
                .lineLimit(1)
            
            Spacer()
            
            // Unread count badge (Slack-style rounded badge)
            if label.unread_count > 0 {
                Text("\(label.unread_count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, label.unread_count > 99 ? 5 : 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
                    .frame(minWidth: 18, minHeight: 18)
            }
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, 4)
        .background(
            isPressed 
                ? AppTheme.secondaryBackground.opacity(0.6) 
                : Color.clear
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

struct CollapsibleSection<Content: View>: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
            // Section header with chevron
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                            .frame(width: 16)
                        
                        Text(title)
                            .font(AppTheme.caption)
                            .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                            .fontWeight(.semibold)
                            .tracking(0.5)
                        
                        Spacer()
                        
                        // Count badge
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, count > 99 ? 5 : 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent)
                                .clipShape(Capsule())
                                .frame(minWidth: 18, minHeight: 18)
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingMedium)
                    .padding(.vertical, AppTheme.spacingSmall)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Content (expanded)
            if isExpanded {
                content
            }
        }
    }
}

struct SenderInfo: Identifiable, Hashable {
    let id: String
    let email: String
    let name: String
    let unreadCount: Int
}

struct SlackStyleSenderRow: View {
    let sender: SenderInfo
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Circle icon prefix (Slack-style for users)
            Image(systemName: "person.circle.fill")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                .frame(width: 16, alignment: .leading)
            
            // Sender name
            Text(sender.name)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(isPressed ? AppTheme.accent : AppTheme.secondaryText)
                .lineLimit(1)
            
            Spacer()
            
            // Unread count badge (Slack-style rounded badge)
            if sender.unreadCount > 0 {
                Text("\(sender.unreadCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, sender.unreadCount > 99 ? 5 : 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
                    .frame(minWidth: 18, minHeight: 18)
            }
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, 4)
        .background(
            isPressed 
                ? AppTheme.secondaryBackground.opacity(0.6) 
                : Color.clear
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

struct MenuView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var showClearedAlert = false
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    if !authManager.accounts.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                            Text("Connected Accounts")
                                .font(AppTheme.headline)
                                .primaryText()
                            
                            ForEach(authManager.accounts) { account in
                                Text(account.email)
                                    .font(AppTheme.subheadline)
                                    .secondaryText()
                            }
                        }
                        .padding(.vertical, AppTheme.spacingSmall)
                    }
                }
                
                Section {
                    Button {
                        Task {
                            do {
                                #if canImport(UIKit)
                                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                      let rootViewController = windowScene.windows.first?.rootViewController else {
                                    return
                                }
                                
                                _ = try await GmailAPIService.shared.signIn(presentingViewController: rootViewController)
                                
                                // Refresh accounts
                                authManager.accounts = GmailAPIService.shared.getAllAccounts()
                                
                                // Dashboard will refresh on next manual refresh
                                
                                dismiss()
                                #endif
                            } catch {
                                print("Error adding Gmail account: \(error)")
                            }
                        }
                    } label: {
                        SwiftUI.Label("Add Gmail Account", systemImage: "plus.circle")
                    }
                    
                    Button {
                        Task {
                            await DashboardCache.shared.clear()
                            await EmailCache.shared.clearAll()
                            await MainActor.run {
                                NotificationCenter.default.post(name: NSNotification.Name("CacheCleared"), object: nil)
                                showClearedAlert = true
                                // Auto-dismiss the sheet shortly after clearing
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    dismiss()
                                }
                            }
                        }
                    } label: {
                        SwiftUI.Label("Clear Cache", systemImage: "trash")
                    }
                    
                    Button {
                        authManager.logout()
                        dismiss()
                    } label: {
                        SwiftUI.Label("Logout", systemImage: "arrow.right.square")
                            .foregroundColor(.red)
                    }
                }
            }
            .primaryBackground()
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .textButton()
                }
            }
            .alert("Cache cleared", isPresented: $showClearedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Local cache was removed.")
            }
        }
    }
}

struct ScrollingText: View {
    let text: String
    let font: Font
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var hasScrolled = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Hidden text to measure width
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textGeometry in
                            Color.clear.preference(
                                key: TextWidthPreferenceKey.self,
                                value: textGeometry.size.width
                            )
                        }
                    )
                    .opacity(0)
                
                // Visible scrolling text
                Text(text)
                    .font(font)
                    .primaryText()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: calculateOffset())
                    .opacity(opacity)
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .onPreferenceChange(TextWidthPreferenceKey.self) { width in
                textWidth = width
                containerWidth = geometry.size.width
                checkIfScrollingNeeded()
            }
            .onAppear {
                containerWidth = geometry.size.width
                // Measure text width after a brief delay to ensure layout is complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    checkIfScrollingNeeded()
                }
            }
            .onChange(of: geometry.size.width) { oldValue, newWidth in
                containerWidth = newWidth
                checkIfScrollingNeeded()
            }
        }
        .frame(height: 22) // Fixed height for headline font
    }
    
    private func calculateOffset() -> CGFloat {
        // If text fits, center it
        if textWidth <= containerWidth {
            return (containerWidth - textWidth) / 2
        }
        // Otherwise, use the scroll offset
        return offset
    }
    
    private func checkIfScrollingNeeded() {
        guard !hasScrolled && textWidth > containerWidth && containerWidth > 0 && textWidth > 0 else {
            return
        }
        
        hasScrolled = true
        
        // Start from center position
        let startOffset = (containerWidth - textWidth) / 2
        offset = startOffset
        
        // Calculate scroll distance (scroll until the end of text is visible)
        let scrollDistance = textWidth - containerWidth + 40 // Add padding
        
        // Wait a moment before starting scroll
        let scrollDuration = Double(scrollDistance) / 25.0
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Scroll animation (slow scroll - about 25 points per second)
            withAnimation(.linear(duration: scrollDuration)) {
                offset = startOffset - scrollDistance
            }
            
            // Fade out after scrolling completes
            try? await Task.sleep(nanoseconds: UInt64(scrollDuration * 1_000_000_000))
            
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 0
            }
        }
    }
}

struct TextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - String Extension for Name Formatting

extension String {
    /// Formats a string as a name: first letter of each word capitalized, rest lowercase
    var formattedAsName: String {
        return self
            .split(separator: " ")
            .map { word in
                guard let firstChar = word.first else { return String(word) }
                return String(firstChar).uppercased() + String(word.dropFirst()).lowercased()
            }
            .joined(separator: " ")
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthManager())
}

// MARK: - Account Summary Card

struct AccountSummaryCard: View {
    let account: EmailAccount
    let unreadCount: Int
    let starredCount: Int
    let lastRefreshTime: Date?
    let onRefresh: () async -> Void
    
    @State private var isRefreshing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMedium) {
            // Account header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.email)
                        .font(AppTheme.headline)
                        .primaryText()
                    
                    if let lastRefresh = lastRefreshTime {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.secondaryText)
                            Text(formatLastRefreshTime(lastRefresh))
                                .font(AppTheme.caption)
                                .secondaryText()
                        }
                    } else if account.email_count == 0 {
                        // New account that's being synced
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(AppTheme.accent)
                            Text("Syncing...")
                                .font(AppTheme.caption)
                                .foregroundColor(AppTheme.accent)
                        }
                    } else {
                        Text("Never synced")
                            .font(AppTheme.caption)
                            .secondaryText()
                    }
                }
                
                Spacer()
                
                // Refresh button
                Button {
                    Task {
                        await MainActor.run {
                            isRefreshing = true
                        }
                        await onRefresh()
                        await MainActor.run {
                            isRefreshing = false
                        }
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(AppTheme.accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.accent)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isRefreshing)
            }
            
            Divider()
                .background(AppTheme.secondaryText.opacity(0.3))
            
            // Stats row
            HStack(spacing: AppTheme.spacingLarge) {
                // Unread count
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(unreadCount)")
                        .font(AppTheme.title2)
                        .foregroundColor(AppTheme.accent)
                    Text("Unread")
                        .font(AppTheme.caption)
                        .secondaryText()
                }
                
                // Starred count
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(starredCount)")
                        .font(AppTheme.title2)
                        .foregroundColor(AppTheme.accent)
                    Text("Starred")
                        .font(AppTheme.caption)
                        .secondaryText()
                }
                
                Spacer()
                
                // Catch up button
                NavigationLink(value: "catch_up_\(account.id)") {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 14, weight: .medium))
                        Text("Catch Up")
                            .font(AppTheme.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(AppTheme.primaryText)
                    .padding(.horizontal, AppTheme.spacingMedium)
                    .padding(.vertical, AppTheme.spacingUnit)
                    .background(AppTheme.accent)
                    .cornerRadius(AppTheme.cornerRadiusMedium)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(unreadCount == 0)
                .opacity(unreadCount == 0 ? 0.5 : 1.0)
            }
        }
        .padding(AppTheme.spacingMedium)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func formatLastRefreshTime(_ date: Date) -> String {
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
}


