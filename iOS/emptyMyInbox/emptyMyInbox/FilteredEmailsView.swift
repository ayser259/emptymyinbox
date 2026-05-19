//
//  FilteredEmailsView.swift
//  emptyMyInbox
//
//  View for displaying emails filtered by sender or category
//

import SwiftUI
import EmptyMyInboxShared

enum EmailFilter: Hashable {
    case sender(email: String, name: String)
    case category(label: GmailLabel)
    // Account-specific filters
    case accountAll(accountEmail: String)
    case accountUnread(accountEmail: String)
    case accountStarred(accountEmail: String)
    case accountSenders(accountEmail: String)
    
    static func == (lhs: EmailFilter, rhs: EmailFilter) -> Bool {
        switch (lhs, rhs) {
        case (.sender(let email1, _), .sender(let email2, _)):
            return email1 == email2
        case (.category(let label1), .category(let label2)):
            return label1.id == label2.id
        case (.accountAll(let email1), .accountAll(let email2)):
            return email1 == email2
        case (.accountUnread(let email1), .accountUnread(let email2)):
            return email1 == email2
        case (.accountStarred(let email1), .accountStarred(let email2)):
            return email1 == email2
        case (.accountSenders(let email1), .accountSenders(let email2)):
            return email1 == email2
        default:
            return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .sender(let email, _):
            hasher.combine("sender")
            hasher.combine(email)
        case .category(let label):
            hasher.combine("category")
            hasher.combine(label.id)
        case .accountAll(let email):
            hasher.combine("accountAll")
            hasher.combine(email)
        case .accountUnread(let email):
            hasher.combine("accountUnread")
            hasher.combine(email)
        case .accountStarred(let email):
            hasher.combine("accountStarred")
            hasher.combine(email)
        case .accountSenders(let email):
            hasher.combine("accountSenders")
            hasher.combine(email)
        }
    }
}

struct FilteredEmailsView: View {
    let filter: EmailFilter
    @State private var emails: [EmailListItem] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var lastRefreshTime: Date?
    @State private var mostRecentEmailTime: Date?
    @State private var showFilterSheet = false
    
    var isCategoryFilter: Bool {
        if case .category = filter {
            return true
        }
        return false
    }
    
    var categoryLabel: GmailLabel? {
        if case .category(let label) = filter {
            return label
        }
        return nil
    }
    
    var title: String {
        switch filter {
        case .sender(_, let name):
            return name.formattedAsName
        case .category(let label):
            return label.name
        case .accountAll:
            return "All Emails"
        case .accountUnread:
            return "Unread"
        case .accountStarred:
            return "Starred"
        case .accountSenders:
            return "Senders"
        }
    }
    
    var subtitle: String? {
        switch filter {
        case .accountAll(let email), .accountUnread(let email), .accountStarred(let email), .accountSenders(let email):
            return email
        default:
            return nil
        }
    }
    
    var emptyStateIcon: String {
        switch filter {
        case .sender:
            return "person.circle"
        case .category:
            return "tag"
        case .accountAll:
            return "envelope"
        case .accountUnread:
            return "envelope.badge"
        case .accountStarred:
            return "star"
        case .accountSenders:
            return "person.2"
        }
    }
    
    var emptyStateMessage: String {
        switch filter {
        case .sender(_, let name):
            return "No emails from \(name.formattedAsName)"
        case .category(let label):
            return "No emails in \(label.name)"
        case .accountAll:
            return "No emails"
        case .accountUnread:
            return "No unread emails"
        case .accountStarred:
            return "No starred emails"
        case .accountSenders:
            return "No senders"
        }
    }
    
    var emptyStateSubmessage: String {
        switch filter {
        case .sender:
            return "Emails from this sender will appear here"
        case .category:
            return "Emails with this label will appear here"
        case .accountAll:
            return "Emails will appear here when synced"
        case .accountUnread:
            return "All caught up!"
        case .accountStarred:
            return "Star emails to save them for later"
        case .accountSenders:
            return "Senders will appear here when emails are synced"
        }
    }
    
    var unreadCount: Int {
        emails.filter { !$0.is_read }.count
    }
    
    @ViewBuilder
    var body: some View {
        if let mailbox = mailboxListConfiguration {
            MailboxListView(
                scope: mailbox.scope,
                initialReadFilter: mailbox.readFilter,
                refreshStrategy: mailbox.refreshStrategy,
                syncStarredOnAppear: mailbox.syncStarredOnAppear
            )
        } else {
            legacyFilteredListBody
        }
    }

    private var mailboxListConfiguration: (
        scope: MailboxScope,
        readFilter: MailboxReadFilter,
        refreshStrategy: MailboxRefreshStrategy,
        syncStarredOnAppear: Bool
    )? {
        switch filter {
        case .accountAll(let accountEmail):
            return (.account(email: accountEmail), .all, .dashboardSync, false)
        case .accountUnread(let accountEmail):
            return (.account(email: accountEmail), .unread, .dashboardSync, false)
        case .accountStarred(let accountEmail):
            return (.accountSaved(email: accountEmail), .all, .starredSync, true)
        default:
            return nil
        }
    }

    private var legacyFilteredListBody: some View {
        ZStack {
            AppTheme.primaryBackground
                .ignoresSafeArea()
                
                if isLoading && emails.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if emails.isEmpty {
                    VStack {
                        Image(systemName: emptyStateIcon)
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.secondaryText)
                            .padding()
                        
                        Text(emptyStateMessage)
                            .font(AppTheme.title3)
                            .primaryText()
                        
                        Text(emptyStateSubmessage)
                            .font(AppTheme.body)
                            .secondaryText()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Refresh status header
                            if let lastRefresh = lastRefreshTime {
                                RefreshStatusView(
                                    lastRefreshTime: lastRefresh,
                                    mostRecentEmailTime: mostRecentEmailTime
                                )
                                .padding(.horizontal, AppTheme.spacingMedium)
                                .padding(.vertical, AppTheme.spacingSmall)
                            }
                            
                            // Unread count header
                            if unreadCount > 0 {
                                HStack {
                                    Text("\(unreadCount) unread")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppTheme.accent)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, AppTheme.spacingMedium)
                                .padding(.vertical, AppTheme.spacingSmall)
                            }
                            
                            LazyVStack(spacing: 0) {
                                ForEach(emails, id: \.id) { email in
                                    NavigationLink(value: email.id) {
                                        GmailStyleEmailRow(email: email)
                                            .padding(.horizontal, AppTheme.spacingMedium)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.vertical, AppTheme.spacingSmall)
                        }
                    }
                    .refreshable {
                        await refreshEmails()
                    }
                }
            }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .customBackButton()
        .primaryBackground()
        .toolbar {
            if isCategoryFilter {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(AppTheme.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            if let label = categoryLabel {
                FilterRulesBottomSheet(label: label)
                    .onDisappear {
                        // Reload filters when sheet is dismissed
                        Task {
                            await loadEmails()
                        }
                    }
            }
        }
        .navigationDestination(for: Int.self) { emailId in
            EmailDetailView(emailId: emailId)
        }
        .task {
            await loadEmails()
        }
    }

    private func loadEmails() async {
        isLoading = true
        defer { isLoading = false }
        
        // Try loading from cache first
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            let sourceEmails = getSourceEmails(from: snapshot)
            let filteredEmails = filterEmails(from: sourceEmails)
            await MainActor.run {
                self.emails = filteredEmails
                self.lastRefreshTime = snapshot.timestamp
                if let mostRecent = filteredEmails.first {
                    self.mostRecentEmailTime = parseDate(mostRecent.received_at)
                }
            }
        }
        
        // Then refresh from Gmail
        await refreshEmails()
    }
    
    private func refreshEmails() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        // Refresh dashboard data first
        _ = await DashboardDataManager.shared.refreshData(shouldSync: true)
        
        // Then load from updated cache
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            let sourceEmails = getSourceEmails(from: snapshot)
            let filteredEmails = filterEmails(from: sourceEmails)
            await MainActor.run {
                self.emails = filteredEmails
                self.lastRefreshTime = snapshot.timestamp
                if let mostRecent = filteredEmails.first {
                    self.mostRecentEmailTime = parseDate(mostRecent.received_at)
                }
            }
        }
    }
    
    /// Get the appropriate source emails based on filter type
    private func getSourceEmails(from snapshot: DashboardDataSnapshot) -> [EmailListItem] {
        switch filter {
        case .accountStarred(let accountEmail):
            // For starred filter, use starredEmails collection with case-insensitive comparison
            return snapshot.starredEmails.filter { $0.account_email.lowercased() == accountEmail.lowercased() }
        default:
            return snapshot.allEmails
        }
    }
    
    private func filterEmails(from emails: [EmailListItem]) -> [EmailListItem] {
        switch filter {
        case .sender(let senderEmail, _):
            return emails.filter { $0.sender.lowercased() == senderEmail.lowercased() }
        case .category(let label):
            if label.id == "__UNCATEGORIZED__" {
                // For uncategorized, filter emails with no user labels
                let systemLabels = Set(["INBOX", "SENT", "DRAFT", "SPAM", "TRASH", "UNREAD", "STARRED", "IMPORTANT"])
                return emails.filter { email in
                    let userLabels = email.labels.filter { !systemLabels.contains($0) }
                    return userLabels.isEmpty
                }
            } else {
                return emails.filter { $0.labels.contains(label.id) }
            }
        case .accountAll(let accountEmail):
            return emails.filter { $0.account_email.lowercased() == accountEmail.lowercased() }
        case .accountUnread(let accountEmail):
            return emails.filter { $0.account_email.lowercased() == accountEmail.lowercased() && !$0.is_read }
        case .accountStarred:
            // Starred filter should already have filtered emails from getSourceEmails
            return emails
        case .accountSenders:
            // Senders view will be handled differently
            return emails
        }
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString)
    }
}

struct FilterRulesBottomSheet: View {
    @Environment(\.dismiss) var dismiss
    let label: GmailLabel
    @State private var filters: [GmailFilter] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilter: GmailFilter?
    @State private var showFilterDetail = false
    @State private var accounts: [EmailAccount] = []
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()
                
                if isLoading && filters.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: AppTheme.spacingMedium) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.secondaryText)
                        
                        Text("Error Loading Filters")
                            .font(AppTheme.title3)
                            .primaryText()
                        
                        Text(errorMessage)
                            .font(AppTheme.body)
                            .secondaryText()
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.spacingLarge)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filters.isEmpty {
                    VStack(spacing: AppTheme.spacingMedium) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.secondaryText)
                        
                        Text("No Filters")
                            .font(AppTheme.title3)
                            .primaryText()
                        
                        Text("No filter rules are associated with this category.\n\nPull to refresh on the dashboard to sync filters from Gmail.")
                            .font(AppTheme.body)
                            .secondaryText()
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.spacingLarge)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.spacingSmall) {
                            ForEach(filters) { filter in
                                Button {
                                    selectedFilter = filter
                                    showFilterDetail = true
                                } label: {
                                    FilterRuleDisplayRow(filter: filter)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.horizontal, AppTheme.spacingMedium)
                            }
                        }
                        .padding(.vertical, AppTheme.spacingMedium)
                    }
                }
            }
            .navigationTitle("Filters for \(label.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .textButton()
                }
            }
            .primaryBackground()
            .sheet(isPresented: $showFilterDetail) {
                if let filter = selectedFilter, let accountId = accounts.first?.id {
                    FilterDetailView(filter: filter, accountId: accountId)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadFilters()
        }
    }
    
    private func loadFilters() async {
        isLoading = true
        defer { isLoading = false }
        
        let gmailService = GmailAPIService.shared
        let gmailAccounts = gmailService.getAllAccounts()
        
        // Convert GmailAccounts to EmailAccounts
        var emailAccounts: [EmailAccount] = []
        var allFilters: [GmailFilter] = []
        
        for gmailAccount in gmailAccounts {
            // Create EmailAccount
            let dateFormatter = ISO8601DateFormatter()
            let lastSyncString = gmailAccount.lastSync.map { dateFormatter.string(from: $0) }
            
            let emailAccount = EmailAccount(
                id: gmailAccount.numericId,
                email: gmailAccount.email,
                is_active: true,
                last_sync: lastSyncString,
                created_at: dateFormatter.string(from: Date()),
                email_count: 0
            )
            emailAccounts.append(emailAccount)
            
            // Get filters for this account
            do {
                let gmailFilters = try await gmailService.getAllFilters(for: gmailAccount)
                
                // Convert Gmail filters to GmailFilter structs
                for (index, filterData) in gmailFilters.enumerated() {
                    guard let gmailFilterId = filterData["id"] as? String,
                          let criteria = filterData["criteria"] as? [String: Any],
                          let action = filterData["action"] as? [String: Any] else {
                        continue
                    }
                    
                    // Check if this filter applies the label
                    if let addLabelIds = action["addLabelIds"] as? [String],
                       addLabelIds.contains(label.id) {
                        
                        // Parse criteria
                        let filterCriteria = FilterCriteria(
                            from: criteria["from"] as? String,
                            to: criteria["to"] as? String,
                            subject: criteria["subject"] as? String,
                            hasAttachment: criteria["hasAttachment"] as? Bool,
                            excludeChats: criteria["excludeChats"] as? Bool,
                            size: criteria["size"] as? Int,
                            sizeComparison: criteria["sizeComparison"] as? String
                        )
                        
                        // Parse actions
                        let filterActions = FilterActions(
                            addLabelIds: action["addLabelIds"] as? [String],
                            removeLabelIds: action["removeLabelIds"] as? [String],
                            forward: action["forward"] as? String,
                            markAsRead: action["markAsRead"] as? Bool,
                            archive: action["archive"] as? Bool,
                            delete: action["delete"] as? Bool,
                            alwaysMarkAsRead: action["alwaysMarkAsRead"] as? Bool,
                            neverMarkAsRead: action["neverMarkAsRead"] as? Bool,
                            neverSpam: action["neverSpam"] as? Bool,
                            star: action["star"] as? Bool
                        )
                        
                        let gmailFilter = GmailFilter(
                            id: index + 1, // Generate numeric ID
                            gmail_filter_id: gmailFilterId,
                            criteria: filterCriteria,
                            actions: filterActions,
                            created_at: Date().ISO8601Format(),
                            updated_at: Date().ISO8601Format()
                        )
                        allFilters.append(gmailFilter)
                    }
                }
            } catch {
                logError("Error loading filters for \(gmailAccount.email): \(error)", category: "Gmail")
            }
        }
        
        await MainActor.run {
            self.filters = allFilters
            self.accounts = emailAccounts
            if allFilters.isEmpty {
                logInfo("No filters found for label \(label.id)", category: "Gmail")
            }
        }
    }
}

struct FilterRuleDisplayRow: View {
    let filter: GmailFilter
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
            // Criteria
            if let from = filter.criteria.from {
                HStack {
                    Image(systemName: "envelope")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                    Text("From: \(from)")
                        .font(AppTheme.caption)
                        .secondaryText()
                }
            }
            
            if let subject = filter.criteria.subject {
                HStack {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                    Text("Subject: \(subject)")
                        .font(AppTheme.caption)
                        .secondaryText()
                }
            }
            
            if filter.criteria.hasAttachment == true {
                HStack {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                    Text("Has attachment")
                        .font(AppTheme.caption)
                        .secondaryText()
                }
            }
            
            // Actions
            if let labelIds = filter.actions.addLabelIds, !labelIds.isEmpty {
                HStack {
                    Image(systemName: "tag")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.accent)
                    Text("Apply labels: \(labelIds.joined(separator: ", "))")
                        .font(AppTheme.caption)
                        .foregroundColor(AppTheme.accent)
                }
            }
            
            HStack {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.5))
            }
        }
        .padding(AppTheme.spacingMedium)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
    }
}

struct FilterDetailView: View {
    @Environment(\.dismiss) var dismiss
    let filter: GmailFilter
    let accountId: Int
    @State private var showEditor = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacingLarge) {
                    // Filter ID
                    VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                        Text("Filter ID")
                            .font(AppTheme.subheadline)
                            .secondaryText()
                            .textCase(.uppercase)
                        
                        Text(filter.gmail_filter_id)
                            .font(AppTheme.body)
                            .primaryText()
                            .textSelection(.enabled)
                    }
                    .padding(AppTheme.spacingMedium)
                    .background(AppTheme.secondaryBackground)
                    .cornerRadius(AppTheme.cornerRadiusMedium)
                    
                    // Criteria Section
                    VStack(alignment: .leading, spacing: AppTheme.spacingMedium) {
                        Text("Criteria")
                            .font(AppTheme.title3)
                            .primaryText()
                        
                        VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                            if let from = filter.criteria.from {
                                FilterDetailRow(
                                    icon: "envelope",
                                    title: "From",
                                    value: from,
                                    description: "Has sender"
                                )
                            }
                            
                            if let to = filter.criteria.to {
                                FilterDetailRow(
                                    icon: "envelope.badge",
                                    title: "To",
                                    value: to,
                                    description: "Has recipient"
                                )
                            }
                            
                            if let subject = filter.criteria.subject {
                                FilterDetailRow(
                                    icon: "text.bubble",
                                    title: "Subject",
                                    value: subject,
                                    description: "Has the words"
                                )
                            }
                            
                            if filter.criteria.hasAttachment == true {
                                FilterDetailRow(
                                    icon: "paperclip",
                                    title: "Has Attachment",
                                    value: "Yes",
                                    description: "Email has attachment"
                                )
                            }
                            
                            if filter.criteria.excludeChats == true {
                                FilterDetailRow(
                                    icon: "message",
                                    title: "Exclude Chats",
                                    value: "Yes",
                                    description: "Exclude chat messages"
                                )
                            }
                            
                            if let size = filter.criteria.size, let comparison = filter.criteria.sizeComparison {
                                let sizeMB = Double(size) / 1024.0 / 1024.0
                                let comparisonText = comparison == "larger" ? "Larger than" : "Smaller than"
                                FilterDetailRow(
                                    icon: "doc",
                                    title: "Size",
                                    value: String(format: "%.2f MB", sizeMB),
                                    description: comparisonText
                                )
                            }
                            
                            if filter.criteria.from == nil &&
                               filter.criteria.to == nil &&
                               filter.criteria.subject == nil &&
                               filter.criteria.hasAttachment != true &&
                               filter.criteria.excludeChats != true &&
                               filter.criteria.size == nil {
                                Text("No criteria specified")
                                    .font(AppTheme.body)
                                    .secondaryText()
                                    .padding(.vertical, AppTheme.spacingSmall)
                            }
                        }
                    }
                    .padding(AppTheme.spacingMedium)
                    .background(AppTheme.secondaryBackground)
                    .cornerRadius(AppTheme.cornerRadiusMedium)
                    
                    // Actions Section
                    VStack(alignment: .leading, spacing: AppTheme.spacingMedium) {
                        Text("Actions")
                            .font(AppTheme.title3)
                            .primaryText()
                        
                        VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                            if let addLabelIds = filter.actions.addLabelIds, !addLabelIds.isEmpty {
                                let labelNames = addLabelIds.compactMap { labelId in
                                    // Try to find label name from common system labels or use ID
                                    switch labelId {
                                    case "INBOX": return "Inbox"
                                    case "SENT": return "Sent"
                                    case "DRAFT": return "Draft"
                                    case "SPAM": return "Spam"
                                    case "TRASH": return "Trash"
                                    case "STARRED": return "Starred"
                                    case "UNREAD": return "Unread"
                                    default: return labelId
                                    }
                                }
                                FilterDetailRow(
                                    icon: "tag.fill",
                                    title: "Add Labels",
                                    value: labelNames.joined(separator: ", "),
                                    description: "Apply these labels",
                                    isAction: true
                                )
                            }
                            
                            if let removeLabelIds = filter.actions.removeLabelIds, !removeLabelIds.isEmpty {
                                let labelNames = removeLabelIds.compactMap { labelId in
                                    switch labelId {
                                    case "INBOX": return "Inbox"
                                    case "SENT": return "Sent"
                                    case "DRAFT": return "Draft"
                                    case "SPAM": return "Spam"
                                    case "TRASH": return "Trash"
                                    case "STARRED": return "Starred"
                                    case "UNREAD": return "Unread"
                                    default: return labelId
                                    }
                                }
                                FilterDetailRow(
                                    icon: "tag.slash.fill",
                                    title: "Remove Labels",
                                    value: labelNames.joined(separator: ", "),
                                    description: "Remove these labels",
                                    isAction: true
                                )
                            }
                            
                            if let forward = filter.actions.forward {
                                FilterDetailRow(
                                    icon: "arrow.forward",
                                    title: "Forward To",
                                    value: forward,
                                    description: "Forward email to",
                                    isAction: true
                                )
                            }
                            
                            if filter.actions.markAsRead == true {
                                FilterDetailRow(
                                    icon: "envelope.open",
                                    title: "Mark as Read",
                                    value: "Yes",
                                    description: "Mark email as read",
                                    isAction: true
                                )
                            }
                            
                            if filter.actions.archive == true {
                                FilterDetailRow(
                                    icon: "archivebox",
                                    title: "Archive",
                                    value: "Yes",
                                    description: "Archive the email",
                                    isAction: true
                                )
                            }
                            
                            if filter.actions.delete == true {
                                FilterDetailRow(
                                    icon: "trash",
                                    title: "Delete",
                                    value: "Yes",
                                    description: "Delete the email",
                                    isAction: true
                                )
                            }
                            
                            if filter.actions.alwaysMarkAsRead == true {
                                FilterDetailRow(
                                    icon: "checkmark.circle.fill",
                                    title: "Always Mark as Read",
                                    value: "Yes",
                                    description: "Always mark as read",
                                    isAction: true
                                )
                            }
                            
                            if filter.actions.neverMarkAsRead == true {
                                FilterDetailRow(
                                    icon: "xmark.circle.fill",
                                    title: "Never Mark as Read",
                                    value: "Yes",
                                    description: "Never mark as read",
                                    isAction: true
                                )
                            }
                            
                            if filter.actions.neverSpam == true {
                                FilterDetailRow(
                                    icon: "exclamationmark.shield.fill",
                                    title: "Never Send to Spam",
                                    value: "Yes",
                                    description: "Never mark as spam",
                                    isAction: true
                                )
                            }
                            
                            if filter.actions.star == true {
                                FilterDetailRow(
                                    icon: "star.fill",
                                    title: "Star",
                                    value: "Yes",
                                    description: "Star the email",
                                    isAction: true
                                )
                            }
                            
                            if filter.actions.addLabelIds?.isEmpty != false &&
                               filter.actions.removeLabelIds?.isEmpty != false &&
                               filter.actions.forward == nil &&
                               filter.actions.markAsRead != true &&
                               filter.actions.archive != true &&
                               filter.actions.delete != true &&
                               filter.actions.alwaysMarkAsRead != true &&
                               filter.actions.neverMarkAsRead != true &&
                               filter.actions.neverSpam != true &&
                               filter.actions.star != true {
                                Text("No actions specified")
                                    .font(AppTheme.body)
                                    .secondaryText()
                                    .padding(.vertical, AppTheme.spacingSmall)
                            }
                        }
                    }
                    .padding(AppTheme.spacingMedium)
                    .background(AppTheme.secondaryBackground)
                    .cornerRadius(AppTheme.cornerRadiusMedium)
                    
                    // Metadata Section
                    VStack(alignment: .leading, spacing: AppTheme.spacingMedium) {
                        Text("Metadata")
                            .font(AppTheme.title3)
                            .primaryText()
                        
                        VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                            if let createdAt = parseDate(filter.created_at) {
                                FilterDetailRow(
                                    icon: "clock",
                                    title: "Created",
                                    value: formatDate(createdAt)
                                )
                            }
                            
                            if let updatedAt = parseDate(filter.updated_at) {
                                FilterDetailRow(
                                    icon: "clock.arrow.circlepath",
                                    title: "Last Updated",
                                    value: formatDate(updatedAt)
                                )
                            }
                        }
                    }
                    .padding(AppTheme.spacingMedium)
                    .background(AppTheme.secondaryBackground)
                    .cornerRadius(AppTheme.cornerRadiusMedium)
                }
                .padding(AppTheme.spacingMedium)
            }
            .navigationTitle("Filter Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .textButton()
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(AppTheme.accent)
                    }
                }
            }
            .primaryBackground()
            .sheet(isPresented: $showEditor) {
                FilterEditorView(filter: filter, accountId: accountId)
            }
        }
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct FilterDetailRow: View {
    let icon: String
    let title: String
    let value: String
    var description: String? = nil
    var isAction: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingMedium) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isAction ? AppTheme.accent : AppTheme.secondaryText.opacity(0.7))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(AppTheme.caption)
                        .secondaryText()
                    
                    if let description = description {
                        Text("• \(description)")
                            .font(AppTheme.caption)
                            .secondaryText()
                            .opacity(0.7)
                    }
                }
                
                Text(value)
                    .font(AppTheme.body)
                    .primaryText()
                    .textSelection(.enabled)
            }
            
            Spacer()
        }
        .padding(.vertical, AppTheme.spacingSmall)
    }
}

#Preview {
    FilteredEmailsView(filter: .sender(email: "test@example.com", name: "John Doe"))
}

