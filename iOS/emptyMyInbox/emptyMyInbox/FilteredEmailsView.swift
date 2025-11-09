//
//  FilteredEmailsView.swift
//  emptyMyInbox
//
//  View for displaying emails filtered by sender or category
//

import SwiftUI

enum EmailFilter: Hashable {
    case sender(email: String, name: String)
    case category(label: Label)
    
    static func == (lhs: EmailFilter, rhs: EmailFilter) -> Bool {
        switch (lhs, rhs) {
        case (.sender(let email1, _), .sender(let email2, _)):
            return email1 == email2
        case (.category(let label1), .category(let label2)):
            return label1.id == label2.id
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
    
    var categoryLabel: Label? {
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
        }
    }
    
    var emptyStateIcon: String {
        switch filter {
        case .sender:
            return "person.circle"
        case .category:
            return "tag"
        }
    }
    
    var emptyStateMessage: String {
        switch filter {
        case .sender(_, let name):
            return "No emails from \(name.formattedAsName)"
        case .category(let label):
            return "No emails in \(label.name)"
        }
    }
    
    var emptyStateSubmessage: String {
        switch filter {
        case .sender:
            return "Emails from this sender will appear here"
        case .category:
            return "Emails with this label will appear here"
        }
    }
    
    var unreadCount: Int {
        emails.filter { !$0.is_read }.count
    }
    
    var body: some View {
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
        
        do {
            let fetchedEmails: [EmailListItem]
            
            switch filter {
            case .sender(let email, _):
                fetchedEmails = try await APIService.shared.getEmailsBySender(senderEmail: email)
            case .category(let label):
                fetchedEmails = try await APIService.shared.getEmailsByLabel(labelId: label.id)
            }
            
            await MainActor.run {
                self.emails = fetchedEmails
                self.lastRefreshTime = Date()
                if let mostRecent = fetchedEmails.first {
                    self.mostRecentEmailTime = parseDate(mostRecent.received_at)
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func refreshEmails() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        do {
            // Sync all accounts first
            let syncResponse = try await APIService.shared.syncAllAccounts()
            
            // Then reload emails based on filter
            let fetchedEmails: [EmailListItem]
            
            switch filter {
            case .sender(let email, _):
                fetchedEmails = try await APIService.shared.getEmailsBySender(senderEmail: email)
            case .category(let label):
                fetchedEmails = try await APIService.shared.getEmailsByLabel(labelId: label.id)
            }
            
            await MainActor.run {
                self.emails = fetchedEmails
                self.lastRefreshTime = Date()
                
                if let mostRecentTimeStr = syncResponse.most_recent_email_at {
                    self.mostRecentEmailTime = parseDate(mostRecentTimeStr)
                } else if let mostRecent = fetchedEmails.first {
                    self.mostRecentEmailTime = parseDate(mostRecent.received_at)
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
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
    let label: Label
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
        
        do {
            print("Loading filters for label: \(label.id) (\(label.name))")
            async let filtersTask = APIService.shared.getFiltersForLabel(labelId: label.id)
            async let accountsTask = APIService.shared.getAccounts()
            
            let (fetchedFilters, fetchedAccounts) = try await (filtersTask, accountsTask)
            
            await MainActor.run {
                self.filters = fetchedFilters
                self.accounts = fetchedAccounts
                if fetchedFilters.isEmpty {
                    print("No filters found for label \(label.id)")
                }
            }
        } catch {
            print("Error loading filters: \(error)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                print("Error message: \(error.localizedDescription)")
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
            
            if let query = filter.criteria.query {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                    Text("Query: \(query)")
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
                            
                            if let query = filter.criteria.query {
                                FilterDetailRow(
                                    icon: "magnifyingglass",
                                    title: "Search Query",
                                    value: query,
                                    description: "Matches Gmail search"
                                )
                            }
                            
                            if let negatedQuery = filter.criteria.negatedQuery {
                                FilterDetailRow(
                                    icon: "magnifyingglass.circle",
                                    title: "Does Not Match",
                                    value: negatedQuery,
                                    description: "Excludes emails matching"
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
                               filter.criteria.query == nil &&
                               filter.criteria.negatedQuery == nil &&
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

