//
//  FilterEditorView.swift
//  emptyMyInbox
//
//  Comprehensive Gmail filter editor
//

import SwiftUI

struct FilterEditorView: View {
    @Environment(\.dismiss) var dismiss
    let filter: GmailFilter?
    let accountId: Int
    
    @State private var criteria: FilterCriteria
    @State private var actions: FilterActions
    @State private var labels: [Label] = []
    @State private var accounts: [EmailAccount] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    
    // Criteria state
    @State private var fromText = ""
    @State private var toText = ""
    @State private var subjectText = ""
    @State private var queryText = ""
    @State private var negatedQueryText = ""
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
                                
                                // Query (Gmail search syntax)
                                FilterTextField(
                                    title: "Search Query",
                                    placeholder: "Use Gmail search syntax",
                                    text: $queryText,
                                    icon: "magnifyingglass"
                                )
                                
                                // Negated Query
                                FilterTextField(
                                    title: "Does Not Match",
                                    placeholder: "Exclude emails matching...",
                                    text: $negatedQueryText,
                                    icon: "magnifyingglass.circle"
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
        
        do {
            async let labelsTask = APIService.shared.getLabels()
            async let accountsTask = APIService.shared.getAccounts()
            
            let (fetchedLabels, fetchedAccounts) = try await (labelsTask, accountsTask)
            
            await MainActor.run {
                self.labels = fetchedLabels
                self.accounts = fetchedAccounts
                
                // Initialize form fields from filter
                if let filter = filter {
                    fromText = filter.criteria.from ?? ""
                    toText = filter.criteria.to ?? ""
                    subjectText = filter.criteria.subject ?? ""
                    queryText = filter.criteria.query ?? ""
                    negatedQueryText = filter.criteria.negatedQuery ?? ""
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
                // Build criteria
                let sizeInBytes = sizeText.isEmpty ? nil : Int((Double(sizeText) ?? 0) * 1024 * 1024)
                let newCriteria = FilterCriteria(
                    from: fromText.isEmpty ? nil : fromText,
                    to: toText.isEmpty ? nil : toText,
                    subject: subjectText.isEmpty ? nil : subjectText,
                    query: queryText.isEmpty ? nil : queryText,
                    negatedQuery: negatedQueryText.isEmpty ? nil : negatedQueryText,
                    hasAttachment: hasAttachment ? true : nil,
                    excludeChats: excludeChats ? true : nil,
                    size: sizeInBytes,
                    sizeComparison: sizeText.isEmpty ? nil : sizeComparison
                )
                
                // Build actions
                let newActions = FilterActions(
                    addLabelIds: selectedAddLabels.isEmpty ? nil : Array(selectedAddLabels),
                    removeLabelIds: selectedRemoveLabels.isEmpty ? nil : Array(selectedRemoveLabels),
                    forward: forwardText.isEmpty ? nil : forwardText,
                    markAsRead: markAsRead ? true : nil,
                    archive: archive ? true : nil,
                    delete: delete ? true : nil,
                    alwaysMarkAsRead: alwaysMarkAsRead ? true : nil,
                    neverMarkAsRead: neverMarkAsRead ? true : nil,
                    neverSpam: neverSpam ? true : nil,
                    star: star ? true : nil
                )
                
                if let filter = filter {
                    // Update existing filter
                    _ = try await APIService.shared.updateFilter(
                        filterId: filter.id,
                        criteria: newCriteria,
                        actions: newActions
                    )
                } else {
                    // Create new filter
                    _ = try await APIService.shared.createFilter(
                        accountId: accountId,
                        criteria: newCriteria,
                        actions: newActions
                    )
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
                try await APIService.shared.deleteFilter(filterId: filter.id)
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
    let allLabels: [Label]
    
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
    let allLabels: [Label]
    
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






