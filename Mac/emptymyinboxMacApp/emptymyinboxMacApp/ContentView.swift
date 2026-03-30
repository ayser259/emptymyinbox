//
//  ContentView.swift
//  emptymyinboxMacApp
//
//  Desktop shell: sidebar + detail; uses shared services and caches.
//

import SwiftUI
import EmptyMyInboxShared

private enum MacMainSection: String, CaseIterable, Identifiable {
    case dashboard
    case accounts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .accounts: return "Accounts"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .accounts: return "person.crop.circle"
        }
    }
}

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
    @State private var rootTab: MacRootTab = .mail
    @State private var selection: MacMainSection? = .dashboard
    @State private var snapshot: DashboardDataSnapshot?
    @State private var isRefreshing = false
    @State private var refreshMessage: String?
    @State private var showVaultSettings = false

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
        .frame(minWidth: 880, minHeight: 560)
        .background(MacAppTheme.primaryBackground)
        .sheet(isPresented: $showVaultSettings) {
            MacVaultSettingsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macOpenVaultSettings)) { _ in
            showVaultSettings = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task { await AppLifecycleCloudSync.pushLocalStateOnly() }
            }
        }
    }

    @ViewBuilder
    private var mainChrome: some View {
        VStack(spacing: 0) {
            macRootTabBar

            Group {
                switch rootTab {
                case .mail:
                    mailSplitView
                case .calendar:
                    MacVaultCalendarTab()
                case .actionItems:
                    MacVaultActionItemsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MacAppTheme.primaryBackground)
    }

    private var macRootTabBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                LogoView(size: 26)
                Text("Empty My Inbox")
                    .font(.headline)
                    .foregroundStyle(MacAppTheme.primaryText)
            }
            .frame(minWidth: 160, idealWidth: 200, maxWidth: 240, alignment: .leading)

            Picker("Main section", selection: $rootTab) {
                ForEach(MacRootTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 440)
            .layoutPriority(1)

            Group {
                Button {
                    showVaultSettings = true
                } label: {
                    Label("Vault", systemImage: "shippingbox")
                }
                .labelStyle(.iconOnly)
                .help("Vault storage settings")

                if rootTab == .mail {
                    Button {
                        Task { await refreshMailbox() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(isRefreshing)
                    .help("Refresh mailbox (⌘R)")
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            .frame(minWidth: 160, idealWidth: 200, maxWidth: 240, alignment: .trailing)
        }
        .padding(.horizontal, MacAppTheme.spacingMedium)
        .padding(.vertical, 10)
        .background(MacAppTheme.secondaryBackground.opacity(0.65))
    }

    @ViewBuilder
    private var mailSplitView: some View {
        NavigationSplitView {
            List(MacMainSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard:
                MacDashboardDetailView(
                    snapshot: snapshot,
                    isRefreshing: isRefreshing,
                    refreshMessage: refreshMessage,
                    onRefresh: { Task { await refreshMailbox() } }
                )
            case .accounts:
                MacAccountsListView(accounts: authManager.accounts)
            }
        }
        .background(MacAppTheme.primaryBackground)
        .task(id: authManager.sessionState) {
            if case .authenticated = authManager.sessionState {
                await loadSnapshot()
            }
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

private struct MacDashboardDetailView: View {
    let snapshot: DashboardDataSnapshot?
    let isRefreshing: Bool
    let refreshMessage: String?
    let onRefresh: () -> Void

    var body: some View {
        Group {
            if let snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            LogoView(size: 36)
                            Text("Dashboard")
                                .font(.title.bold())
                                .foregroundStyle(MacAppTheme.primaryText)
                            Spacer()
                            if isRefreshing {
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

private struct MacAccountsListView: View {
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
