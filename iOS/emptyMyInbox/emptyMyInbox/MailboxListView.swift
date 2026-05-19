//
//  MailboxListView.swift
//  emptyMyInbox
//
//  Unified mailbox list for Saved, All Emails, All Unread, and per-account inboxes.
//

import SwiftUI
import EmptyMyInboxShared

enum MailboxRefreshStrategy {
  case dashboardSync
  case starredSync
}

struct MailboxListView: View {
  let scope: MailboxScope
  var initialReadFilter: MailboxReadFilter = .all
  var refreshStrategy: MailboxRefreshStrategy = .dashboardSync
  var showsAccountOnRows: Bool = false
  var allowsBulkSelection: Bool = false
  var syncStarredOnAppear: Bool = false

  @State private var emails: [EmailListItem] = []
  @State private var accounts: [EmailAccount] = []
  @State private var isLoading = false
  @State private var lastRefreshTime: Date?
  @State private var mostRecentEmailTime: Date?
  @State private var readFilter: MailboxReadFilter
  @State private var selectedEmailIds: Set<Int> = []
  @State private var editMode: EditMode = .inactive
  @State private var isProcessing = false

  private var displayConfig: MailboxDisplayConfig {
    MailboxDisplayConfig.forScope(scope, readFilter: readFilter)
  }

  private var unreadCount: Int {
    emails.filter { !$0.is_read }.count
  }

  init(
    scope: MailboxScope,
    initialReadFilter: MailboxReadFilter = .all,
    refreshStrategy: MailboxRefreshStrategy = .dashboardSync,
    showsAccountOnRows: Bool = false,
    allowsBulkSelection: Bool = false,
    syncStarredOnAppear: Bool = false
  ) {
    self.scope = scope
    self.initialReadFilter = initialReadFilter
    self.refreshStrategy = refreshStrategy
    self.showsAccountOnRows = showsAccountOnRows
    self.allowsBulkSelection = allowsBulkSelection
    self.syncStarredOnAppear = syncStarredOnAppear
    _readFilter = State(initialValue: initialReadFilter)
  }

  var body: some View {
    ZStack {
      AppTheme.primaryBackground
        .ignoresSafeArea()

      mainContent
    }
    .navigationTitle(displayConfig.navigationTitle)
    .navigationBarTitleDisplayMode(.large)
    .customBackButton()
    .primaryBackground()
    .toolbar { bulkSelectionToolbar }
    .safeAreaInset(edge: .bottom) {
      if allowsBulkSelection, editMode == .active, !selectedEmailIds.isEmpty {
        bulkSelectionActionBar
      }
    }
    .environment(\.editMode, $editMode)
    .task {
      await loadCachedEmails()
      if syncStarredOnAppear, refreshStrategy == .starredSync {
        await refreshStarredFromGmail()
      }
    }
    .onChange(of: readFilter) { _, _ in
      Task { await loadCachedEmails() }
    }
  }

  @ToolbarContentBuilder
  private var bulkSelectionToolbar: some ToolbarContent {
    if allowsBulkSelection {
      ToolbarItem(placement: .navigationBarLeading) {
        if editMode == .active {
          Button {
            if selectedEmailIds.count == emails.count {
              selectedEmailIds.removeAll()
            } else {
              selectedEmailIds = Set(emails.map(\.id))
            }
          } label: {
            Text(selectedEmailIds.count == emails.count ? "Deselect All" : "Select All")
          }
          .textButton()
        }
      }

      ToolbarItem(placement: .navigationBarTrailing) {
        if editMode == .inactive {
          Button { editMode = .active } label: { Text("Select") }
            .textButton()
        } else {
          Button {
            selectedEmailIds.removeAll()
            editMode = .inactive
          } label: {
            Text("Cancel")
          }
          .textButton()
        }
      }
    }
  }

  @ViewBuilder
  private var mainContent: some View {
    if isLoading && emails.isEmpty {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if emails.isEmpty {
      MailboxEmptyStateView(config: displayConfig)
    } else {
      emailListScrollView
    }
  }

  private var emailListScrollView: some View {
    ScrollView {
      VStack(spacing: 0) {
        if displayConfig.showsReadFilterChips {
          MailboxReadFilterBar(selection: $readFilter)
        }

        if let lastRefresh = lastRefreshTime {
          MailboxRefreshStatusView(
            lastRefreshTime: lastRefresh,
            mostRecentEmailTime: mostRecentEmailTime
          )
          .padding(.horizontal, AppTheme.spacingMedium)
          .padding(.vertical, AppTheme.spacingSmall)
        }

        if displayConfig.showsUnreadCountHeader {
          MailboxUnreadCountHeader(count: unreadCount)
        }

        LazyVStack(spacing: 0) {
          ForEach(emails, id: \.id) { email in
            emailRow(for: email)
          }
        }
        .padding(.vertical, AppTheme.spacingSmall)
      }
    }
    .refreshable {
      await performRefresh()
    }
  }

  @ViewBuilder
  private func emailRow(for email: EmailListItem) -> some View {
    HStack(spacing: AppTheme.spacingMedium) {
      if allowsBulkSelection, editMode == .active {
        Button {
          toggleSelection(for: email.id)
        } label: {
          Image(systemName: selectedEmailIds.contains(email.id) ? "checkmark.circle.fill" : "circle")
            .foregroundColor(
              selectedEmailIds.contains(email.id)
                ? AppTheme.accent
                : AppTheme.secondaryText.opacity(0.5)
            )
            .font(.system(size: 22))
            .frame(width: 30)
        }
        .buttonStyle(.plain)
      }

      let row = MailboxEmailRow(
        email: email,
        showsAccountEmail: showsAccountOnRows || isMultiAccountScope
      )

      if allowsBulkSelection, editMode == .active {
        row.opacity(selectedEmailIds.contains(email.id) ? 1 : 0.6)
      } else {
        NavigationLink(destination: EmailDetailView(emailId: email.id)) {
          row
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, AppTheme.spacingMedium)
    .padding(.vertical, 4)
  }

  private var isMultiAccountScope: Bool {
    switch scope {
    case .all, .allUnread, .saved:
      return true
    case .account, .accountSaved:
      return false
    }
  }

  private var bulkSelectionActionBar: some View {
    VStack(spacing: 0) {
      Divider()
        .background(AppTheme.secondaryText.opacity(0.3))

      VStack(spacing: AppTheme.spacingSmall) {
        HStack {
          Text("\(selectedEmailIds.count) selected")
            .font(AppTheme.subheadline)
            .foregroundColor(AppTheme.secondaryText)
          Spacer()
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.top, AppTheme.spacingSmall)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            bulkActionButton(title: "Mark Read", icon: "envelope.open") {
              await markSelectedAsRead()
            }
            bulkActionButton(title: "Mark Unread", icon: "envelope.badge") {
              await markSelectedAsUnread()
            }
            bulkActionButton(title: "Remove from Device", icon: "iphone.slash", isDestructive: true) {
              await deleteSelectedLocally()
            }
          }
          .padding(.horizontal, AppTheme.spacingMedium)
        }
        .padding(.bottom, AppTheme.spacingSmall)
      }
      .background(AppTheme.primaryBackground)
    }
  }

  private func bulkActionButton(
    title: String,
    icon: String,
    isDestructive: Bool = false,
    action: @escaping () async -> Void
  ) -> some View {
    Button {
      Task { await action() }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 14, weight: .medium))
        Text(title)
          .font(.system(size: 14, weight: .medium))
      }
      .foregroundColor(isDestructive ? .red : AppTheme.primaryText)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(AppTheme.secondaryBackground)
      .cornerRadius(20)
    }
    .disabled(isProcessing)
  }

  // MARK: - Data

  private func loadCachedEmails() async {
    isLoading = true
    defer { isLoading = false }

    guard let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() else { return }

    await MainActor.run {
      applySnapshot(snapshot)
    }
  }

  private func performRefresh() async {
    switch refreshStrategy {
    case .dashboardSync:
      if let snapshot = await DashboardDataManager.shared.refreshData(shouldSync: true) {
        await MainActor.run { applySnapshot(snapshot) }
      }
    case .starredSync:
      await refreshStarredFromGmail()
    }
  }

  private func applySnapshot(_ snapshot: DashboardDataSnapshot) {
    accounts = snapshot.accounts
    emails = MailboxQuery.emails(in: snapshot, scope: scope, readFilter: readFilter)
    lastRefreshTime = snapshot.timestamp
    mostRecentEmailTime = emails.first.flatMap { EmailListItemDisplay.parseReceivedAt($0.received_at) }
  }

  private func refreshStarredFromGmail() async {
    let gmailService = GmailAPIService.shared
    let gmailAccounts = gmailService.getAllAccounts()
    var allStarred: [EmailListItem] = []

    for account in gmailAccounts {
      do {
        let starred = try await gmailService.syncStarredEmails(for: account, maxResults: 500)
        allStarred.append(contentsOf: starred)
      } catch {
        logError("Error syncing starred emails for \(account.email): \(error)", category: "Email")
      }
    }

    allStarred.sort { lhs, rhs in
      let left = EmailListItemDisplay.parseReceivedAt(lhs.received_at) ?? .distantPast
      let right = EmailListItemDisplay.parseReceivedAt(rhs.received_at) ?? .distantPast
      return left > right
    }

    if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
      let updated = DashboardDataSnapshot(
        timestamp: Date(),
        accounts: snapshot.accounts,
        emails: snapshot.emails,
        allEmails: snapshot.allEmails,
        starredEmails: allStarred,
        labels: snapshot.labels
      )
      await DashboardCache.shared.saveSnapshot(updated)
      await MainActor.run {
        NotificationCenter.default.post(name: .dashboardNeedsUpdate, object: nil)
        applySnapshot(updated)
        lastRefreshTime = Date()
      }
    }
  }

  // MARK: - Bulk actions

  private func toggleSelection(for emailId: Int) {
    if selectedEmailIds.contains(emailId) {
      selectedEmailIds.remove(emailId)
    } else {
      selectedEmailIds.insert(emailId)
    }
  }

  private func getAccountId(for accountEmail: String) -> Int? {
    accounts.first { $0.email.caseInsensitiveCompare(accountEmail) == .orderedSame }?.id
  }

  private func markSelectedAsRead() async {
    guard !selectedEmailIds.isEmpty, !isProcessing else { return }
    isProcessing = true
    defer {
      Task { @MainActor in
        isProcessing = false
        selectedEmailIds.removeAll()
        editMode = .inactive
      }
    }

    for emailId in selectedEmailIds {
      guard let email = emails.first(where: { $0.id == emailId }) else { continue }
      await EmailActionSynchronizer.shared.enqueueMarkRead(
        emailId: emailId,
        gmailId: email.gmail_id,
        accountEmail: email.account_email
      )
      await DashboardDataManager.shared.markEmailAsRead(emailId: emailId)
    }
    await loadCachedEmails()
  }

  private func markSelectedAsUnread() async {
    guard !selectedEmailIds.isEmpty, !isProcessing else { return }
    isProcessing = true
    defer {
      Task { @MainActor in
        isProcessing = false
        selectedEmailIds.removeAll()
        editMode = .inactive
      }
    }

    for emailId in selectedEmailIds {
      guard let email = emails.first(where: { $0.id == emailId }) else { continue }
      await EmailActionSynchronizer.shared.enqueueMarkUnread(
        emailId: emailId,
        gmailId: email.gmail_id,
        accountEmail: email.account_email
      )
      let accountId = getAccountId(for: email.account_email)
      await DashboardDataManager.shared.markEmailAsUnread(emailId: emailId, accountId: accountId)
    }
    await loadCachedEmails()
  }

  private func deleteSelectedLocally() async {
    guard !selectedEmailIds.isEmpty, !isProcessing else { return }
    isProcessing = true
    defer {
      Task { @MainActor in
        isProcessing = false
        selectedEmailIds.removeAll()
        editMode = .inactive
      }
    }

    let emailIds = Array(selectedEmailIds)
    guard let snapshot = await DashboardCache.shared.loadSnapshot() else { return }

    let updated = DashboardDataSnapshot(
      timestamp: snapshot.timestamp,
      accounts: snapshot.accounts,
      emails: snapshot.emails.filter { !emailIds.contains($0.id) },
      allEmails: snapshot.allEmails.filter { !emailIds.contains($0.id) },
      starredEmails: snapshot.starredEmails.filter { !emailIds.contains($0.id) },
      labels: snapshot.labels
    )
    await DashboardCache.shared.saveSnapshot(updated)

    var defaultMetadata = await EmailCache.shared.loadEmailMetadata(accountId: nil)
    defaultMetadata = defaultMetadata.filter { !emailIds.contains($0.id) }
    await EmailCache.shared.saveEmailMetadata(defaultMetadata, accountId: nil)

    for account in accounts {
      var accountMetadata = await EmailCache.shared.loadEmailMetadata(accountId: account.id)
      accountMetadata = accountMetadata.filter { !emailIds.contains($0.id) }
      await EmailCache.shared.saveEmailMetadata(accountMetadata, accountId: account.id)
    }

    await EmailCache.shared.deleteEmailDetails(emailIds: emailIds)
    await loadCachedEmails()
  }
}
