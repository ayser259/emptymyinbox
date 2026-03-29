//
//  FilterEditorView.swift
//  emptyMyInbox
//
//  Comprehensive Gmail filter editor
//

import SwiftUI
import EmptyMyInboxShared

struct FilterEditorView: View {
    @Environment(\.dismiss) var dismiss
    let filter: GmailFilter?
    let accountId: Int
    
    @State private var criteria: FilterCriteria
    @State private var actions: FilterActions
    @State private var labels: [GmailLabel] = []
    @State private var accounts: [EmailAccount] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    
    // Criteria state
    @State private var fromText = ""
    @State private var toText = ""
    @State private var subjectText = ""
    @State private var hasAttachment = false
    @State private var excludeChats = false
    @State private var sizeText = ""
    @State private var sizeComparison: String = "larger"
    
    // Actions state
    @State private var selectedAddLabels: Set<String> = []
    @State private var selectedRemoveLabels: Set<String> = []
    @State private var forwardText = ""
    @State private var markAsRead = false
    @State private var archive = false
    @State private var delete = false
    @State private var alwaysMarkAsRead = false
    @State private var neverMarkAsRead = false
    @State private var neverSpam = false
    @State private var star = false
    
    init(filter: GmailFilter? = nil, accountId: Int) {
        self.filter = filter
        self.accountId = accountId
        
        if let filter = filter {
            _criteria = State(initialValue: filter.criteria)
            _actions = State(initialValue: filter.actions)
        } else {
            _criteria = State(initialValue: FilterCriteria())
            _actions = State(initialValue: FilterActions())
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.spacingLarge) {
                        // Criteria Section
                        VStack(alignment: .leading, spacing: AppTheme.spacingMedium) {
                            Text("Criteria")
                                .font(AppTheme.title2)
                                .primaryText()
                                .padding(.horizontal, AppTheme.spacingMedium)
                            
                            VStack(spacing: AppTheme.spacingMedium) {
                                // From
                                FilterTextField(
                                    title: "From",
                                    placeholder: "email@example.com",
                                    text: $fromText,
                                    icon: "envelope"
                                )
                                
                                // To
                                FilterTextField(
                                    title: "To",
                                    placeholder: "email@example.com",
                                    text: $toText,
                                    icon: "envelope.badge"
                                )
                                
                                // Subject
                                FilterTextField(
                                    title: "Subject",
                                    placeholder: "Contains text...",
                                    text: $subjectText,
                                    icon: "text.bubble"
                                )
                                
                                // Has Attachment
                                FilterToggle(
                                    title: "Has Attachment",
                                    icon: "paperclip",
                                    isOn: $hasAttachment
                                )
                                
                                // Exclude Chats
                                FilterToggle(
                                    title: "Exclude Chats",
                                    icon: "message",
                                    isOn: $excludeChats
                                )
                                
                                // Size
                                VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                                    HStack {
                                        Image(systemName: "doc")
                                            .foregroundColor(AppTheme.secondaryText)
                                        Text("Size")
                                            .font(AppTheme.subheadline)
                                            .primaryText()
                                    }
                                    
                                    HStack(spacing: AppTheme.spacingSmall) {
                                        Picker("", selection: $sizeComparison) {
                                            Text("Larger than").tag("larger")
                                            Text("Smaller than").tag("smaller")
                                        }
                                        .pickerStyle(.menu)
                                        .frame(width: 140)
                                        
                                        TextField("Size in MB", text: $sizeText)
                                            .keyboardType(.decimalPad)
                                            .primaryText()
                                            .padding(AppTheme.spacingMedium)
                                            .background(AppTheme.secondaryBackground)
                                            .cornerRadius(AppTheme.cornerRadiusMedium)
                                    }
                                }
                                .padding(AppTheme.spacingMedium)
                                .background(AppTheme.secondaryBackground)
                                .cornerRadius(AppTheme.cornerRadiusMedium)
                            }
                            .padding(.horizontal, AppTheme.spacingMedium)
                        }
                        
                        // Actions Section
                        VStack(alignment: .leading, spacing: AppTheme.spacingMedium) {
                            Text("Actions")
                                .font(AppTheme.title2)
                                .primaryText()
                                .padding(.horizontal, AppTheme.spacingMedium)
                            
                            VStack(spacing: AppTheme.spacingMedium) {
                                // Add Labels
                                FilterLabelPicker(
                                    title: "Add Labels",
                                    icon: "tag.fill",
                                    selectedLabels: $selectedAddLabels,
                                    allLabels: labels
                                )
                                
                                // Remove Labels
                                FilterLabelPicker(
                                    title: "Remove Labels",
                                    icon: "tag.slash.fill",
                                    selectedLabels: $selectedRemoveLabels,
                                    allLabels: labels
                                )
                                
                                // Forward
                                FilterTextField(
                                    title: "Forward To",
                                    placeholder: "email@example.com",
                                    text: $forwardText,
                                    icon: "arrow.forward",
                                    keyboardType: .emailAddress
                                )
                                
                                // Mark as Read
                                FilterToggle(
                                    title: "Mark as Read",
                                    icon: "envelope.open",
                                    isOn: $markAsRead
                                )
                                
                                // Archive
                                FilterToggle(
                                    title: "Archive",
                                    icon: "archivebox",
                                    isOn: $archive
                                )
                                
                                // Delete
                                FilterToggle(
                                    title: "Delete",
                                    icon: "trash",
                                    isOn: $delete
                                )
                                
                                // Always Mark as Read
                                FilterToggle(
                                    title: "Always Mark as Read",
                                    icon: "checkmark.circle.fill",
                                    isOn: $alwaysMarkAsRead
                                )
                                
                                // Never Mark as Read
                                FilterToggle(
                                    title: "Never Mark as Read",
                                    icon: "xmark.circle.fill",
                                    isOn: $neverMarkAsRead
                                )
                                
                                // Never Spam
                                FilterToggle(
                                    title: "Never Send to Spam",
                                    icon: "exclamationmark.shield.fill",
                                    isOn: $neverSpam
                                )
                                
                                // Star
                                FilterToggle(
                                    title: "Star",
                                    icon: "star.fill",
                                    isOn: $star
                                )
                            }
                            .padding(.horizontal, AppTheme.spacingMedium)
                        }
                        
                        // Error message
                        if let error = errorMessage {
                            Text(error)
                                .font(AppTheme.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal, AppTheme.spacingMedium)
                        }
                        
                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.vertical, AppTheme.spacingMedium)
                }
            }
            .navigationTitle(filter == nil ? "New Filter" : "Edit Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .textButton()
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if filter != nil {
                        Menu {
                            Button("Save", action: saveFilter)
                            Button("Delete", role: .destructive) {
                                showDeleteConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(AppTheme.accent)
                        }
                    } else {
                        Button("Save") {
                            saveFilter()
                        }
                        .textButton()
                        .disabled(isSaving)
                    }
                }
            }
            .primaryBackground()
            .confirmationDialog(
                "Delete Filter",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteFilter()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this filter? This action cannot be undone.")
            }
            .task {
                await loadData()
            }
        }
    }
    
    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        let gmailService = GmailAPIService.shared
        let gmailAccounts = gmailService.getAllAccounts()
        
        // Find account by ID
        guard let gmailAccount = gmailAccounts.first(where: { $0.numericId == accountId }) else {
            await MainActor.run {
                self.errorMessage = "Account not found"
            }
            return
        }
        
        do {
            // Get labels
            let labelsDict = try await gmailService.getAllLabels(for: gmailAccount)
            let fetchedLabels = labelsDict.map { (id, name) in
                GmailLabel(id: id, name: name, unread_count: 0)
            }.sorted { $0.name < $1.name }
            
            // Convert GmailAccounts to EmailAccounts
            let dateFormatter = ISO8601DateFormatter()
            let fetchedAccounts = gmailAccounts.map { gmailAccount in
                let lastSyncString = gmailAccount.lastSync.map { dateFormatter.string(from: $0) }
                return EmailAccount(
                    id: gmailAccount.numericId,
                    email: gmailAccount.email,
                    is_active: true,
                    last_sync: lastSyncString,
                    created_at: dateFormatter.string(from: Date()),
                    email_count: 0
                )
            }
            
            await MainActor.run {
                self.labels = fetchedLabels
                self.accounts = fetchedAccounts
                
                // Initialize form fields from filter
                if let filter = filter {
                    fromText = filter.criteria.from ?? ""
                    toText = filter.criteria.to ?? ""
                    subjectText = filter.criteria.subject ?? ""
                    hasAttachment = filter.criteria.hasAttachment ?? false
                    excludeChats = filter.criteria.excludeChats ?? false
                    if let size = filter.criteria.size {
                        sizeText = String(size / 1024 / 1024) // Convert bytes to MB
                    }
                    sizeComparison = filter.criteria.sizeComparison ?? "larger"
                    
                    selectedAddLabels = Set(filter.actions.addLabelIds ?? [])
                    selectedRemoveLabels = Set(filter.actions.removeLabelIds ?? [])
                    forwardText = filter.actions.forward ?? ""
                    markAsRead = filter.actions.markAsRead ?? false
                    archive = filter.actions.archive ?? false
                    delete = filter.actions.delete ?? false
                    alwaysMarkAsRead = filter.actions.alwaysMarkAsRead ?? false
                    neverMarkAsRead = filter.actions.neverMarkAsRead ?? false
                    neverSpam = filter.actions.neverSpam ?? false
                    star = filter.actions.star ?? false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load data: \(error.localizedDescription)"
            }
        }
    }
    
    private func saveFilter() {
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                let gmailService = GmailAPIService.shared
                let gmailAccounts = gmailService.getAllAccounts()
                
                guard let gmailAccount = gmailAccounts.first(where: { $0.numericId == accountId }) else {
                    throw NSError(domain: "FilterEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Account not found"])
                }
                
                // Build Gmail filter data structure
                var filterData: [String: Any] = [:]
                
                // Criteria
                var criteriaDict: [String: Any] = [:]
                if !fromText.isEmpty { criteriaDict["from"] = fromText }
                if !toText.isEmpty { criteriaDict["to"] = toText }
                if !subjectText.isEmpty { criteriaDict["subject"] = subjectText }
                if hasAttachment { criteriaDict["hasAttachment"] = true }
                if excludeChats { criteriaDict["excludeChats"] = true }
                if let sizeInBytes = sizeText.isEmpty ? nil : Int((Double(sizeText) ?? 0) * 1024 * 1024) {
                    criteriaDict["size"] = sizeInBytes
                    criteriaDict["sizeComparison"] = sizeComparison
                }
                filterData["criteria"] = criteriaDict
                
                // Actions
                var actionDict: [String: Any] = [:]
                if !selectedAddLabels.isEmpty { actionDict["addLabelIds"] = Array(selectedAddLabels) }
                if !selectedRemoveLabels.isEmpty { actionDict["removeLabelIds"] = Array(selectedRemoveLabels) }
                if !forwardText.isEmpty { actionDict["forward"] = forwardText }
                if markAsRead { actionDict["markAsRead"] = true }
                if archive { actionDict["archive"] = true }
                if delete { actionDict["delete"] = true }
                if alwaysMarkAsRead { actionDict["alwaysMarkAsRead"] = true }
                if neverMarkAsRead { actionDict["neverMarkAsRead"] = true }
                if neverSpam { actionDict["neverSpam"] = true }
                if star { actionDict["star"] = true }
                filterData["action"] = actionDict
                
                if let filter = filter {
                    // Update existing filter - Gmail API doesn't support update, so we delete and recreate
                    try await gmailService.deleteFilter(for: gmailAccount, filterId: filter.gmail_filter_id)
                    _ = try await gmailService.createFilter(for: gmailAccount, filterData: filterData)
                } else {
                    // Create new filter
                    _ = try await gmailService.createFilter(for: gmailAccount, filterData: filterData)
                }
                
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save filter: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func deleteFilter() {
        guard let filter = filter else { return }
        
        Task {
            do {
                let gmailService = GmailAPIService.shared
                let gmailAccounts = gmailService.getAllAccounts()
                
                guard let gmailAccount = gmailAccounts.first(where: { $0.numericId == accountId }) else {
                    throw NSError(domain: "FilterEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Account not found"])
                }
                
                try await gmailService.deleteFilter(for: gmailAccount, filterId: filter.gmail_filter_id)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to delete filter: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct FilterTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(AppTheme.secondaryText)
                Text(title)
                    .font(AppTheme.subheadline)
                    .primaryText()
            }
            
            TextField(placeholder, text: $text)
                .primaryText()
                .keyboardType(keyboardType)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding(AppTheme.spacingMedium)
                .background(AppTheme.secondaryBackground)
                .cornerRadius(AppTheme.cornerRadiusMedium)
        }
        .padding(AppTheme.spacingMedium)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
    }
}

struct FilterToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(AppTheme.secondaryText)
                .frame(width: 20)
            
            Text(title)
                .font(AppTheme.subheadline)
                .primaryText()
            
            Spacer()
            
            Toggle("", isOn: $isOn)
        }
        .padding(AppTheme.spacingMedium)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
    }
}

struct FilterLabelPicker: View {
    let title: String
    let icon: String
    @Binding var selectedLabels: Set<String>
    let allLabels: [GmailLabel]
    
    @State private var showPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(AppTheme.accent)
                Text(title)
                    .font(AppTheme.subheadline)
                    .primaryText()
            }
            
            Button {
                showPicker = true
            } label: {
                HStack {
                    if selectedLabels.isEmpty {
                        Text("Select labels...")
                            .font(AppTheme.body)
                            .secondaryText()
                    } else {
                        Text("\(selectedLabels.count) label\(selectedLabels.count == 1 ? "" : "s") selected")
                            .font(AppTheme.body)
                            .primaryText()
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .secondaryText()
                }
                .padding(AppTheme.spacingMedium)
                .background(AppTheme.secondaryBackground)
                .cornerRadius(AppTheme.cornerRadiusMedium)
            }
        }
        .padding(AppTheme.spacingMedium)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .sheet(isPresented: $showPicker) {
            LabelMultiPickerView(
                title: title,
                selectedLabels: $selectedLabels,
                allLabels: allLabels
            )
        }
    }
}

struct LabelMultiPickerView: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    @Binding var selectedLabels: Set<String>
    let allLabels: [GmailLabel]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(allLabels, id: \.id) { label in
                    Button {
                        if selectedLabels.contains(label.id) {
                            selectedLabels.remove(label.id)
                        } else {
                            selectedLabels.insert(label.id)
                        }
                    } label: {
                        HStack {
                            Text(label.name)
                                .primaryText()
                            Spacer()
                            if selectedLabels.contains(label.id) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(AppTheme.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
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
        }
    }
}

#Preview {
    FilterEditorView(accountId: 1)
}








