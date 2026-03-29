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

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authManager: AuthManager
    @State private var selection: MacMainSection? = .dashboard
    @State private var snapshot: DashboardDataSnapshot?
    @State private var isRefreshing = false
    @State private var refreshMessage: String?

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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task { await AppLifecycleCloudSync.pushLocalStateOnly() }
            }
        }
    }

    @ViewBuilder
    private var mainChrome: some View {
        NavigationSplitView {
            List(MacMainSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await refreshMailbox() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                    .help("Refresh mailbox (⌘R)")
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
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
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Empty My Inbox")
                .font(.largeTitle.weight(.semibold))
            Text("Sign in with Google to load your Gmail accounts and dashboard.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if authManager.isLoading {
                ProgressView()
                    .scaleEffect(1.1)
            } else {
                Button {
                    Task { await signIn() }
                } label: {
                    Label("Sign in with Google", systemImage: "person.crop.circle.badge.plus")
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 420)
            }
        }
        .padding(40)
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
            ProgressView()
            Text("Loading…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            Text("Dashboard")
                                .font(.title.bold())
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
                                        .lineLimit(1)
                                    Text("\(unreadCount(snapshot: snapshot, accountEmail: account.email)) unread")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(.quaternary.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }

                        Text("Last snapshot: \(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text("Tip: Use ⌘R to refresh mailbox data from Gmail.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                Text("Gmail account")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Accounts")
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}
