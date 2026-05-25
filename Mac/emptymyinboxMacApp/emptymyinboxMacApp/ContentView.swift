//
//  ContentView.swift
//  emptymyinboxMacApp
//
//  Desktop shell: sidebar + detail; uses shared services and caches.
//

import SwiftUI
import EmptyMyInboxShared

struct ContentView: View {
    /// Persist sidebar “last refresh” times across app launches (UserDefaults).
    private enum SidebarRefreshPersistence {
        static let mailKey = "mac.sidebar.lastMailRefreshAt"
        static let calendarKey = "mac.sidebar.lastCalendarRefreshAt"
        static let actionItemsKey = "mac.sidebar.lastActionItemsRefreshAt"

        static func restore() -> (mail: Date?, calendar: Date?, actionItems: Date?) {
            let d = UserDefaults.standard
            return (
                d.object(forKey: mailKey) as? Date,
                d.object(forKey: calendarKey) as? Date,
                d.object(forKey: actionItemsKey) as? Date
            )
        }

        static func save(mail: Date?, calendar: Date?, actionItems: Date?) {
            let d = UserDefaults.standard
            if let mail { d.set(mail, forKey: mailKey) } else { d.removeObject(forKey: mailKey) }
            if let calendar { d.set(calendar, forKey: calendarKey) } else { d.removeObject(forKey: calendarKey) }
            if let actionItems { d.set(actionItems, forKey: actionItemsKey) } else { d.removeObject(forKey: actionItemsKey) }
        }

        static func clear() {
            let d = UserDefaults.standard
            d.removeObject(forKey: mailKey)
            d.removeObject(forKey: calendarKey)
            d.removeObject(forKey: actionItemsKey)
        }
    }

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
    @State private var lastMailRefreshAt: Date?
    @State private var lastCalendarRefreshAt: Date?
    @State private var lastActionItemsRefreshAt: Date?
    @State private var dashboardActionItems: [VaultActionItemRecord] = []
    @StateObject private var sidebarShortcutsStore = MacSidebarShortcutsStore()

    private var sidebarRefreshState: MacSidebarRefreshState {
        MacSidebarRefreshState(
            isRefreshingMail: isRefreshing,
            isRefreshingCalendar: calendarModel.isLoading,
            lastMailRefreshAt: lastMailRefreshAt,
            lastCalendarRefreshAt: lastCalendarRefreshAt,
            lastActionItemsRefreshAt: lastActionItemsRefreshAt
        )
    }

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
        .environmentObject(sidebarShortcutsStore)
        .sheet(isPresented: $showVaultSettings) {
            NavigationStack {
                MacVaultSettingsView()
            }
            .frame(minWidth: 440, minHeight: 400)
        }
        .sheet(isPresented: $showAppSettings) {
            SettingsContainerView(
                vaultSettings: { MacVaultSettingsView(showDismissToolbar: false) },
                isAddingAccount: $isAddingGmailAccount,
                onAddGmailAccount: { Task { await addGmailAccountFromSettings() } },
                onDismiss: { showAppSettings = false },
                accentColor: MacAppTheme.accent
            )
            .environmentObject(authManager)
            .frame(minWidth: 760, minHeight: 560)
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
        .onChange(of: authManager.sessionState) { _, new in
            if case .needsLogin = new {
                lastMailRefreshAt = nil
                lastCalendarRefreshAt = nil
                lastActionItemsRefreshAt = nil
                SidebarRefreshPersistence.clear()
            }
        }
    }

    @ViewBuilder
    private var mainChrome: some View {
        VStack(spacing: 0) {
            Group {
                switch rootTab {
                case .mail:
                    mailSplitView
                case .calendar:
                    MacVaultCalendarTab(
                        model: calendarModel,
                        snapshot: snapshot,
                        dashboardActionItems: dashboardActionItems,
                        isRefreshing: isRefreshing,
                        refreshMessage: refreshMessage,
                        refreshState: sidebarRefreshState,
                        onOpenSettings: { showAppSettings = true }
                    )
                case .actionItems:
                    MacVaultActionItemsTab(
                        calendarModel: calendarModel,
                        snapshot: snapshot,
                        dashboardActionItems: dashboardActionItems,
                        isRefreshing: isRefreshing,
                        refreshMessage: refreshMessage,
                        refreshState: sidebarRefreshState,
                        onOpenSettings: { showAppSettings = true }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacAppTheme.primaryBackground)

            Divider()
                .opacity(0.35)

            VaultRefreshStatusLabel(font: .caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacAppTheme.secondaryBackground.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppTheme.primaryBackground)
        .toolbar {
            ToolbarItem(placement: .principal) {
                MacRootTabBar(selection: $rootTab)
                    .frame(minWidth: 420, idealWidth: 520, maxWidth: 560)
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
        .onReceive(NotificationCenter.default.publisher(for: .macSelectRootTab)) { notification in
            guard let raw = notification.object as? Int, let tab = MacRootTab(rawValue: raw) else { return }
            rootTab = tab
        }
        .onReceive(NotificationCenter.default.publisher(for: .macCycleRootTabForward)) { _ in
            let order = MacRootTab.allCases
            guard let idx = order.firstIndex(of: rootTab) else { return }
            rootTab = order[(idx + 1) % order.count]
        }
        .onReceive(NotificationCenter.default.publisher(for: .macRefreshCurrentRootTab)) { _ in
            Task { await refreshCurrentTab() }
        }
        .onChange(of: rootTab) { _, _ in
            sidebarShortcutsStore.clearAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaultDidSync)) { _ in
            Task { await loadDashboardActionItems() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macActionItemsShouldReload)) { _ in
            Task { await loadDashboardActionItems() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .companionVaultCalendarActionItemsRefresh)) { _ in
            Task {
                await VaultManager.shared.performLifecycleSync(postNotification: false)
                await calendarModel.refresh()
                lastCalendarRefreshAt = Date()
                NotificationCenter.default.post(name: .macActionItemsShouldReload, object: nil)
                lastActionItemsRefreshAt = Date()
                persistSidebarRefreshTimestamps()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountAdded)) { _ in
            Task {
                await VaultManager.shared.performLifecycleSync(postNotification: false)
                await calendarModel.refresh()
                NotificationCenter.default.post(name: .macActionItemsShouldReload, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardNeedsUpdate)) { _ in
            Task { await loadSnapshot() }
        }
    }

    @ViewBuilder
    private var mailSplitView: some View {
        MacMailTabView(
            snapshot: $snapshot,
            isRefreshing: $isRefreshing,
            refreshMessage: $refreshMessage,
            calendarModel: calendarModel,
            dashboardActionItems: dashboardActionItems,
            refreshState: sidebarRefreshState,
            onRefreshMailbox: { Task { await refreshMailbox() } },
            onOpenSettings: { showAppSettings = true },
            onAddAccount: { Task { await addGmailAccountFromSettings() } }
        )
        .environmentObject(authManager)
        .background(MacAppTheme.primaryBackground)
        .task(id: authManager.sessionState) {
            if case .authenticated = authManager.sessionState {
                let restored = SidebarRefreshPersistence.restore()
                lastMailRefreshAt = restored.mail
                lastCalendarRefreshAt = restored.calendar
                lastActionItemsRefreshAt = restored.actionItems
                await loadSnapshot()
                await loadDashboardActionItems()
                NotificationCenter.default.post(name: .companionVaultCalendarActionItemsRefresh, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macActionItemsShouldReload)) { _ in
            lastActionItemsRefreshAt = Date()
            persistSidebarRefreshTimestamps()
        }
    }

    private func loadSnapshot() async {
        let loaded = await DashboardDataManager.shared.loadCachedSnapshot()
        snapshot = loaded
        // Prefer dashboard snapshot time (same as on-disk cache); keep UserDefaults restore if no snapshot yet.
        if let ts = loaded?.timestamp {
            lastMailRefreshAt = ts
        }
        persistSidebarRefreshTimestamps()
        if DashboardRefreshPolicy.shouldAutoSync(snapshot: loaded, now: Date()), !isRefreshing {
            await refreshMailbox()
        }
    }

    private func persistSidebarRefreshTimestamps() {
        SidebarRefreshPersistence.save(
            mail: lastMailRefreshAt,
            calendar: lastCalendarRefreshAt,
            actionItems: lastActionItemsRefreshAt
        )
    }

    private func loadDashboardActionItems() async {
        dashboardActionItems = (try? await VaultManager.shared.listActionItems()) ?? []
    }

    private func refreshMailbox() async {
        isRefreshing = true
        refreshMessage = nil
        defer { isRefreshing = false }
        await VaultManager.shared.performLifecycleSync(postNotification: false)
        _ = await DashboardDataManager.shared.refreshData(shouldSync: true, progressCallback: nil)
        await loadSnapshot()
        await loadDashboardActionItems()
        refreshMessage = "Updated \(snapshot?.timestamp.formatted(date: .abbreviated, time: .shortened) ?? "—")"
        NotificationCenter.default.post(name: .companionVaultCalendarActionItemsRefresh, object: nil)
    }

    private func refreshCurrentTab() async {
        switch rootTab {
        case .mail:
            await refreshMailbox()
        case .calendar:
            await VaultManager.shared.performLifecycleSync(postNotification: false)
            await calendarModel.refresh()
            lastCalendarRefreshAt = Date()
            persistSidebarRefreshTimestamps()
        case .actionItems:
            NotificationCenter.default.post(name: .macActionItemsShouldReload, object: nil)
            lastActionItemsRefreshAt = Date()
            persistSidebarRefreshTimestamps()
            Task { await loadDashboardActionItems() }
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

    /// Matches iOS foreground behavior: refresh mail when the cached snapshot is stale; companion tabs refresh via `refreshMailbox` notification.
    private func checkMacForegroundCompanionIfNeeded() {
        guard case .authenticated = authManager.sessionState else { return }
        Task {
            let cached: DashboardDataSnapshot?
            if let snapshot {
                cached = snapshot
            } else {
                cached = await DashboardDataManager.shared.loadCachedSnapshot()
            }
            guard DashboardRefreshPolicy.shouldAutoSync(snapshot: cached, now: Date()) else { return }
            await refreshMailbox()
        }
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

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}
