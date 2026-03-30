//
//  ContentView.swift
//  emptymyinboxMacApp
//
//  Desktop shell: sidebar + detail; uses shared services and caches.
//

import SwiftUI
import EmptyMyInboxShared

private enum MacRootTab: Int, CaseIterable, Identifiable, Hashable {
    case mail
    case calendar
    case actionItems

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .mail: return "Mail"
        case .calendar: return "Calendar"
        case .actionItems: return "Action Items"
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var calendarModel = GoogleCalendarViewModel()
    @State private var rootTab: MacRootTab = .mail
    @State private var snapshot: DashboardDataSnapshot?
    @State private var isRefreshing = false
    @State private var refreshMessage: String?
    @State private var showVaultSettings = false
    @State private var showAppSettings = false
    @State private var isAddingGmailAccount = false
    @State private var lastCalendarRefreshAt: Date?
    @State private var lastActionItemsRefreshAt: Date?

    var body: some View {
        Group {
            switch authManager.sessionState {
            case .checking:
                MacSplashView()
            case .needsLogin:
                MacLoginView()
            case .authenticated:
                mainChrome
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        .background(MacAppTheme.primaryBackground)
        .sheet(isPresented: $showVaultSettings) {
            MacVaultSettingsView()
        }
        .sheet(isPresented: $showAppSettings) {
            NavigationStack {
                AppSettingsMenuContent(
                    vaultSettings: { MacVaultSettingsView() },
                    isAddingAccount: $isAddingGmailAccount,
                    onAddGmailAccount: { Task { await addGmailAccountFromSettings() } },
                    onDismiss: { showAppSettings = false },
                    accentColor: MacAppTheme.accent
                )
                .environmentObject(authManager)
            }
            .frame(minWidth: 520, minHeight: 640)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macOpenVaultSettings)) { _ in
            showVaultSettings = true
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                Task { await AppLifecycleCloudSync.pushLocalStateOnly() }
            }
            if oldPhase != .active && newPhase == .active {
                checkMacForegroundCompanionIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var mainChrome: some View {
        Group {
            switch rootTab {
            case .mail:
                mailSplitView
            case .calendar:
                MacVaultCalendarTab(model: calendarModel, onOpenSettings: { showAppSettings = true })
            case .actionItems:
                MacVaultActionItemsTab(onOpenSettings: { showAppSettings = true })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppTheme.primaryBackground)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(selection: $rootTab) {
                    ForEach(MacRootTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                } label: {
                    Text("Primary navigation")
                }
                .labelsHidden()
                .accessibilityLabel("Primary navigation")
                .pickerStyle(.segmented)
                .frame(maxWidth: 460)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showVaultSettings = true
                } label: {
                    Label("Vault", systemImage: "shippingbox")
                }
                .labelStyle(.iconOnly)
                .help("Vault storage settings")

                Button {
                    Task { await refreshCurrentTab() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .disabled(isRefreshing)
                .help("Refresh current tab (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .toolbarBackground(MacAppTheme.secondaryBackground.opacity(0.65), for: .windowToolbar)
        .onReceive(NotificationCenter.default.publisher(for: .companionVaultCalendarActionItemsRefresh)) { _ in
            Task {
                await calendarModel.refresh()
                lastCalendarRefreshAt = Date()
                NotificationCenter.default.post(name: .macActionItemsShouldReload, object: nil)
                lastActionItemsRefreshAt = Date()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountAdded)) { _ in
            Task {
                await calendarModel.refresh()
                NotificationCenter.default.post(name: .macActionItemsShouldReload, object: nil)
            }
        }
    }

    @ViewBuilder
    private var mailSplitView: some View {
        MacMailTabView(
            snapshot: $snapshot,
            isRefreshing: $isRefreshing,
            refreshMessage: $refreshMessage,
            onRefreshMailbox: { Task { await refreshMailbox() } },
            onOpenSettings: { showAppSettings = true }
        )
        .environmentObject(authManager)
        .background(MacAppTheme.primaryBackground)
        .task(id: authManager.sessionState) {
            if case .authenticated = authManager.sessionState {
                await loadSnapshot()
                NotificationCenter.default.post(name: .companionVaultCalendarActionItemsRefresh, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macActionItemsShouldReload)) { _ in
            lastActionItemsRefreshAt = Date()
        }
    }

    private func loadSnapshot() async {
        snapshot = await DashboardDataManager.shared.loadCachedSnapshot()
    }

    private func refreshMailbox() async {
        isRefreshing = true
        refreshMessage = nil
        defer { isRefreshing = false }
        _ = await DashboardDataManager.shared.refreshData(shouldSync: true, progressCallback: nil)
        await loadSnapshot()
        refreshMessage = "Updated \(snapshot?.timestamp.formatted(date: .abbreviated, time: .shortened) ?? "—")"
        NotificationCenter.default.post(name: .companionVaultCalendarActionItemsRefresh, object: nil)
    }

    private func refreshCurrentTab() async {
        switch rootTab {
        case .mail:
            await refreshMailbox()
        case .calendar:
            await calendarModel.refresh()
            lastCalendarRefreshAt = Date()
        case .actionItems:
            NotificationCenter.default.post(name: .macActionItemsShouldReload, object: nil)
            lastActionItemsRefreshAt = Date()
        }
    }

    private func addGmailAccountFromSettings() async {
        isAddingGmailAccount = true
        defer { isAddingGmailAccount = false }
        do {
            try await authManager.signInWithGoogle()
        } catch {
            logError("Add account failed: \(error)", category: "Auth")
        }
    }

    /// Matches iOS `checkAndRefreshIfNeeded` day gate: first foreground of a new calendar day pulls Gmail and posts companion (Calendar + Action Items).
    private func checkMacForegroundCompanionIfNeeded() {
        guard case .authenticated = authManager.sessionState else { return }
        let userDefaults = UserDefaults.standard
        let lastAutoRefreshKey = "lastAutoRefreshDate"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if let lastRefreshDate = userDefaults.object(forKey: lastAutoRefreshKey) as? Date {
            let lastRefreshDay = calendar.startOfDay(for: lastRefreshDate)
            if calendar.isDate(today, inSameDayAs: lastRefreshDay) {
                return
            }
        }
        userDefaults.set(today, forKey: lastAutoRefreshKey)
        Task { await refreshMailbox() }
    }
}

// MARK: - Login

private struct MacLoginView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            LogoView(size: 88)
            Text("Empty My Inbox")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(MacAppTheme.primaryText)
            Text("Sign in with Google to load your Gmail accounts and dashboard.")
                .font(.body)
                .foregroundStyle(MacAppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if authManager.isLoading {
                ProgressView()
                    .scaleEffect(1.1)
                    .tint(MacAppTheme.accent)
            } else {
                Button {
                    Task { await signIn() }
                } label: {
                    Label("Sign in with Google", systemImage: "person.crop.circle.badge.plus")
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(MacAppTheme.accent)
                .controlSize(.large)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 420)
            }

            Text("Messages in the log about “no accounts in keychain” are normal until you sign in successfully.")
                .font(.caption2)
                .foregroundStyle(MacAppTheme.secondaryText.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppTheme.primaryBackground)
    }

    private func signIn() async {
        errorMessage = nil
        do {
            try await authManager.signInWithGoogle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Splash

private struct MacSplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            LogoView(size: 64)
            ProgressView()
                .tint(MacAppTheme.accent)
            Text("Loading…")
                .foregroundStyle(MacAppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppTheme.primaryBackground)
    }
}

// MARK: - Dashboard

private func unreadCount(snapshot: DashboardDataSnapshot, accountEmail: String) -> Int {
    snapshot.emails.filter {
        $0.account_email.caseInsensitiveCompare(accountEmail) == .orderedSame && !$0.is_read
    }.count
}

struct MacDashboardDetailView: View {
    let snapshot: DashboardDataSnapshot?
    let isRefreshing: Bool
    let refreshMessage: String?
    let onRefresh: () -> Void

    var body: some View {
        Group {
            if let snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if isRefreshing {
                            HStack {
                                Spacer(minLength: 0)
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        if let refreshMessage {
                            Text(refreshMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                            ForEach(snapshot.accounts, id: \.id) { account in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.email)
                                        .font(.headline)
                                        .foregroundStyle(MacAppTheme.primaryText)
                                        .lineLimit(1)
                                    Text("\(unreadCount(snapshot: snapshot, accountEmail: account.email)) unread")
                                        .font(.caption)
                                        .foregroundStyle(MacAppTheme.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(MacAppTheme.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }

                        Text("Last snapshot: \(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(MacAppTheme.secondaryText.opacity(0.75))

                        Text("Tip: Use ⌘R to refresh mailbox data from Gmail.")
                            .font(.caption)
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
                    .padding(24)
                }
            } else {
                ContentUnavailableView {
                    Label("No dashboard data yet", systemImage: "tray")
                } description: {
                    Text("Tap Refresh in the toolbar to pull your latest Gmail data.")
                } actions: {
                    Button("Refresh now", action: onRefresh)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Dashboard")
    }
}

// MARK: - Accounts

struct MacAccountsListView: View {
    let accounts: [GmailAccount]

    var body: some View {
        List(accounts) { account in
            VStack(alignment: .leading, spacing: 4) {
                Text(account.email)
                    .font(.headline)
                    .foregroundStyle(MacAppTheme.primaryText)
                Text("Gmail account")
                    .font(.caption)
                    .foregroundStyle(MacAppTheme.secondaryText)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Accounts")
        .scrollContentBackground(.hidden)
        .background(MacAppTheme.primaryBackground)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}
