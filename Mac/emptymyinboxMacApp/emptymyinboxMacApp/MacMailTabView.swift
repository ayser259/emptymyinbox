//
//  MacMailTabView.swift
//  emptymyinboxMacApp
//
//  Mail: sidebar (carousel parity) + detail with navigation.
//

import SwiftUI
import EmptyMyInboxShared

private enum MacMailSidebarItem: String, CaseIterable, Identifiable {
    case dashboard
    case catchUp
    case stories
    case brief
    case allEmails
    case senders
    case saved
    case accounts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .catchUp: return "Catch Up"
        case .stories: return "Stories"
        case .brief: return "Brief"
        case .allEmails: return "All Emails"
        case .senders: return "Senders"
        case .saved: return "Saved"
        case .accounts: return "Accounts"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .catchUp: return "tray.full"
        case .stories: return "rectangle.stack.fill"
        case .brief: return "sparkles"
        case .allEmails: return "envelope"
        case .senders: return "person.2.fill"
        case .saved: return "star.fill"
        case .accounts: return "person.crop.circle"
        }
    }
}

struct MacMailTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Binding var snapshot: DashboardDataSnapshot?
    @Binding var isRefreshing: Bool
    @Binding var refreshMessage: String?
    var onRefreshMailbox: () -> Void
    var onOpenSettings: () -> Void

    @State private var selection: MacMailSidebarItem = .dashboard
    @State private var navigationPath = NavigationPath()
    @State private var showBriefSheet = false
    @State private var briefingPayload: DailyBriefingPayload?
    @State private var showLLMSettings = false

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    ForEach(MacMailSidebarItem.allCases) { item in
                        sidebarRow(item)
                    }
                }
                Section {
                    Button {
                        onOpenSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
            .scrollContentBackground(.hidden)
        } detail: {
            NavigationStack(path: $navigationPath) {
                detailContent
                    .navigationDestination(for: Int.self) { emailId in
                        MacCachedEmailDetailView(emailId: emailId)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MacAppTheme.primaryBackground)
        .sheet(isPresented: $showBriefSheet) {
            if let briefingPayload {
                DailyBriefingSheet(
                    payload: briefingPayload,
                    onItemTap: { item in
                        navigationPath.append(item.emailId)
                        showBriefSheet = false
                    },
                    onDismiss: { showBriefSheet = false }
                )
                .frame(minWidth: 480, minHeight: 400)
            }
        }
        .sheet(isPresented: $showLLMSettings) {
            NavigationStack {
                LLMManagementView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showLLMSettings = false }
                        }
                    }
            }
            .frame(minWidth: 520, minHeight: 560)
        }
    }

    @ViewBuilder
    private func sidebarRow(_ item: MacMailSidebarItem) -> some View {
        switch item {
        case .brief:
            Button {
                Task { await presentBrief() }
            } label: {
                Label(item.title, systemImage: item.systemImage)
            }
        default:
            Button {
                selection = item
                navigationPath = NavigationPath()
            } label: {
                Label(item.title, systemImage: item.systemImage)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .dashboard:
            MacDashboardDetailView(
                snapshot: snapshot,
                isRefreshing: isRefreshing,
                refreshMessage: refreshMessage,
                onRefresh: onRefreshMailbox
            )
        case .catchUp:
            MacCatchUpLiteView(navigationPath: $navigationPath)
                .environmentObject(authManager)
        case .stories:
            NewsletterInsightDeckView(
                emails: snapshot?.allEmails ?? [],
                onDiveDeeper: { id in navigationPath.append(id) },
                onOpenLLMSettings: { showLLMSettings = true }
            )
        case .brief:
            ContentUnavailableView {
                Label("Daily Briefing", systemImage: "sparkles")
            } description: {
                Text("Choose Brief in the sidebar or wait for generation.")
            }
        case .allEmails:
            MacSimpleEmailListView(mode: .all, snapshot: snapshot, path: $navigationPath)
        case .senders:
            MacSimpleEmailListView(mode: .senders, snapshot: snapshot, path: $navigationPath)
        case .saved:
            MacSimpleEmailListView(mode: .starred, snapshot: snapshot, path: $navigationPath)
        case .accounts:
            MacAccountsListView(accounts: authManager.accounts)
        }
    }

    private func presentBrief() async {
        guard let snap = snapshot else { return }
        let payload = await DailyBriefingEngine.shared.buildPayload(from: snap.allEmails, sinceDate: nil)
        await MainActor.run {
            briefingPayload = payload
            showBriefSheet = true
        }
    }
}

// MARK: - Catch Up (desktop list + detail; same data pipeline as iOS deck)

private struct MacCatchUpLiteView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Binding var navigationPath: NavigationPath
    @StateObject private var loader = LazyEmailLoader()

    var body: some View {
        Group {
            if loader.isLoadingMetadata {
                ProgressView("Loading…")
            } else if loader.emailMetadata.isEmpty {
                ContentUnavailableView {
                    Label("All caught up", systemImage: "checkmark.circle")
                } description: {
                    Text("No unread emails in this view.")
                }
            } else {
                List {
                    ForEach(loader.emailMetadata, id: \.id) { meta in
                        Button {
                            navigationPath.append(meta.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meta.subject.isEmpty ? "(No subject)" : meta.subject)
                                    .foregroundStyle(MacAppTheme.primaryText)
                                Text(meta.sender ?? "")
                                    .font(.caption)
                                    .foregroundStyle(MacAppTheme.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Catch Up")
        .task {
            await loader.loadMetadata()
        }
    }
}

// MARK: - Simple lists from snapshot

private enum MacEmailListMode {
    case all
    case starred
    case senders
}

private struct MacSimpleEmailListView: View {
    let mode: MacEmailListMode
    let snapshot: DashboardDataSnapshot?
    @Binding var path: NavigationPath

    private var title: String {
        switch mode {
        case .all: return "All Emails"
        case .starred: return "Saved"
        case .senders: return "Senders"
        }
    }

    private var rows: [EmailListItem] {
        guard let snapshot else { return [] }
        switch mode {
        case .all:
            return snapshot.allEmails
        case .starred:
            return snapshot.allEmails.filter(\.is_starred)
        case .senders:
            return snapshot.allEmails
        }
    }

    var body: some View {
        Group {
            if mode == .senders {
                MacSendersAggregatedView(emails: rows, path: $path)
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label("No messages", systemImage: "envelope")
                }
            } else {
                List {
                    ForEach(rows, id: \.id) { email in
                        Button {
                            path.append(email.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(email.subject)
                                    .foregroundStyle(MacAppTheme.primaryText)
                                Text(email.sender)
                                    .font(.caption)
                                    .foregroundStyle(MacAppTheme.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(title)
    }
}

private struct MacSendersAggregatedView: View {
    let emails: [EmailListItem]
    @Binding var path: NavigationPath

    private var grouped: [(sender: String, count: Int, sampleId: Int)] {
        let dict = Dictionary(grouping: emails, by: { $0.sender })
        return dict.map { (sender, list) in
            (sender, list.count, list.first?.id ?? 0)
        }
        .sorted { $0.sender.localizedCaseInsensitiveCompare($1.sender) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.sender) { g in
                Button {
                    path.append(g.sampleId)
                } label: {
                    HStack {
                        Text(g.sender)
                            .foregroundStyle(MacAppTheme.primaryText)
                        Spacer()
                        Text("\(g.count)")
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Email detail from cache

private struct MacCachedEmailDetailView: View {
    let emailId: Int
    @State private var detail: EmailDetail?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(detail.subject)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(MacAppTheme.primaryText)
                        Text(detail.sender)
                            .foregroundStyle(MacAppTheme.secondaryText)
                        Divider().opacity(0.3)
                        Text(detail.body_text.isEmpty ? (detail.snippet) : detail.body_text)
                            .font(.body)
                            .foregroundStyle(MacAppTheme.primaryText)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView {
                    Label("Could not load email", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .navigationTitle("Email")
        .task {
            detail = await EmailCache.shared.loadEmailDetail(emailId: emailId)
            isLoading = false
        }
    }
}
