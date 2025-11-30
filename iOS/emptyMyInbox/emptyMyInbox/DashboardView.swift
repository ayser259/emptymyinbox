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
    @State private var accountHealthStatuses: [String: AccountHealthStatus] = [:] // email -> status
    
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
                switch filter {
                case .accountSenders(let accountEmail):
                    AccountSendersView(accountEmail: accountEmail)
                default:
                    FilteredEmailsView(filter: filter)
                }
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
                await refreshDashboard(shouldSync: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .emailMetadataLoaded)) { notification in
            // CatchUp loaded new email data - update our counts
            let count = notification.userInfo?["count"] as? Int ?? 0
            logInfo("Dashboard received emailMetadataLoaded notification: \(count) emails", category: "Dashboard")
            Task {
                // Reload from cache to get the updated counts
                if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
                    await MainActor.run {
                        applySnapshot(snapshot)
                        logInfo("Dashboard updated from CatchUp data: \(self.emails.count) emails", category: "Dashboard")
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .starredEmailsUpdated)) { notification in
            // Starred emails were updated - reload from cache
            let count = notification.userInfo?["count"] as? Int ?? 0
            logInfo("Dashboard received starredEmailsUpdated notification: \(count) starred emails", category: "Dashboard")
            Task {
                if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
                    await MainActor.run {
                        applySnapshot(snapshot)
                        logInfo("Dashboard updated starred count: \(self.starredEmails.count)", category: "Dashboard")
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardNeedsUpdate)) { _ in
            // Email status changed somewhere - reload from cache to update counters
            logInfo("Dashboard received dashboardNeedsUpdate notification", category: "Dashboard")
            Task {
                if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
                    await MainActor.run {
                        applySnapshot(snapshot)
                        logInfo("Dashboard updated from cache: \(self.allEmails.count) emails, \(self.starredEmails.count) starred", category: "Dashboard")
                    }
                }
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
                    CatchUpActionButton(
                        title: "Catch up",
                        count: unreadCount
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(value: "all_emails") {
                    ActionButton(
                        title: "All emails",
                        count: allEmails.count,
                        icon: "envelope"
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(value: "senders") {
                    ActionButton(
                        title: "Senders",
                        count: totalSendersCount,
                        icon: "person.2.fill"
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(value: "starred") {
                    ActionButton(
                        title: "Saved",
                        count: starredEmails.count,
                        icon: "star.fill"
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
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
                            totalEmailCount: getTotalEmailCount(for: account),
                            senderCount: getSenderCount(for: account),
                            unreadSenderCount: getUnreadSenderCount(for: account),
                            lastRefreshTime: getLastRefreshTime(for: account),
                            healthStatus: accountHealthStatuses[account.email],
                            onRefresh: {
                                await refreshAccount(accountEmail: account.email)
                            },
                            onDisconnect: {
                                disconnectAccount(email: account.email)
                            }
                        )
                    }
                }
                .padding(.horizontal, AppTheme.spacingMedium)
            }
        }
    }
    
    private func getUnreadCount(for account: EmailAccount) -> Int {
        allEmails.filter { $0.account_email.lowercased() == account.email.lowercased() && !$0.is_read && !$0.is_starred }.count
    }
    
    private func getStarredCount(for account: EmailAccount) -> Int {
        starredEmails.filter { $0.account_email.lowercased() == account.email.lowercased() }.count
    }
    
    private func getTotalEmailCount(for account: EmailAccount) -> Int {
        allEmails.filter { $0.account_email.lowercased() == account.email.lowercased() }.count
    }
    
    private func getSenderCount(for account: EmailAccount) -> Int {
        let accountEmails = allEmails.filter { $0.account_email.lowercased() == account.email.lowercased() }
        let uniqueSenders = Set(accountEmails.map { $0.sender })
        return uniqueSenders.count
    }
    
    private func getUnreadSenderCount(for account: EmailAccount) -> Int {
        let unreadAccountEmails = allEmails.filter { $0.account_email.lowercased() == account.email.lowercased() && !$0.is_read && !$0.is_starred }
        let uniqueSenders = Set(unreadAccountEmails.map { $0.sender })
        return uniqueSenders.count
    }
    
    private func getLastRefreshTime(for account: EmailAccount) -> Date? {
        guard let lastSyncString = account.last_sync else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: lastSyncString)
    }
    
    private func getHealthStatus(for account: EmailAccount) -> AccountHealthStatus? {
        return accountHealthStatuses[account.email]
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
        emails.filter { !$0.is_read && !$0.is_starred }.count
    }
    
    // MARK: - Sender Grouping
    
    // Computed property for total senders count (all unique senders on device)
    private var totalSendersCount: Int {
        let grouped = Dictionary(grouping: allEmails) { email in
            email.sender
        }
        return grouped.count
    }
    
    // Computed property for unread senders count
    private var unreadSendersCount: Int {
        let unreadEmails = allEmails.filter { !$0.is_read && !$0.is_starred }
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
            
            // Search in both list items AND full cached email bodies
            var matchingEmailIds = Set<Int>()
            var resultEmails: [EmailListItem] = []
            
            // First: Search in cached email details (includes body text)
            // This searches the full body content that's been downloaded
            let fullBodyMatches = await EmailCache.shared.searchCachedEmails(query: trimmedQuery)
            for match in fullBodyMatches {
                matchingEmailIds.insert(match.id)
            }
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Second: Search in list items (for emails not yet fully cached)
            if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
                for email in snapshot.allEmails {
                    // Skip if already matched via full body search
                    if matchingEmailIds.contains(email.id) {
                        resultEmails.append(email)
                        continue
                    }
                    
                    // Search in list item fields
                    if email.subject.localizedCaseInsensitiveContains(trimmedQuery) ||
                       email.sender.localizedCaseInsensitiveContains(trimmedQuery) ||
                       email.sender_name?.localizedCaseInsensitiveContains(trimmedQuery) == true ||
                       email.snippet.localizedCaseInsensitiveContains(trimmedQuery) {
                        resultEmails.append(email)
                    }
                }
            }
            
            // Sort by received_at descending
            resultEmails.sort { $0.received_at > $1.received_at }
            
            // Check again if task was cancelled
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.searchResults = resultEmails
                self.isSearching = false
            }
        }
    }
    
    private func loadInitialData() async {
        // First, quickly show any cached data
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            await MainActor.run {
                applySnapshot(snapshot)
                logInfo("Loaded cached snapshot: \(snapshot.emails.count) emails", category: "Dashboard")
            }
        }
        
        // Always sync on initial load to get fresh data
        // This ensures we don't show stale counts
        logInfo("Initial load - syncing with Gmail...", category: "Dashboard")
        await refreshDashboard(shouldSync: true)
    }
    
    private func refreshDashboard(shouldSync: Bool) async {
        logDebug("DashboardView.refreshDashboard called - shouldSync: \(shouldSync)", category: "Dashboard")
        
        // Check current state
        let (currentlyRefreshing, currentlyLoading) = await MainActor.run {
            return (isRefreshing, isLoading)
        }
        
        // If a sync is requested, always allow it (don't skip)
        // Only skip if we're already syncing
        if shouldSync {
            if currentlyRefreshing {
                logWarning("Skipping sync - already syncing", category: "Dashboard")
                return
            }
            // If just loading (non-sync), we can override it with a sync
        } else {
            // Non-sync request - skip if any refresh is happening
            if currentlyRefreshing || currentlyLoading {
                logWarning("Skipping non-sync refresh - already refreshing", category: "Dashboard")
                return
            }
        }
        
        // Set loading state
        await MainActor.run {
            if shouldSync {
                isRefreshing = true
                isLoading = false // Clear loading if we're now syncing
                progressTracker.reset()
            } else {
                isLoading = true
            }
        }
        
        // Create progress callback
        let progressCallback: DashboardDataManager.ProgressCallback = { stage, status, detail, accountEmail, currentCount, totalCount in
            await MainActor.run {
                self.progressTracker.updateStage(stage, status: status, detail: detail, accountEmail: accountEmail, currentCount: currentCount, totalCount: totalCount)
            }
        }
        
        do {
            if let snapshot = await DashboardDataManager.shared.refreshData(shouldSync: shouldSync, progressCallback: progressCallback) {
                // Get health statuses after refresh
                let healthStatuses = await DashboardDataManager.shared.getAccountHealth()
                logDebug("Received \(healthStatuses.count) health statuses", category: "Dashboard")
                
                await MainActor.run {
                    applySnapshot(snapshot)
                    lastRefreshTime = snapshot.timestamp
                    
                    // Update health statuses
                    for health in healthStatuses {
                        accountHealthStatuses[health.email] = health.status
                        logDebug("Set health for \(health.email): \(health.status)", category: "Health")
                    }
                    
                    logSuccess("Dashboard updated: \(accounts.count) accounts, \(emails.count) emails", category: "Dashboard")
                }
            } else {
                logWarning("refreshData returned nil", category: "Dashboard")
            }
        }
        
        // Always reset loading states when done
        await MainActor.run {
            if shouldSync {
                isRefreshing = false
            }
            isLoading = false
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
        // Use full dashboard refresh with sync for this account
        // This now uses fast metadata-only sync
        if let snapshot = await DashboardDataManager.shared.refreshData(shouldSync: true) {
            await MainActor.run {
                applySnapshot(snapshot)
                lastRefreshTime = snapshot.timestamp
            }
        }
    }
    
    private func disconnectAccount(email: String) {
        authManager.logout(accountEmail: email)
        // Remove from local state
        accounts.removeAll { $0.email == email }
        accountHealthStatuses.removeValue(forKey: email)
        // Clear emails for this account from local state
        allEmails.removeAll { $0.account_email == email }
        emails.removeAll { $0.account_email == email }
        starredEmails.removeAll { $0.account_email == email }
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

// MARK: - Catch Up Action Button (Featured with yellow border)

struct CatchUpActionButton: View {
    let title: String
    let count: Int
    
    var body: some View {
        VStack(spacing: AppTheme.spacingSmall) {
            // Use Caughtup image when count is 0, otherwise use Catchup
            if count == 0 {
                Image("Caughtup")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image("Catchup")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            }
            
            // Show "Inbox 0!" when count is 0, otherwise show title
            Text(count == 0 ? "Inbox 0!" : title)
                .font(.system(size: 14, weight: .semibold))
                .primaryText()
            
            // Show count only if not zero
            if count > 0 {
                Text("\(count)")
                    .font(AppTheme.caption)
                    .secondaryText()
            }
        }
        .frame(width: 100, height: 100)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(AppTheme.accent, lineWidth: 2)
        )
        .shadow(color: AppTheme.accent.opacity(0.2), radius: 6, x: 0, y: 2)
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
    @StateObject private var debugSettings = DebugSettings.shared
    @State private var showClearedAlert = false
    @State private var showDebugLogs = false
    @State private var cachedEmailCount: Int = 0
    @State private var accountToDisconnect: GmailAccount?
    @State private var showDisconnectConfirmation = false
    @State private var isAddingAccount = false
    
    var body: some View {
        NavigationView {
            List {
                // Connected Accounts section with individual account management
                Section {
                    // Account rows with disconnect buttons
                    ForEach(authManager.accounts) { account in
                        ConnectedAccountRow(
                            account: account,
                            onDisconnect: {
                                accountToDisconnect = account
                                showDisconnectConfirmation = true
                            }
                        )
                    }
                    
                    // Add Gmail button - inside the Connected Accounts section
                    Button {
                        addGmailAccount()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(AppTheme.accent)
                            
                            Text("Add Gmail Account")
                                .font(AppTheme.body)
                                .foregroundColor(AppTheme.accent)
                            
                            Spacer()
                            
                            if isAddingAccount {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isAddingAccount)
                } header: {
                    Text("Connected Accounts")
                } footer: {
                    if authManager.accounts.isEmpty {
                        Text("No accounts connected. Add a Gmail account to get started.")
                    } else {
                        Text("Tap the disconnect button to remove an account. You can reconnect it anytime.")
                    }
                }
                
                // Storage section
                Section {
                    HStack {
                        SwiftUI.Label("Cached Emails", systemImage: "internaldrive")
                        Spacer()
                        Text("\(cachedEmailCount) emails")
                            .font(AppTheme.caption)
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    
                    Button {
                        Task {
                            await DashboardCache.shared.clear()
                            await EmailCache.shared.clearAll()
                            await MainActor.run {
                                cachedEmailCount = 0
                                NotificationCenter.default.post(name: NSNotification.Name("CacheCleared"), object: nil)
                                showClearedAlert = true
                            }
                        }
                    } label: {
                        SwiftUI.Label("Clear Cache", systemImage: "trash")
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("Local Storage")
                } footer: {
                    Text("Email content is stored locally for fast access and offline search.")
                }
                
                // Account actions section
                Section {
                    Button {
                        authManager.logout()
                        dismiss()
                    } label: {
                        HStack {
                            SwiftUI.Label("Logout All Accounts", systemImage: "arrow.right.square")
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("This will disconnect all accounts and clear local data.")
                }
                
                // Debug section
                Section {
                    // Debug Mode Toggle
                    Toggle(isOn: $debugSettings.isDebugModeEnabled) {
                        HStack {
                            Image(systemName: "hammer.fill")
                                .foregroundColor(debugSettings.isDebugModeEnabled ? .purple : AppTheme.secondaryText)
                            Text("Debug Mode")
                        }
                    }
                    .tint(.purple)
                    
                    Button {
                        showDebugLogs = true
                    } label: {
                        HStack {
                            SwiftUI.Label("Debug Logs", systemImage: "ladybug")
                            Spacer()
                            Text("\(DebugLogger.shared.entries.count)")
                                .font(AppTheme.caption)
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    if debugSettings.isDebugModeEnabled {
                        Text("Debug mode is ON. Copy buttons will appear in email views.")
                            .foregroundColor(.purple)
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
            .alert("Disconnect Account?", isPresented: $showDisconnectConfirmation) {
                Button("Cancel", role: .cancel) {
                    accountToDisconnect = nil
                }
                Button("Disconnect", role: .destructive) {
                    if let account = accountToDisconnect {
                        authManager.logout(accountEmail: account.email)
                        NotificationCenter.default.post(name: NSNotification.Name("CacheCleared"), object: nil)
                    }
                    accountToDisconnect = nil
                }
            } message: {
                if let account = accountToDisconnect {
                    Text("This will disconnect \(account.email) from the app. You can reconnect it later.")
                } else {
                    Text("This will disconnect the account from the app.")
                }
            }
            .sheet(isPresented: $showDebugLogs) {
                DebugLogView()
            }
            .task {
                // Load cached email count
                cachedEmailCount = await EmailCache.shared.cachedEmailCount()
            }
        }
    }
    
    private func addGmailAccount() {
        isAddingAccount = true
        Task {
            do {
                #if canImport(UIKit)
                guard let windowScene = await MainActor.run(body: {
                    UIApplication.shared.connectedScenes.first as? UIWindowScene
                }),
                      let rootViewController = await MainActor.run(body: {
                          windowScene.windows.first?.rootViewController
                      }) else {
                    await MainActor.run { isAddingAccount = false }
                    return
                }
                
                _ = try await GmailAPIService.shared.signIn(presentingViewController: rootViewController)
                
                await MainActor.run {
                    // Refresh accounts
                    authManager.accounts = GmailAPIService.shared.getAllAccounts()
                    // Notify dashboard
                    NotificationCenter.default.post(name: NSNotification.Name("AccountAdded"), object: nil)
                    isAddingAccount = false
                }
                #endif
            } catch {
                logError("Error adding Gmail account: \(error)", category: "Auth")
                await MainActor.run { isAddingAccount = false }
            }
        }
    }
}

// MARK: - Connected Account Row

struct ConnectedAccountRow: View {
    let account: GmailAccount
    let onDisconnect: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Account icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.3), AppTheme.accent.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: "envelope.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.accent)
            }
            
            // Account info
            VStack(alignment: .leading, spacing: 2) {
                Text(account.email)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: "#4ade80"))
                        .frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
            
            Spacer()
            
            // Disconnect button
            Button {
                onDisconnect()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.5))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
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

// MARK: - Account Summary Card (Redesigned)

struct AccountSummaryCard: View {
    let account: EmailAccount
    let unreadCount: Int
    let starredCount: Int
    let totalEmailCount: Int
    let senderCount: Int
    let unreadSenderCount: Int
    let lastRefreshTime: Date?
    let healthStatus: AccountHealthStatus?
    let onRefresh: () async -> Void
    var onDisconnect: (() -> Void)? = nil
    
    @State private var isRefreshing = false
    @State private var catchUpPressed = false
    @State private var showDisconnectConfirmation = false
    
    // Gradient colors for card
    private let cardGradient = LinearGradient(
        colors: [
            Color(hex: "#1a1a1a"),
            Color(hex: "#0d0d0d")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top section: Email + Refresh button
            HStack(alignment: .center) {
                // Account info
                VStack(alignment: .leading, spacing: 4) {
                    // Email address with subtle shadow for depth
                    Text(account.email)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .primaryText()
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    
                    // Last sync time
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                        
                        if let lastRefresh = lastRefreshTime {
                            Text(formatLastRefreshTime(lastRefresh))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                        } else if account.email_count == 0 {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .tint(AppTheme.accent)
                                Text("Syncing...")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.accent)
                            }
                        } else {
                            Text("Never synced")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                        }
                    }
                }
                
                Spacer()
                
                // Refresh button - pill style
                Button {
                    Task {
                        await MainActor.run { isRefreshing = true }
                        await onRefresh()
                        await MainActor.run { isRefreshing = false }
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppTheme.accent.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                            )
                        
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(AppTheme.accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.accent)
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isRefreshing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
            
            // Health status bar - glass morphism style
            HStack(spacing: 8) {
                Image(systemName: healthIconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(healthColor)
                
                Text(healthText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(healthColor)
                
                Spacer()
                
                // Disconnect button when not healthy
                if !isHealthy, let onDisconnect = onDisconnect {
                    Button {
                        showDisconnectConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Reconnect")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(healthColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(healthColor.opacity(0.15))
                                .overlay(
                                    Capsule()
                                        .stroke(healthColor.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Animated health indicator
                    Circle()
                        .fill(healthColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: healthColor.opacity(0.6), radius: 4, x: 0, y: 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(healthColor.opacity(0.08))
                    .overlay(
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [healthColor.opacity(0.15), healthColor.opacity(0.05)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            )
            
            // Error/Warning message if applicable
            if let status = healthStatus {
                switch status {
                case .error(let message):
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                case .warning(let message):
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                default:
                    EmptyView()
                }
            }
            
            // Stats section with better visual hierarchy
            VStack(spacing: 12) {
                // Top row stats - Unread & Starred (primary)
                HStack(spacing: 12) {
                    NavigationLink(value: EmailFilter.accountUnread(accountEmail: account.email)) {
                        PremiumStatBadge(
                            icon: "envelope.badge",
                            count: unreadCount,
                            label: "Unread",
                            isHighlighted: unreadCount > 0,
                            highlightColor: AppTheme.accent
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    NavigationLink(value: EmailFilter.accountStarred(accountEmail: account.email)) {
                        PremiumStatBadge(
                            icon: "star.fill",
                            count: starredCount,
                            label: "Starred",
                            isHighlighted: starredCount > 0,
                            highlightColor: .yellow
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Bottom row stats - Total & Senders (secondary)
                HStack(spacing: 12) {
                    NavigationLink(value: EmailFilter.accountAll(accountEmail: account.email)) {
                        PremiumStatBadge(
                            icon: "envelope",
                            count: totalEmailCount,
                            label: "Total",
                            isHighlighted: false,
                            highlightColor: AppTheme.secondaryText
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    NavigationLink(value: EmailFilter.accountSenders(accountEmail: account.email)) {
                        PremiumStatBadge(
                            icon: "person.2.fill",
                            count: senderCount,
                            label: "Senders",
                            isHighlighted: unreadSenderCount > 0,
                            highlightColor: AppTheme.accent,
                            secondaryText: unreadSenderCount > 0 ? "\(unreadSenderCount) unread" : nil
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            // Catch up button - subtle dark style that blends in
            if unreadCount > 0 {
                NavigationLink(value: "catch_up_\(account.id)") {
                    HStack(spacing: 8) {
                        // Yellow catchup icon for accent
                        Image("Catchup")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                        
                        Text("Catch Up")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        
                        Spacer()
                        
                        // Count badge
                        Text("\(unreadCount)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(AppTheme.accent.opacity(0.15))
                            )
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                    }
                    .foregroundColor(AppTheme.primaryText.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardGradient)
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04),
                            healthBorderGlow
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .alert("Disconnect Account?", isPresented: $showDisconnectConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                onDisconnect?()
            }
        } message: {
            Text("This will disconnect \(account.email) from the app. You can reconnect it later from the menu.")
        }
    }
    
    // MARK: - Health Properties
    
    private var healthIconName: String {
        guard let status = healthStatus else { return "circle.dotted" }
        switch status {
        case .healthy: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.shield.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var healthColor: Color {
        guard let status = healthStatus else { return AppTheme.secondaryText }
        switch status {
        case .healthy: return Color(hex: "#4ade80") // Brighter green
        case .warning: return .orange
        case .error: return .red
        case .unknown: return AppTheme.secondaryText
        }
    }
    
    private var healthText: String {
        guard let status = healthStatus else { return "Checking..." }
        switch status {
        case .healthy: return "Connected"
        case .warning: return "Warning"
        case .error: return "Error"
        case .unknown: return "Unknown"
        }
    }
    
    private var healthBorderGlow: Color {
        guard let status = healthStatus else { return Color.clear }
        switch status {
        case .healthy: return Color.clear
        case .warning: return Color.orange.opacity(0.3)
        case .error: return Color.red.opacity(0.3)
        case .unknown: return Color.clear
        }
    }
    
    private var isHealthy: Bool {
        guard let status = healthStatus else { return true }
        if case .healthy = status { return true }
        return false
    }
    
    private func formatLastRefreshTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if let seconds = calendar.dateComponents([.second], from: date, to: now).second, seconds < 60 {
            return "just now"
        }
        
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return timeFormatter.string(from: date)
        }
        
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        return dateFormatter.string(from: date)
    }
}

// MARK: - Premium Stat Badge

struct PremiumStatBadge: View {
    let icon: String
    let count: Int
    let label: String
    let isHighlighted: Bool
    let highlightColor: Color
    var secondaryText: String? = nil
    
    private var displayColor: Color {
        isHighlighted ? highlightColor : AppTheme.secondaryText.opacity(0.7)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(displayColor)
                
                Text("\(count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(displayColor)
            }
            
            if let secondary = secondaryText {
                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                    Text(secondary)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(highlightColor.opacity(0.9))
                }
            } else {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isHighlighted
                        ? highlightColor.opacity(0.08)
                        : Color.white.opacity(0.03)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isHighlighted
                                ? highlightColor.opacity(0.2)
                                : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Legacy Account Stat Cell (for compatibility)

struct AccountStatCell: View {
    let icon: String
    let count: Int
    let label: String
    var secondaryCount: Int? = nil
    var secondaryLabel: String? = nil
    var color: Color = AppTheme.accent
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            
            if let secondary = secondaryCount, let secondaryLabel = secondaryLabel {
                HStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 11))
                        .secondaryText()
                    Text("•")
                        .font(.system(size: 11))
                        .secondaryText()
                    Text("\(secondary) \(secondaryLabel)")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.accent)
                }
            } else {
                Text(label)
                    .font(.system(size: 11))
                    .secondaryText()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacingSmall)
        .contentShape(Rectangle())
    }
}


