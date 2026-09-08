//
//  ContentView.swift
//  ProjectJadeMac
//
//  Desktop shell: sidebar + detail; uses shared services and caches.
//

import SwiftUI
import ProjectJadeShared

struct ContentView: View {
    private enum SidebarRefreshPersistence {
        static let mailKey = "mac.sidebar.lastMailRefreshAt"

        static func restore() -> Date? {
            UserDefaults.standard.object(forKey: mailKey) as? Date
        }

        static func save(mail: Date?) {
            let d = UserDefaults.standard
            if let mail { d.set(mail, forKey: mailKey) } else { d.removeObject(forKey: mailKey) }
        }

        static func clear() {
            UserDefaults.standard.removeObject(forKey: mailKey)
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appearanceSettings: AppearanceSettingsStore
    @State private var snapshot: DashboardDataSnapshot?
    @State private var isRefreshing = false
    @State private var refreshMessage: String?
    @State private var showAppSettings = false
    @State private var isAddingGmailAccount = false
    @State private var lastMailRefreshAt: Date?
    @StateObject private var sidebarShortcutsStore = MacSidebarShortcutsStore()

    private var sidebarRefreshState: MacSidebarRefreshState {
        MacSidebarRefreshState(
            isRefreshingMail: isRefreshing,
            lastMailRefreshAt: lastMailRefreshAt
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
        .sheet(isPresented: $showAppSettings) {
            SettingsContainerView(
                isAddingAccount: $isAddingGmailAccount,
                onAddGmailAccount: { Task { await addGmailAccountFromSettings() } },
                onDismiss: { showAppSettings = false },
                accentColor: appearanceSettings.resolvedPalette.accent
            )
            .environmentObject(authManager)
            .frame(minWidth: 760, minHeight: 560)
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
                SidebarRefreshPersistence.clear()
            }
        }
    }

    @ViewBuilder
    private var mainChrome: some View {
        mailSplitView
            .id(appearanceSettings.paletteRevision)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacAppTheme.primaryBackground)
            .tint(appearanceSettings.resolvedPalette.accent)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await refreshMailbox() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(isRefreshing)
                    .help("Refresh mail (⌘R)")
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        .toolbarBackground(MacAppTheme.secondaryBackground.opacity(0.65), for: .windowToolbar)
        .onReceive(NotificationCenter.default.publisher(for: .macRefreshCurrentRootTab)) { _ in
            Task { await refreshMailbox() }
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
            refreshState: sidebarRefreshState,
            onRefreshMailbox: { Task { await refreshMailbox() } },
            onOpenSettings: { showAppSettings = true },
            onAddAccount: { Task { await addGmailAccountFromSettings() } }
        )
        .environmentObject(authManager)
        .background(MacAppTheme.primaryBackground)
        .task(id: authManager.sessionState) {
            if case .authenticated = authManager.sessionState {
                lastMailRefreshAt = SidebarRefreshPersistence.restore()
                await loadSnapshot()
            }
        }
    }

    private func loadSnapshot() async {
        let loaded = await DashboardDataManager.shared.loadCachedSnapshot()
        snapshot = loaded
        if let ts = loaded?.timestamp {
            lastMailRefreshAt = ts
        }
        SidebarRefreshPersistence.save(mail: lastMailRefreshAt)
        if DashboardRefreshPolicy.shouldAutoSync(snapshot: loaded, now: Date()), !isRefreshing {
            await refreshMailbox()
        }
    }

    private func refreshMailbox() async {
        isRefreshing = true
        refreshMessage = nil
        defer { isRefreshing = false }
        _ = await DashboardDataManager.shared.refreshData(shouldSync: true, progressCallback: nil)
        await loadSnapshot()
        let stamp = snapshot?.timestamp.formatted(date: .abbreviated, time: .shortened) ?? "—"
        refreshMessage = "Updated \(stamp)"
    }

    private func addGmailAccountFromSettings() async {
        isAddingGmailAccount = true
        defer { isAddingGmailAccount = false }
        do {
            try await authManager.signInWithGoogle()
        } catch {
            logError("Add account failed: (error)", category: "Auth")
        }
    }

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
    @EnvironmentObject private var appearanceSettings: AppearanceSettingsStore
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            BrandedLogoView(size: 88)
            Text(appearanceSettings.resolvedDisplayName)
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
    @EnvironmentObject private var appearanceSettings: AppearanceSettingsStore

    var body: some View {
        VStack(spacing: 16) {
            BrandedLogoView(size: 64)
            ProgressView()
                .tint(appearanceSettings.resolvedPalette.accent)
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
