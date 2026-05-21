//
//  iPadMailTabView.swift
//  emptyMyInbox
//
//  Wide iPad mail: NavigationSplitView with tools/mailboxes sidebar, thread list, detail.
//

import SwiftUI
import EmptyMyInboxShared

struct iPadMailTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var rootState: AdaptiveRootState

    @State private var snapshot: DashboardDataSnapshot?
    @State private var isRefreshing = false
    @State private var showLLMSettings = false
    @StateObject private var calendarModel = GoogleCalendarViewModel()
    @State private var dashboardActionItems: [VaultActionItemRecord] = []

    private var unreadCount: Int {
        snapshot?.emails.count ?? 0
    }

    var body: some View {
        NavigationSplitView {
            mailSidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            HStack(spacing: 0) {
                if case .mailbox = rootState.mailSidebarSelection {
                    iPadMailboxListColumn(
                        scope: mailboxScope,
                        snapshot: snapshot,
                        selectedThreadId: $rootState.selectedThreadId,
                        selectedThread: $rootState.selectedThread
                    )
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
                    .background(AppTheme.secondaryBackground)

                    Divider()
                        .background(AppTheme.accent.opacity(0.25))
                }

                NavigationStack(path: $rootState.mailNavigationPath) {
                    mailDetailContent
                        .navigationDestination(for: Int.self) { emailId in
                            EmailDetailView(emailId: emailId)
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(AppTheme.accent)
        .background(AppTheme.primaryBackground)
        .task {
            await loadSnapshot()
            await loadActionItems()
            await calendarModel.refreshIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardNeedsUpdate)) { _ in
            Task { await loadSnapshot() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appShouldRefreshData)) { _ in
            Task { await refreshMailbox() }
        }
        .sheet(isPresented: $showLLMSettings) {
            NavigationStack {
                LLMManagementView()
                    .primaryBackground()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showLLMSettings = false }
                                .textButton()
                        }
                    }
            }
        }
    }

    private var mailboxScope: MailboxScope {
        if case .mailbox(let scope) = rootState.mailSidebarSelection {
            return scope
        }
        return .all
    }

    // MARK: - Sidebar

    private var mailSidebar: some View {
        List {
            Section("Tools") {
                ForEach(AdaptiveRootState.MailTool.allCases) { tool in
                    iPadSidebarRow(
                        title: tool.title,
                        systemImage: tool.systemImage,
                        isSelected: rootState.mailSidebarSelection == .tool(tool)
                    ) {
                        rootState.selectMailSidebar(.tool(tool))
                    }
                }
            }

            Section {
                iPadSidebarRow(
                    title: "All Emails",
                    systemImage: "tray.2",
                    isSelected: rootState.mailSidebarSelection == .mailbox(.all)
                ) {
                    rootState.selectMailSidebar(.mailbox(.all))
                }
                iPadSidebarRow(
                    title: "All Unread",
                    systemImage: "envelope.badge",
                    badge: unreadCount > 0 ? unreadCount : nil,
                    isSelected: rootState.mailSidebarSelection == .mailbox(.allUnread)
                ) {
                    rootState.selectMailSidebar(.mailbox(.allUnread))
                }
                iPadSidebarRow(
                    title: "Saved",
                    systemImage: "star.fill",
                    isSelected: rootState.mailSidebarSelection == .mailbox(.saved)
                ) {
                    rootState.selectMailSidebar(.mailbox(.saved))
                }
                iPadSidebarRow(
                    title: "Sent",
                    systemImage: "paperplane.fill",
                    isSelected: rootState.mailSidebarSelection == .mailbox(.sent)
                ) {
                    rootState.selectMailSidebar(.mailbox(.sent))
                }

                ForEach(authManager.accounts) { account in
                    iPadSidebarRow(
                        title: account.email,
                        systemImage: "envelope.circle",
                        isSelected: rootState.mailSidebarSelection == .mailbox(.account(email: account.email))
                    ) {
                        rootState.selectMailSidebar(.mailbox(.account(email: account.email)))
                    }
                }
            } header: {
                HStack {
                    Text("Accounts")
                        .font(AppTheme.subheadline.weight(.semibold))
                        .secondaryText()
                    Spacer()
                    Button {
                        Task { await addGmailAccount() }
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Add Google account")
                }
            }

            Section {
                Button {
                    Task { await refreshMailbox() }
                } label: {
                    Label(isRefreshing ? "Refreshing…" : "Refresh mailbox", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(AppTheme.primaryBackground)
        .navigationTitle("Mail")
    }

    // MARK: - Detail

    @ViewBuilder
    private var mailDetailContent: some View {
        switch rootState.mailSidebarSelection {
        case .tool(let tool):
            toolDetail(tool)
        case .mailbox:
            mailboxDetail
        }
    }

    @ViewBuilder
    private var mailboxDetail: some View {
        if let thread = rootState.selectedThread, thread.key.hasValidThreadId {
            EmailThreadDetailScreen(summary: thread)
                .id(thread.id)
        } else if let emailId = rootState.selectedThreadId {
            EmailDetailView(emailId: emailId)
                .id(emailId)
        } else {
            ContentUnavailableView {
                Label("No Message Selected", systemImage: "envelope.open")
            } description: {
                Text("Select a message in the list.")
            }
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    @ViewBuilder
    private func toolDetail(_ tool: AdaptiveRootState.MailTool) -> some View {
        switch tool {
        case .dashboard:
            DashboardView(isMenuPresented: $rootState.showMenu)
                .environmentObject(authManager)
        case .catchUp:
            CatchUpView()
                .environmentObject(authManager)
        case .stories:
            if let snap = snapshot {
                NewsletterInsightDeckView(
                    emails: snap.allEmails,
                    onDiveDeeper: { emailId in
                        rootState.mailNavigationPath.append(emailId)
                    },
                    onOpenLLMSettings: { showLLMSettings = true }
                )
                .id(snap.timestamp)
            } else {
                iPadMailPlaceholder(
                    title: "Stories",
                    systemImage: "rectangle.stack.fill",
                    message: "Refresh your mailbox to load newsletter data."
                )
            }
        case .brief:
            if let snap = snapshot {
                DailyBriefingTabView(
                    allEmails: snap.allEmails,
                    onItemTap: { item in
                        rootState.mailNavigationPath.append(item.emailId)
                    },
                    onOpenLLMSettings: { showLLMSettings = true }
                )
                .id(snap.timestamp)
            } else {
                iPadMailPlaceholder(
                    title: "Daily Briefing",
                    systemImage: "sparkles",
                    message: "Refresh your mailbox to load briefing data."
                )
            }
        }
    }

    // MARK: - Data

    private func loadSnapshot() async {
        snapshot = await DashboardDataManager.shared.loadCachedSnapshot()
        if snapshot == nil, !isRefreshing {
            await refreshMailbox()
        }
    }

    private func loadActionItems() async {
        dashboardActionItems = (try? await VaultManager.shared.listActionItems()) ?? []
    }

    private func refreshMailbox() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await VaultManager.shared.performLifecycleSync(postNotification: false)
        _ = await DashboardDataManager.shared.refreshData(shouldSync: true, progressCallback: nil)
        await loadSnapshot()
        await loadActionItems()
        await calendarModel.refreshIfNeeded()
        NotificationCenter.default.post(name: .companionVaultCalendarActionItemsRefresh, object: nil)
    }

    private func addGmailAccount() async {
        do {
            try await authManager.signInWithGoogle()
        } catch {
            logError("Add account failed: \(error)", category: "Auth")
        }
    }
}

// MARK: - Mailbox list column

private struct iPadMailboxListColumn: View {
    let scope: MailboxScope
    let snapshot: DashboardDataSnapshot?
    @Binding var selectedThreadId: Int?
    @Binding var selectedThread: EmailThreadSummary?

    @State private var readFilter: MailboxReadFilter = .all

    private var displayConfig: MailboxDisplayConfig {
        MailboxDisplayConfig.forScope(scope, readFilter: readFilter)
    }

    private var threadRows: [EmailThreadSummary] {
        guard let snapshot else { return [] }
        return MailboxThreadQuery.threads(in: snapshot, scope: scope, readFilter: readFilter)
    }

    private var showsAccountOnRows: Bool {
        switch scope {
        case .all, .allUnread, .saved, .sent:
            return true
        case .account, .accountSaved, .accountSent:
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if displayConfig.showsReadFilterChips {
                MailboxReadFilterBar(selection: $readFilter)
                Divider().opacity(0.3)
            }

            if threadRows.isEmpty {
                MailboxEmptyStateView(config: displayConfig)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedThreadId) {
                    if displayConfig.showsUnreadCountHeader {
                        let unreadCount = threadRows.reduce(0) { $0 + $1.unreadCount }
                        if unreadCount > 0 {
                            Section {
                                MailboxUnreadCountHeader(count: unreadCount)
                            }
                        }
                    }

                    ForEach(threadRows) { thread in
                        MailboxThreadEmailRow(thread: thread, showsAccountEmail: showsAccountOnRows)
                            .tag(Optional(thread.id))
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(displayConfig.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scope) { _, _ in
            readFilter = .all
            selectedThreadId = nil
            selectedThread = nil
        }
        .onChange(of: selectedThreadId) { _, newId in
            guard let newId else {
                selectedThread = nil
                return
            }
            selectedThread = threadRows.first { $0.id == newId }
        }
        .onChange(of: readFilter) { _, _ in
            selectedThreadId = nil
            selectedThread = nil
        }
    }
}

// MARK: - Sidebar row

private struct iPadSidebarRow: View {
    let title: String
    let systemImage: String
    var badge: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(AppTheme.body)
                    .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
                Spacer()
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryBackground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.accent))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isSelected
                ? AppTheme.secondaryBackground
                : Color.clear
        )
    }
}

private struct iPadMailPlaceholder: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .foregroundStyle(AppTheme.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.primaryBackground)
    }
}
