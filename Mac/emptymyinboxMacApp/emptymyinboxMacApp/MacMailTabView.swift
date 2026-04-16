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
    case saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .catchUp: return "Catch Up"
        case .stories: return "Stories"
        case .brief: return "Brief"
        case .saved: return "Saved"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .catchUp: return "tray.full"
        case .stories: return "rectangle.stack.fill"
        case .brief: return "sparkles"
        case .saved: return "star.fill"
        }
    }
}

private enum MailMailboxScope: Hashable {
    case all
    case allUnread
    case account(String)
}

private enum MailSidebarSelection: Hashable {
    case tool(MailTool)
    case mailbox(MailMailboxScope)
}

// MARK: - Mail tab

struct MacMailTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Binding var snapshot: DashboardDataSnapshot?
    @Binding var isRefreshing: Bool
    @Binding var refreshMessage: String?
    @ObservedObject var calendarModel: GoogleCalendarViewModel
    let dashboardActionItems: [VaultActionItemRecord]
    var onRefreshMailbox: () -> Void
    var onOpenSettings: () -> Void
    var onAddAccount: () -> Void

    @State private var selection: MailSidebarSelection = .tool(.dashboard)
    @State private var navigationPath = NavigationPath()
    @State private var selectedEmailId: Int?
    @State private var briefingPayload: DailyBriefingPayload?
    /// `nil` until the first Brief-tab load checks the keychain (matches iOS: Brief is AI-only).
    @State private var briefLLMKeyState: Bool?
    @State private var showLLMSettings = false
    @State private var catchUpContextualShortcuts: [MacSidebarContextualShortcut] = []

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
        .onChange(of: selection) { _, new in
            navigationPath = NavigationPath()
            selectedEmailId = nil
            if case .tool(.catchUp) = new { } else {
                catchUpContextualShortcuts = []
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

    private var unreadCount: Int {
        snapshot?.allEmails.filter { !$0.is_read }.count ?? 0
    }

    private var mailSidebarContextualShortcuts: [MacSidebarContextualShortcut] {
        if case .tool(.catchUp) = selection {
            return catchUpContextualShortcuts
        }
        return []
    }

    private var sidebar: some View {
        MacSidebarShell(
            contextualShortcuts: mailSidebarContextualShortcuts,
            onRefresh: onRefreshMailbox,
            onOpenSettings: onOpenSettings
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
                refreshMessage: refreshMessage
            )
        case .catchUp:
            MacCatchUpFeedView(contextualShortcuts: $catchUpContextualShortcuts)
        case .stories:
            NewsletterInsightDeckView(
                emails: snapshot?.allEmails ?? [],
                onDiveDeeper: { id in navigationPath.append(id) },
                onOpenLLMSettings: { showLLMSettings = true }
            )
        case .brief:
            briefInlineDetail
        case .saved:
            MacStarredEmailListView(snapshot: snapshot, path: $navigationPath)
        }
    }

    private var briefInlineDetail: some View {
        Group {
            if briefLLMKeyState == nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if briefLLMKeyState == false {
                LLMUpsellView(
                    title: "Unlock AI Summary",
                    subtitle: "Add your OpenAI API key to enable the Daily Executive Summary.",
                    actionTitle: "Add API Key",
                    onAction: { showLLMSettings = true }
                )
            } else if let briefingPayload {
                DailyBriefingContent(payload: briefingPayload) { item in
                    navigationPath.append(item.emailId)
                }
            } else if snapshot == nil {
                ContentUnavailableView {
                    Label("Daily Briefing", systemImage: "sparkles")
                } description: {
                    Text("Refresh your mailbox to load briefing data.")
                }
            } else {
                ProgressView("Preparing briefing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Daily Briefing")
        .task(id: briefTaskId) {
            guard case .tool(.brief) = selection else { return }
            await loadBriefingForMacTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .llmAPIKeyChanged)) { _ in
            Task {
                guard case .tool(.brief) = selection else { return }
                await loadBriefingForMacTab()
            }
        }
    }

    /// Identity for reloading Brief when the mailbox snapshot changes while the tab is open.
    private var briefTaskId: String {
        switch selection {
        case .tool(.brief):
            return "brief-\(snapshot?.timestamp.timeIntervalSince1970 ?? 0)-\(snapshot?.allEmails.count ?? 0)"
        default:
            return "brief-off"
        }
    }

    private func loadBriefingForMacTab() async {
        let hasKey = await LLMSettingsStore.shared.hasAPIKey()
        guard hasKey else {
            await MainActor.run {
                briefLLMKeyState = false
                briefingPayload = nil
            }
            return
        }
        await MainActor.run { briefLLMKeyState = true }
        guard let snap = snapshot else {
            await MainActor.run { briefingPayload = nil }
            return
        }
        let payload = await DailyBriefingEngine.shared.buildPayload(from: snap.allEmails, sinceDate: nil)
        await MainActor.run { briefingPayload = payload }
    }
}

// MARK: - Mailbox read filter

private enum MailboxReadFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case read = "Read"
}

// MARK: - Mailbox list (middle column)

private struct MacMailboxListColumn: View {
    let scope: MailMailboxScope
    let snapshot: DashboardDataSnapshot?
    @Binding var selectedEmailId: Int?

    @State private var readFilter: MailboxReadFilter = .all

    // Emails matching the scope (account / all / allUnread)
    private var scopedEmails: [EmailListItem] {
        guard let snapshot else { return [] }
        switch scope {
        case .all:
            return snapshot.allEmails
        case .allUnread:
            return snapshot.allEmails.filter { !$0.is_read }
        case .account(let email):
            return snapshot.allEmails.filter {
                $0.account_email.caseInsensitiveCompare(email) == .orderedSame
            }
        }
    }

    // Apply the read/unread chip filter on top of the scope
    private var rows: [EmailListItem] {
        switch readFilter {
        case .all:    return scopedEmails
        case .unread: return scopedEmails.filter { !$0.is_read }
        case .read:   return scopedEmails.filter { $0.is_read }
        }
    }

    private var title: String {
        switch scope {
        case .all:              return "All Emails"
        case .allUnread:        return "All Unread"
        case .account(let e):   return e
        }
    }

    // Hide chips for scopes that are already hard-filtered to one state
    private var showReadFilterChips: Bool {
        scope != .allUnread
    }

    var body: some View {
        VStack(spacing: 0) {
            if showReadFilterChips {
                readFilterBar
                Divider().opacity(0.3)
            }

            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No messages", systemImage: "envelope")
                } description: {
                    Text(emptyDescription)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedEmailId) {
                    ForEach(rows, id: \.id) { email in
                        MacMailboxRow(email: email)
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

    private var emptyDescription: String {
        switch readFilter {
        case .all:    return "Nothing in this mailbox yet."
        case .unread: return "No unread messages here."
        case .read:   return "No read messages here."
        }
    }

    private var readFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MailboxReadFilter.allCases, id: \.self) { f in
                    MailboxFilterChip(
                        title: f.rawValue,
                        isSelected: readFilter == f,
                        action: { readFilter = f }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(MacAppTheme.primaryBackground)
    }
}

// MARK: - Filter chip

private struct MailboxFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .black : MacAppTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected
                              ? MacAppTheme.accent
                              : (isHovered
                                 ? MacAppTheme.secondaryText.opacity(0.15)
                                 : MacAppTheme.secondaryBackground))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

private struct MacMailboxRow: View {
    let email: EmailListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(email.sender_name?.isEmpty == false ? (email.sender_name ?? email.sender) : email.sender)
                    .font(.headline)
                    .foregroundStyle(MacAppTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(shortDate(from: email.received_at))
                    .font(.caption)
                    .foregroundStyle(MacAppTheme.secondaryText)
            }
            Text(email.subject.isEmpty ? "(No subject)" : email.subject)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MacAppTheme.primaryText)
                .lineLimit(2)
            if !email.snippet.isEmpty {
                Text(email.snippet)
                    .font(.caption)
                    .foregroundStyle(MacAppTheme.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func shortDate(from iso: String) -> String {
        let parsed = ISO8601DateFormatter().date(from: iso) ?? {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            return f.date(from: iso)
        }()
        guard let parsed else { return "" }
        return parsed.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Saved (starred) list in detail

private struct MacStarredEmailListView: View {
    let snapshot: DashboardDataSnapshot?
    @Binding var path: NavigationPath

    private var rows: [EmailListItem] {
        snapshot?.allEmails.filter(\.is_starred) ?? []
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No saved messages", systemImage: "star")
                } description: {
                    Text("Star messages in Gmail to see them here.")
                }
            } else {
                List {
                    ForEach(rows, id: \.id) { email in
                        Button {
                            path.append(email.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(email.subject.isEmpty ? "(No subject)" : email.subject)
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
        .navigationTitle("Saved")
    }
}

// MARK: - Email detail (cache → Gmail API fallback, matches iOS EmailDetailView)

private struct MacCachedEmailDetailView: View {
    let emailId: Int
    @State private var detail: EmailDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
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
        .navigationTitle("Email")
        .task { await loadEmail() }
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

                // Body
                emailBody(detail, availableHeight: geo.size.height)
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
