//
//  DashboardView.swift
//  emptyMyInbox
//
//  Main dashboard view after login
//

import SwiftUI
import UIKit
import EmptyMyInboxShared

struct DashboardView: View {
    private enum BriefingTrigger {
        case manual
        case automatic
    }

    @EnvironmentObject var authManager: AuthManager
    @Binding var isMenuPresented: Bool
    @State private var navigationPath = NavigationPath()
    @State private var accounts: [EmailAccount] = []
    @State private var emails: [EmailListItem] = []
    @State private var allEmails: [EmailListItem] = [] // All emails for sender grouping
    @State private var starredEmails: [EmailListItem] = []
    @State private var labels: [GmailLabel] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var lastRefreshTime: Date?
    @StateObject private var progressTracker = RefreshProgressTracker()
    @State private var showProgressModal = false
    @State private var accountHealthStatuses: [String: AccountHealthStatus] = [:] // email -> status
    @State private var showDailyBriefing = false
    @State private var dailyBriefingPayload: DailyBriefingPayload?
    @State private var pendingAutoBriefing = false
    @State private var showSummaryUpsell = false
    @State private var storiesCount = 0
    @State private var isGeneratingBrief = false
    private let persistedBriefingKey = "persistedDailyBriefingPayload"
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
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
            .navigationDestination(for: GmailLabel.self) { label in
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
                case "insights":
                    NewsletterInsightDeckView(
                        emails: allEmails,
                        onDiveDeeper: { emailId in
                            navigationPath.append(emailId)
                        },
                        onOpenLLMSettings: {
                            navigationPath.append("llm_management")
                        }
                    )
                case "llm_management":
                    LLMManagementView()
                default:
                    EmptyView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await loadInitialData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cacheCleared)) { _ in
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
        .onReceive(NotificationCenter.default.publisher(for: .appShouldShowDailyBriefing)) { _ in
            Task { @MainActor in
                pendingAutoBriefing = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountAdded)) { _ in
            // New account was added, refresh to show it immediately
            Task {
                await AccountInclusionStore.shared.refreshFromConnectedAccounts()
                await refreshDashboard(shouldSync: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .llmAPIKeyChanged)) { _ in
            Task {
                let hasKey = await LLMSettingsStore.shared.hasAPIKey()
                await MainActor.run {
                    if hasKey {
                        showSummaryUpsell = false
                    }
                }
                if hasKey, pendingAutoBriefing {
                    await presentDailyBriefingIfPending()
                }
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
        .sheet(isPresented: $showDailyBriefing) {
            if let payload = dailyBriefingPayload {
                DailyBriefingSheet(
                    payload: payload,
                    onItemTap: { item in
                        showDailyBriefing = false
                        navigationPath.append(item.emailId)
                        saveLastBriefingCheckDate()
                    },
                    onDismiss: {
                        showDailyBriefing = false
                        saveLastBriefingCheckDate()
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showSummaryUpsell) {
            LLMUpsellView(
                title: "Unlock AI Summary",
                subtitle: "Add your OpenAI API key to enable the Daily Executive Summary.",
                actionTitle: "Add API Key",
                onAction: {
                    showSummaryUpsell = false
                    navigationPath.append("llm_management")
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBarSection

                VaultRefreshStatusLabel(font: .caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.spacingMedium)
                    .padding(.bottom, AppTheme.spacingSmall)
                
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
        MainAppTopBar(center: {
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
        }, onMenuTap: {
            isMenuPresented = true
        })
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

                NavigationLink(value: "insights") {
                    ActionButton(
                        title: "Stories",
                        count: storiesCount,
                        icon: "rectangle.stack.fill"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    Task { await presentDailyBriefing(trigger: .manual) }
                } label: {
                    ActionButton(
                        title: "Brief",
                        count: dailyBriefingPayload?.items.count ?? 0,
                        icon: "sparkles",
                        badgeText: isGeneratingBrief ? "..." : nil
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isGeneratingBrief)
                
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
                            onReconnect: {
                                await reconnectAccount(accountEmail: account.email)
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
    
    private func loadInitialData() async {
        await AccountInclusionStore.shared.refreshFromConnectedAccounts()
        await refreshStoriesCount()
        await loadPersistedDailyBriefing()

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
        NotificationCenter.default.post(name: .companionVaultCalendarActionItemsRefresh, object: nil)
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
            if shouldSync {
                await VaultManager.shared.performLifecycleSync(postNotification: false)
            }
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

                await refreshStoriesCount()
                await presentDailyBriefingIfPending()
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

    private func presentDailyBriefingIfPending() async {
        let currentlyGenerating = await MainActor.run { isGeneratingBrief }
        if currentlyGenerating { return }
        let shouldPresent = await MainActor.run { pendingAutoBriefing }
        guard shouldPresent else { return }
        await presentDailyBriefing(trigger: .automatic)
    }

    private func presentDailyBriefing(trigger: BriefingTrigger) async {
        let startedAt = Date()
        let triggerLabel: String
        switch trigger {
        case .manual:
            triggerLabel = "manual"
        case .automatic:
            triggerLabel = "automatic"
        }
        Telemetry.event("daily_briefing.generate.started", metadata: ["trigger": triggerLabel])
        await MainActor.run { isGeneratingBrief = true }

        let hasKey = await LLMSettingsStore.shared.hasAPIKey()
        guard hasKey else {
            await MainActor.run {
                showSummaryUpsell = true
                isGeneratingBrief = false
            }
            Telemetry.event("daily_briefing.generate.blocked_no_key", metadata: ["trigger": triggerLabel])
            return
        }

        let shouldReusePersisted: Bool = await MainActor.run {
            if case .manual = trigger {
                return !pendingAutoBriefing && dailyBriefingPayload != nil
            }
            return false
        }
        if shouldReusePersisted {
            await MainActor.run {
                showDailyBriefing = true
                isGeneratingBrief = false
            }
            Telemetry.event("daily_briefing.generate.reused_cached", metadata: ["trigger": triggerLabel])
            return
        }

        let sinceDate = lastBriefingCheckDate()
        let payload = await DailyBriefingEngine.shared.buildPayload(from: allEmails, sinceDate: sinceDate)
        await persistDailyBriefing(payload)
        await MainActor.run {
            dailyBriefingPayload = payload
            showDailyBriefing = true
            if case .automatic = trigger {
                pendingAutoBriefing = false
                markAutoBriefingShownToday()
            }
            isGeneratingBrief = false
        }
        Telemetry.event("daily_briefing.generate.presented", metadata: [
            "trigger": triggerLabel,
            "item_count": "\(payload.items.count)",
            "elapsed_ms": "\(Int(Date().timeIntervalSince(startedAt) * 1000))"
        ])
    }

    private func saveLastBriefingCheckDate() {
        UserDefaults.standard.set(Date(), forKey: "lastDailyBriefingCheckDate")
    }

    private func lastBriefingCheckDate() -> Date? {
        UserDefaults.standard.object(forKey: "lastDailyBriefingCheckDate") as? Date
    }

    private func markAutoBriefingShownToday() {
        let today = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(today, forKey: "lastBriefingShownDate")
    }

    private func refreshStoriesCount() async {
        let count = await StoriesFeedStore.shared.stories().count
        await MainActor.run {
            storiesCount = count
        }
    }

    private func loadPersistedDailyBriefing() async {
        guard let data = UserDefaults.standard.data(forKey: persistedBriefingKey),
              let payload = try? JSONDecoder().decode(DailyBriefingPayload.self, from: data) else {
            return
        }
        await MainActor.run {
            dailyBriefingPayload = payload
        }
    }

    private func persistDailyBriefing(_ payload: DailyBriefingPayload) async {
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: persistedBriefingKey)
        }
    }
    
    private func refreshAccount(accountEmail: String) async {
        if let snapshot = await DashboardDataManager.shared.refreshData(forAccountEmail: accountEmail, shouldSync: true) {
            await MainActor.run {
                applySnapshot(snapshot)
                lastRefreshTime = snapshot.timestamp
            }
        }
    }
    
    @MainActor
    private func reconnectAccount(accountEmail: String) async {
        do {
            try await authManager.signInWithGoogle()
            await refreshDashboard(shouldSync: true)
        } catch {
            let message = error.localizedDescription
            accountHealthStatuses[accountEmail] = .error("Reconnect failed: \(message)")
            logError("Reconnect failed for \(accountEmail): \(message)", category: "Auth")
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

#Preview {
    DashboardView(isMenuPresented: .constant(false))
        .environmentObject(AuthManager())
}
