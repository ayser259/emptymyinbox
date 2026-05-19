//
//  MacMailTabView.swift
//  emptymyinboxMacApp
//
//  Mail: three-pane shell (Tools / Accounts sidebar, mailbox list, detail).
//

import SwiftUI
import EmptyMyInboxShared

// MARK: - Sidebar selection

private enum MailTool: String, CaseIterable, Identifiable {
    case dashboard
    case catchUp
    case stories
    case brief

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .catchUp: return "Catch Up"
        case .stories: return "Stories"
        case .brief: return "Brief"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .catchUp: return "tray.full"
        case .stories: return "rectangle.stack.fill"
        case .brief: return "sparkles"
        }
    }
}

private enum MailMailboxScope: Hashable {
    case all
    case allUnread
    case saved
    case account(String)

    var mailboxScope: MailboxScope {
        switch self {
        case .all: return .all
        case .allUnread: return .allUnread
        case .saved: return .saved
        case .account(let email): return .account(email: email)
        }
    }
}

private enum MailSidebarSelection: Hashable {
    case tool(MailTool)
    case mailbox(MailMailboxScope)
}

// MARK: - Mail tab

struct MacMailTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var sidebarShortcutsStore: MacSidebarShortcutsStore
    @Binding var snapshot: DashboardDataSnapshot?
    @Binding var isRefreshing: Bool
    @Binding var refreshMessage: String?
    @ObservedObject var calendarModel: GoogleCalendarViewModel
    let dashboardActionItems: [VaultActionItemRecord]
    var refreshState: MacSidebarRefreshState = .init()
    var onRefreshMailbox: () -> Void
    var onOpenSettings: () -> Void
    var onAddAccount: () -> Void

    @State private var selection: MailSidebarSelection = .tool(.dashboard)
    @State private var navigationPath = NavigationPath()
    @State private var selectedEmailId: Int?
    @State private var showLLMSettings = false

    var body: some View {
        // Two-column split only: a three-column NavigationSplitView on macOS often collapses the
        // sidebar on selection. The mailbox list lives beside the main content inside the detail column.
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            HStack(spacing: 0) {
                if case .mailbox(let scope) = selection {
                    NavigationStack {
                        MacMailboxListColumn(scope: scope, snapshot: snapshot, selectedEmailId: $selectedEmailId)
                    }
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 480)
                    .background(MacAppTheme.secondaryBackground)

                    Divider()
                        .opacity(0.35)
                }

                NavigationStack(path: $navigationPath) {
                    detailContent
                        .navigationDestination(for: Int.self) { emailId in
                            MacCachedEmailDetailView(emailId: emailId)
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(MacAppTheme.accent)
        .background(MacAppTheme.primaryBackground)
        .onChange(of: selection) { _, _ in
            navigationPath = NavigationPath()
            selectedEmailId = nil
            sidebarShortcutsStore.removeLayers(withPrefix: "mail.")
            sidebarShortcutsStore.removeLayers(withPrefix: "catchup.")
            applyMailToolsShortcutLayer()
        }
        .onAppear {
            applyMailToolsShortcutLayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macSelectMailTool)) { notification in
            guard let rawValue = notification.object as? String,
                  let tool = MailTool(rawValue: rawValue) else { return }
            selection = .tool(tool)
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

    /// snapshot.emails is the authoritative unread-only list built during refresh.
    private var unreadCount: Int {
        snapshot?.emails.count ?? 0
    }

    private func applyMailToolsShortcutLayer() {
        sidebarShortcutsStore.setLayer(
            id: "mail.tools",
            title: "Mail",
            shortcuts: MacSidebarShortcutLibrary.mailTools,
            priority: 10
        )
    }

    private var sidebar: some View {
        MacSidebarShell(
            onRefresh: onRefreshMailbox,
            onOpenSettings: onOpenSettings,
            refreshState: refreshState
        ) {
            Section("Tools") {
                ForEach(MailTool.allCases) { tool in
                    MacSidebarListRowButton(
                        title: tool.title,
                        icon: .system(tool.systemImage),
                        isSelected: selection == .tool(tool),
                        action: { selection = .tool(tool) }
                    )
                }
            }
            Section {
                MacSidebarListRowButton(
                    title: "All Emails",
                    icon: .system("tray.2"),
                    isSelected: selection == .mailbox(.all),
                    action: { selection = .mailbox(.all) }
                )
                MacSidebarListRowButton(
                    title: "All Unread",
                    icon: .system("envelope.badge"),
                    isSelected: selection == .mailbox(.allUnread),
                    badge: unreadCount,
                    action: { selection = .mailbox(.allUnread) }
                )
                MacSidebarListRowButton(
                    title: "Saved",
                    icon: .system("star.fill"),
                    isSelected: selection == .mailbox(.saved),
                    action: { selection = .mailbox(.saved) }
                )

                ForEach(authManager.accounts) { account in
                    MacSidebarListRowButton(
                        title: account.email,
                        icon: .system("envelope.circle"),
                        isSelected: selection == .mailbox(.account(account.email)),
                        action: { selection = .mailbox(.account(account.email)) }
                    )
                }
            } header: {
                HStack {
                    Text("Accounts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MacAppTheme.secondaryText)
                    Spacer()
                    Menu {
                        Button {
                            onAddAccount()
                        } label: {
                            Label("Add Google Account", systemImage: "person.crop.circle.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body)
                            .foregroundStyle(MacAppTheme.secondaryText)
                            .frame(minWidth: 28, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .help("Add account")
                }
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .tool(let tool):
            toolDetail(tool)
        case .mailbox:
            if let selectedEmailId {
                MacCachedEmailDetailView(emailId: selectedEmailId)
                .id(selectedEmailId)
            } else {
                ContentUnavailableView {
                    Label("No Message Selected", systemImage: "envelope.open")
                } description: {
                    Text("Select a message in the list.")
                }
                .foregroundStyle(MacAppTheme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func toolDetail(_ tool: MailTool) -> some View {
        switch tool {
        case .dashboard:
            MacUnifiedDashboardView(
                calendarModel: calendarModel,
                snapshot: snapshot,
                actionItems: dashboardActionItems,
                isRefreshing: isRefreshing,
                refreshMessage: refreshMessage,
                onOpenMailbox: { email in
                    selection = .mailbox(.account(email))
                },
                onOpenCatchUp: {
                    selection = .tool(.catchUp)
                },
                onOpenBrief: {
                    selection = .tool(.brief)
                },
                onOpenStories: {
                    selection = .tool(.stories)
                }
            )
        case .catchUp:
            MacCatchUpFeedView {
                selection = .tool(.dashboard)
            }
        case .stories:
            Group {
                if let snap = snapshot {
                    NewsletterInsightDeckView(
                        emails: snap.allEmails,
                        onDiveDeeper: { id in navigationPath.append(id) },
                        onOpenLLMSettings: { showLLMSettings = true }
                    )
                    .id(snap.timestamp)
                } else {
                    ContentUnavailableView {
                        Label("Stories", systemImage: "rectangle.stack.fill")
                    } description: {
                        Text("Refresh your mailbox to load newsletter data for stories.")
                    }
                }
            }
        case .brief:
            Group {
                if let snap = snapshot {
                    DailyBriefingTabView(
                        allEmails: snap.allEmails,
                        onItemTap: { item in
                            navigationPath.append(item.emailId)
                        },
                        onOpenLLMSettings: { showLLMSettings = true }
                    )
                    .id(snap.timestamp)
                } else {
                    ContentUnavailableView {
                        Label("Daily Briefing", systemImage: "sparkles")
                    } description: {
                        Text("Refresh your mailbox to load briefing data.")
                    }
                }
            }
        }
    }

}

// MARK: - Mailbox list (middle column)

private struct MacMailboxListColumn: View {
    let scope: MailMailboxScope
    let snapshot: DashboardDataSnapshot?
    @Binding var selectedEmailId: Int?

    @State private var readFilter: MailboxReadFilter = .all

    private var displayConfig: MailboxDisplayConfig {
        MailboxDisplayConfig.forScope(scope.mailboxScope, readFilter: readFilter)
    }

    private var rows: [EmailListItem] {
        guard let snapshot else { return [] }
        return MailboxQuery.emails(in: snapshot, scope: scope.mailboxScope, readFilter: readFilter)
    }

    private var title: String {
        displayConfig.navigationTitle
    }

    private var showReadFilterChips: Bool {
        displayConfig.showsReadFilterChips
    }

    private var showsAccountOnRows: Bool {
        switch scope {
        case .all, .allUnread, .saved:
            return true
        case .account:
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showReadFilterChips {
                readFilterBar
                Divider().opacity(0.3)
            }

            if rows.isEmpty {
                MailboxEmptyStateView(config: displayConfig)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedEmailId) {
                    if displayConfig.showsUnreadCountHeader {
                        let unreadCount = rows.filter { !$0.is_read }.count
                        if unreadCount > 0 {
                            Section {
                                MailboxUnreadCountHeader(count: unreadCount)
                            }
                        }
                    }

                    ForEach(rows, id: \.id) { email in
                        MailboxEmailRow(email: email, showsAccountEmail: showsAccountOnRows)
                            .tag(Optional(email.id))
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(title)
        // Reset filter when the scope changes so we don't land on an empty "Read" view
        .onChange(of: scope) { _, _ in readFilter = .all }
    }

    private var readFilterBar: some View {
        MailboxReadFilterBar(selection: $readFilter)
            .background(MacAppTheme.primaryBackground)
    }
}

// MARK: - Email detail (cache → Gmail API fallback, matches iOS EmailDetailView)

private struct MacCachedEmailDetailView: View {
    let emailId: Int
    @EnvironmentObject private var sidebarShortcutsStore: MacSidebarShortcutsStore
    @State private var detail: EmailDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var hasUnsubscribeAvailable = false
    @State private var showUnsubscribeWebView = false
    @State private var unsubscribeManualURL: URL?
    @State private var replyPresentation: ReplyComposerPresentation?
    @StateObject private var keyboardMonitor = MacMailDetailKeyboardMonitor()

    var body: some View {
        MacReplyComposerSlideInContainer(replyPresentation: $replyPresentation) {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let detail {
                    emailDetailContent(detail)
                } else {
                    ContentUnavailableView {
                        Label("Could not load email", systemImage: "exclamationmark.triangle")
                    } description: {
                        if let msg = errorMessage { Text(msg) }
                    }
                }
            }
        }
        .navigationTitle("Email")
        .task { await loadEmail() }
        .onAppear {
            keyboardMonitor.installIfNeeded()
            syncKeyboardMonitor()
        }
        .onDisappear {
            keyboardMonitor.remove()
            sidebarShortcutsStore.removeLayer(id: "mail.reading")
            sidebarShortcutsStore.removeLayer(id: "mail.replyComposer")
        }
        .onChange(of: replyPresentation?.id) { _, _ in
            syncKeyboardMonitor()
            syncSidebarShortcuts()
        }
        .onChange(of: detail?.id) { _, _ in
            syncKeyboardMonitor()
            syncSidebarShortcuts()
        }
        .onChange(of: hasUnsubscribeAvailable) { _, _ in
            syncKeyboardMonitor()
            syncSidebarShortcuts()
        }
        .sheet(isPresented: $showUnsubscribeWebView) {
            if let url = unsubscribeManualURL {
                UnsubscribeWebView(url: url)
            }
        }
    }

    private var isReplyAllMeaningful: Bool {
        guard let detail else { return false }
        return ReplyRecipientResolver.isReplyAllMeaningful(email: detail)
    }

    // MARK: - Content layout

    private func emailDetailContent(_ detail: EmailDetail) -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(detail.sender_name?.isEmpty == false ? (detail.sender_name ?? detail.sender) : detail.sender)
                            .font(.headline)
                            .foregroundStyle(MacAppTheme.primaryText)
                        Spacer(minLength: 8)
                        Text(formattedDate(detail.received_at))
                            .font(.caption)
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
                    Text(detail.subject.isEmpty ? "(No subject)" : detail.subject)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MacAppTheme.primaryText)
                    if let to = detail.recipients_to, !to.isEmpty {
                        Text("To: \(to)")
                            .font(.caption)
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacAppTheme.secondaryBackground)

                Divider().opacity(0.35)

                emailBody(detail, availableHeight: geo.size.height - 160)

                EmailReadingActionBar(
                    email: self.detail,
                    isDisabled: isProcessing,
                    hasUnsubscribe: $hasUnsubscribeAvailable,
                    handlers: mailDetailReadingHandlers(for: detail)
                )
            }
        }
    }

    private func mailDetailReadingHandlers(for detail: EmailDetail) -> EmailReadingActionHandlers {
        EmailReadingActionHandlers(
            onReply: { openReply(mode: .reply, for: detail) },
            onReplyAll: { openReply(mode: .replyAll, for: detail) },
            onStar: { Task { await handleStar() } },
            onMarkUnread: { Task { await handleMarkUnread() } },
            onMarkAsRead: { Task { await handleMarkAsRead() } },
            onUnsubscribe: { Task { await handleUnsubscribe() } }
        )
    }

    private func openReply(mode: ReplyMode, for detail: EmailDetail) {
        replyPresentation = ReplyComposerPresentation(email: detail, mode: mode)
        syncSidebarShortcuts()
    }

    private func syncKeyboardMonitor() {
        keyboardMonitor.isReplyComposerOpen = replyPresentation != nil
        keyboardMonitor.isEnabled = detail != nil && !isLoading && errorMessage == nil && !isProcessing
        keyboardMonitor.hasUnsubscribe = hasUnsubscribeAvailable
        if let detail {
            keyboardMonitor.isReplyAllMeaningful = ReplyRecipientResolver.isReplyAllMeaningful(email: detail)
            keyboardMonitor.onReply = { openReply(mode: .reply, for: detail) }
            keyboardMonitor.onReplyAll = { openReply(mode: .replyAll, for: detail) }
            keyboardMonitor.onKeepUnread = { Task { await handleMarkUnread() } }
            keyboardMonitor.onStar = { Task { await handleStar() } }
            keyboardMonitor.onMarkAsRead = { Task { await handleMarkAsRead() } }
            keyboardMonitor.onUnsubscribe = { Task { await handleUnsubscribe() } }
        }
    }

    private func syncSidebarShortcuts() {
        if replyPresentation != nil {
            sidebarShortcutsStore.removeLayer(id: "mail.reading")
            sidebarShortcutsStore.setLayer(
                id: "mail.replyComposer",
                title: "Reply composer",
                shortcuts: MacSidebarShortcutLibrary.mailReplyComposer,
                priority: 30
            )
            return
        }
        sidebarShortcutsStore.removeLayer(id: "mail.replyComposer")

        guard detail != nil else {
            sidebarShortcutsStore.removeLayer(id: "mail.reading")
            return
        }
        var items: [MacSidebarContextualShortcut] = [
            MacSidebarContextualShortcut(title: "Keep unread", shortcutDisplay: "K"),
            MacSidebarContextualShortcut(title: "Star", shortcutDisplay: "S"),
            MacSidebarContextualShortcut(title: "Mark as read", shortcutDisplay: "E"),
            MacSidebarContextualShortcut(title: "Reply", shortcutDisplay: "R"),
        ]
        if isReplyAllMeaningful {
            items.append(MacSidebarContextualShortcut(title: "Reply All", shortcutDisplay: "⇧R"))
        }
        if hasUnsubscribeAvailable {
            items.append(MacSidebarContextualShortcut(title: "Unsubscribe", shortcutDisplay: "⌘⇧U"))
        }
        sidebarShortcutsStore.setLayer(
            id: "mail.reading",
            title: "Inbox",
            shortcuts: items,
            priority: 20
        )
    }

    private func handleStar() async {
        guard var email = detail, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let newStarState = !email.is_starred
        await EmailActionSynchronizer.shared.enqueueStar(
            emailId: email.id,
            gmailId: email.gmail_id,
            accountEmail: email.account_email,
            shouldStar: newStarState
        )
        email = email.updating(isStarred: newStarState)
        await EmailCache.shared.saveEmailDetail(email)
        await DashboardDataManager.shared.updateEmailStarred(emailId: email.id, isStarred: newStarState)
        await MainActor.run { detail = email }
    }

    private func handleMarkUnread() async {
        guard var email = detail, !isProcessing else { return }
        if !email.is_read { return }

        isProcessing = true
        defer { isProcessing = false }

        await EmailActionSynchronizer.shared.enqueueMarkUnread(
            emailId: email.id,
            gmailId: email.gmail_id,
            accountEmail: email.account_email
        )
        email = email.updating(isRead: false)
        await EmailCache.shared.saveEmailDetail(email)
        await DashboardDataManager.shared.markEmailAsUnread(emailId: email.id, accountId: nil)
        await MainActor.run { detail = email }
    }

    private func handleMarkAsRead() async {
        guard var email = detail, !isProcessing else { return }
        if email.is_read { return }

        isProcessing = true
        defer { isProcessing = false }

        await EmailActionSynchronizer.shared.enqueueMarkRead(
            emailId: email.id,
            gmailId: email.gmail_id,
            accountEmail: email.account_email
        )
        email = email.updating(isRead: true)
        await EmailCache.shared.saveEmailDetail(email)
        await DashboardDataManager.shared.markEmailAsRead(emailId: email.id)
        await MainActor.run { detail = email }
    }

    private func handleUnsubscribe() async {
        guard let email = detail, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        guard let method = await UnsubscribeService.shared.getUnsubscribeInfo(
            for: email,
            accountEmail: email.account_email
        ) else { return }

        let result = await UnsubscribeService.shared.executeUnsubscribe(
            method: method,
            userEmail: email.account_email
        )

        if result.requiresManualAction, let url = result.manualActionURL {
            await MainActor.run {
                unsubscribeManualURL = url
                showUnsubscribeWebView = true
            }
        } else if let url = result.manualActionURL {
            await MainActor.run {
                unsubscribeManualURL = url
                showUnsubscribeWebView = true
            }
        }
    }

    @ViewBuilder
    private func emailBody(_ detail: EmailDetail, availableHeight: CGFloat) -> some View {
        let minBodyHeight = max(400, availableHeight - 140)
        if let html = detail.body_html, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmailHTMLWebView(htmlContent: html, isDarkMode: false)
                .frame(maxWidth: .infinity, minHeight: minBodyHeight, maxHeight: .infinity)
        } else if !detail.body_text.isEmpty {
            if looksLikeHTML(detail.body_text) {
                EmailHTMLWebView(htmlContent: detail.body_text, isDarkMode: false)
                    .frame(maxWidth: .infinity, minHeight: minBodyHeight, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(detail.body_text)
                        .font(.body)
                        .foregroundStyle(MacAppTheme.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                Text(detail.snippet)
                    .font(.body)
                    .italic()
                    .foregroundStyle(MacAppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Loading pipeline (mirrors iOS EmailDetailView)

    private func loadEmail() async {
        isLoading = true
        defer { isLoading = false }

        // 1. Persistent cache by numeric id
        if let cached = await EmailCache.shared.loadEmailDetail(emailId: emailId) {
            detail = cached
            return
        }

        // 2. Look up gmail_id + account_email from the snapshot
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            let allItems = snapshot.allEmails + snapshot.starredEmails
            if let found = allItems.first(where: { $0.id == emailId }) {
                await fetchFromGmail(gmailId: found.gmail_id, accountEmail: found.account_email)
                return
            }
        }

        errorMessage = "Email not found in cache or snapshot"
    }

    private func fetchFromGmail(gmailId: String, accountEmail: String) async {
        // Check cache by gmail_id first (different code path than numeric id lookup)
        if let cached = await EmailCache.shared.loadEmailDetail(gmailId: gmailId) {
            detail = cached
            return
        }

        let service = GmailAPIService.shared
        guard let account = service.getAccount(byEmail: accountEmail) else {
            errorMessage = "Account '\(accountEmail)' not found"
            return
        }

        do {
            let fetched = try await service.getEmailDetail(for: account, gmailId: gmailId)
            await EmailCache.shared.saveEmailDetail(fetched)
            detail = fetched
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func looksLikeHTML(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.hasPrefix("<html") || t.hasPrefix("<!doctype") || t.contains("<body") || t.contains("<div") || t.contains("<p>") || t.contains("<table")
    }

    private func formattedDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: iso) {
            return d.formatted(date: .abbreviated, time: .shortened)
        }
        let f2 = DateFormatter()
        f2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let d = f2.date(from: iso) {
            return d.formatted(date: .abbreviated, time: .shortened)
        }
        return iso
    }
}
