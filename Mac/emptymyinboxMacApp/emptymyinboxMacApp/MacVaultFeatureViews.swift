//
//  MacVaultFeatureViews.swift
//  emptymyinboxMacApp
//

import SwiftUI
import EmptyMyInboxShared

struct MacVaultCalendarTab: View {
    @ObservedObject var model: GoogleCalendarViewModel
    var onOpenSettings: () -> Void
    @State private var showVisibility = false

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    ForEach(GoogleCalendarViewModel.ViewMode.allCases, id: \.self) { mode in
                        Button {
                            model.mode = mode
                        } label: {
                            Label(modeTitle(mode), systemImage: icon(for: mode))
                        }
                    }
                    Button {
                        Task {
                            await VaultManager.shared.performLifecycleSync(postNotification: false)
                            await model.refresh()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
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
            NavigationStack {
                GoogleCalendarTabContent(
                    model: model,
                    onOpenVisibility: { showVisibility = true },
                    accentColor: MacAppTheme.accent,
                    showsBuiltInModePicker: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacAppTheme.primaryBackground)
                .navigationTitle("Calendar")
            }
        }
        .background(MacAppTheme.primaryBackground)
        .sheet(isPresented: $showVisibility) {
            NavigationStack {
                CalendarVisibilitySettingsView()
                    .frame(minWidth: 420, minHeight: 400)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showVisibility = false }
                        }
                    }
            }
        }
    }

    private func modeTitle(_ mode: GoogleCalendarViewModel.ViewMode) -> String {
        mode.rawValue.capitalized
    }

    private func icon(for mode: GoogleCalendarViewModel.ViewMode) -> String {
        switch mode {
        case .events: return "list.bullet"
        case .day: return "sun.max"
        case .week: return "calendar.day.timeline.left"
        case .month: return "calendar"
        }
    }
}

private let macActionItemsListMaxWidth: CGFloat = 620

private struct MacActionItemsCenteredColumn<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            content()
                .frame(maxWidth: macActionItemsListMaxWidth)
            Spacer(minLength: 0)
        }
    }
}

struct MacVaultActionItemsTab: View {
    var onOpenSettings: () -> Void

    @ObservedObject private var vaultManager = VaultManager.shared
    @State private var allItems: [VaultActionItemRecord] = []
    @State private var subjectGroups: [(key: String, items: [VaultActionItemRecord])] = []
    @State private var projectGroups: [(key: String, items: [VaultActionItemRecord])] = []
    @State private var selectedSubjectKey: String?
    @State private var selectedProjectKey: String?
    @State private var errorText: String?
    @State private var editorPayload: MacActionItemEditorPayload?
    @State private var contextDefinitions: [VaultContextDefinition] = []
    @State private var projectDefinitions: [VaultProjectDefinition] = []
    @State private var typeDefinitions: [VaultActionTypeDefinition] = []
    @State private var showTagLibrary = false
    @State private var checklistScale: [String: CGFloat] = [:]
    @State private var priorityFilter: Int?
    @State private var urgencyFilter: Int?
    @State private var customHexSubjectKey: String?
    @State private var customHexDraft = ""
    @State private var priorityExpanded = true
    @State private var urgencyExpanded = true
    @State private var contextsExpanded = true
    @State private var projectsExpanded = true

    private let typePresets = ["Action item", "Learning", "Time block", "Meeting", "Event", "Reminder"]

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    DisclosureGroup(isExpanded: $priorityExpanded) {
                        Button { priorityFilter = nil } label: {
                            rowLabel("All", isSelected: priorityFilter == nil)
                        }
                        ForEach(0 ... 4, id: \.self) { p in
                            Button { priorityFilter = p } label: {
                                rowLabel("P\(p)", isSelected: priorityFilter == p, tint: ActionItemPriorityColors.color(forStoredPriority: p))
                            }
                        }
                    } label: {
                        Label("Priority", systemImage: "chevron.right")
                    }
                    DisclosureGroup(isExpanded: $urgencyExpanded) {
                        Button { urgencyFilter = nil } label: {
                            rowLabel("All", isSelected: urgencyFilter == nil)
                        }
                        ForEach(0 ... 4, id: \.self) { u in
                            Button { urgencyFilter = u } label: {
                                rowLabel("U\(u)", isSelected: urgencyFilter == u, tint: ActionItemPriorityColors.color(forStoredPriority: u))
                            }
                        }
                    } label: {
                        Label("Urgency", systemImage: "chevron.right")
                    }
                    DisclosureGroup(isExpanded: $contextsExpanded) {
                        ForEach(subjectGroups, id: \.key) { group in
                            Button {
                                selectedSubjectKey = selectedSubjectKey == group.key ? nil : group.key
                            } label: {
                                rowLabel(
                                    ActionItemsFeatureModel.displaySubjectHash(group.key),
                                    isSelected: selectedSubjectKey == group.key,
                                    trailing: "\(group.items.count)"
                                )
                            }
                            .contextMenu {
                                Menu("Accent color") {
                                    ForEach(ContextAccentPalette.presets) { preset in
                                        Button(preset.name) {
                                            Task { await setContextAccentHex(subjectKey: group.key, hex: preset.hex) }
                                        }
                                    }
                                    Divider()
                                    Button("Custom hex…") {
                                        customHexDraft = contextAccentHex(forSubjectKey: group.key)
                                        customHexSubjectKey = group.key
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Contexts", systemImage: "chevron.right")
                    }
                    DisclosureGroup(isExpanded: $projectsExpanded) {
                        ForEach(projectGroups, id: \.key) { group in
                            Button {
                                selectedProjectKey = selectedProjectKey == group.key ? nil : group.key
                            } label: {
                                rowLabel(
                                    ActionItemsFeatureModel.displayProjectPath(group.key),
                                    isSelected: selectedProjectKey == group.key,
                                    trailing: "\(group.items.count)"
                                )
                            }
                        }
                    } label: {
                        Label("Projects", systemImage: "chevron.right")
                    }
                }
                Section {
                    Button { onOpenSettings() } label: { Label("Settings", systemImage: "gearshape.fill") }
                    Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
            .scrollContentBackground(.hidden)
        } detail: {
            NavigationStack {
                VStack(alignment: .leading, spacing: 0) {
                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, MacAppTheme.spacingMedium)
                    }

                    MacActionItemsCenteredColumn {
                        List {
                            ForEach(filteredItems) { item in
                                macActionRow(item)
                            }
                            .onDelete { offsets in deleteFrom(filteredItems, offsets: offsets) }
                            macAddOrEditorSection
                        }
                        .scrollContentBackground(.hidden)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(MacAppTheme.primaryBackground)
                .navigationTitle("Action Items")
            }
        }
        .background(MacAppTheme.primaryBackground)
        .task {
            await reloadTagDefinitions()
            await reload()
        }
        .onChange(of: priorityFilter) { _, _ in Task { await reload() } }
        .onChange(of: urgencyFilter) { _, _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .vaultDidSync)) { _ in
            Task {
                await reloadTagDefinitions()
                await reload()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macActionItemsShouldReload)) { _ in
            Task { await reload() }
        }
        .sheet(isPresented: $showTagLibrary) {
            NavigationStack {
                ActionItemTagLibraryView()
                    .frame(minWidth: 420, minHeight: 480)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showTagLibrary = false }
                        }
                    }
            }
        }
        .alert("Custom accent color", isPresented: Binding(
            get: { customHexSubjectKey != nil },
            set: { if !$0 { customHexSubjectKey = nil } }
        )) {
            TextField("#RRGGBB", text: $customHexDraft)
            Button("Cancel", role: .cancel) {
                customHexSubjectKey = nil
            }
            Button("Save") {
                if let key = customHexSubjectKey,
                   let hex = ContextAccentPalette.normalizeHex(customHexDraft) {
                    Task {
                        await setContextAccentHex(subjectKey: key, hex: hex)
                        customHexSubjectKey = nil
                    }
                }
            }
        } message: {
            Text("Enter a 6-digit hex color (e.g. #FF5500).")
        }
    }

    private func reloadTagDefinitions() async {
        try? await vaultManager.ensureDefaultContextDefinitions()
        _ = try? await vaultManager.ensureGeneralProjectDefinition()
        contextDefinitions = (try? await vaultManager.listContextDefinitions()) ?? []
        projectDefinitions = (try? await vaultManager.listProjectDefinitions()) ?? []
        typeDefinitions = (try? await vaultManager.listActionTypeDefinitions()) ?? []
    }

    private func applyFilters(_ items: [VaultActionItemRecord]) -> [VaultActionItemRecord] {
        var filtered = items
        if let p = priorityFilter {
            filtered = filtered.filter { $0.priority == p }
        }
        if let u = urgencyFilter {
            filtered = filtered.filter { $0.urgency == u }
        }
        if let selectedSubjectKey {
            filtered = filtered.filter {
                ActionItemsFeatureModel.normalizedSubjectKey($0.subjectLabel) == selectedSubjectKey
            }
        }
        if let selectedProjectKey {
            let projectById = Dictionary(uniqueKeysWithValues: projectDefinitions.map { ($0.id, $0) })
            filtered = filtered.filter { item in
                guard let pid = item.projectId, let def = projectById[pid] else {
                    return selectedProjectKey == ActionItemsFeatureModel.generalProjectName
                }
                return ActionItemsFeatureModel.normalizedProjectKey(def.name) == selectedProjectKey
            }
        }
        return filtered
    }

    private var filteredItems: [VaultActionItemRecord] {
        ActionItemsFeatureModel.defaultSorted(applyFilters(allItems))
    }

    private func contextAccentHex(forSubjectKey key: String) -> String {
        if let def = ActionItemsFeatureModel.contextDefinition(matchingSubjectKey: key, definitions: contextDefinitions) {
            return def.accentColorHex ?? ContextAccentPalette.defaultGreyHex
        }
        return ContextAccentPalette.defaultGreyHex
    }

    private func setContextAccentHex(subjectKey: String, hex: String) async {
        if var existing = ActionItemsFeatureModel.contextDefinition(matchingSubjectKey: subjectKey, definitions: contextDefinitions) {
            existing.accentColorHex = hex
            try? await vaultManager.upsertContextDefinition(existing)
        } else {
            let order = (contextDefinitions.map(\.sortOrder).max() ?? 0) + 1
            let neu = VaultContextDefinition(name: subjectKey, accentColorHex: hex, sortOrder: order)
            try? await vaultManager.upsertContextDefinition(neu)
        }
        await reloadTagDefinitions()
        await reload()
    }

    @ViewBuilder
    private var macAddOrEditorSection: some View {
        Section {
            if let payload = editorPayload {
                ActionItemQuickEntryView(
                    initial: payload.item,
                    isNew: payload.isNew,
                    contexts: contextDefinitions,
                    projects: projectDefinitions,
                    types: typeDefinitions,
                    typePresets: typePresets,
                    allTasks: allItems,
                    style: .macCard,
                    vaultManager: vaultManager,
                    onSave: { _, isNew in
                        await reload()
                        await reloadTagDefinitions()
                        if isNew {
                            editorPayload = MacActionItemEditorPayload(item: templateDraftForNewItem(), isNew: true)
                        } else {
                            editorPayload = nil
                        }
                    },
                    onCancel: { editorPayload = nil },
                    onManageTags: { showTagLibrary = true }
                )
                .id(payload.id)
            } else {
                Button {
                    presentAddSheet()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.yellow)
                        Text("Add Action Item")
                            .foregroundStyle(MacAppTheme.primaryText)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func macActionRow(_ item: VaultActionItemRecord) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                Task { await toggleCompletion(for: item) }
            } label: {
                ZStack {
                    if item.isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(MacAppTheme.accent)
                    } else if let p = item.priority {
                        Circle()
                            .strokeBorder(ActionItemPriorityColors.color(forStoredPriority: p), lineWidth: 2)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
                }
                .scaleEffect(checklistScale[item.id] ?? 1)
            }
            .buttonStyle(.plain)

            Button {
                editorPayload = MacActionItemEditorPayload(item: item, isNew: false)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .strikethrough(item.isDone)
                            .foregroundStyle(MacAppTheme.primaryText)
                    }
                    if let p = item.priority {
                        Text("P\(p)")
                            .font(.caption2)
                            .foregroundStyle(ActionItemPriorityColors.color(forStoredPriority: p))
                    }
                    if let u = item.urgency {
                        Text("U\(u)")
                            .font(.caption2)
                            .foregroundStyle(ActionItemPriorityColors.color(forStoredPriority: u))
                    }
                    Text(ActionItemsFeatureModel.displayProjectPath(projectName(forProjectId: item.projectId)))
                        .font(.caption2)
                        .foregroundStyle(MacAppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("Mark done") {
                Task { await toggleCompletion(for: item) }
            }
        }
    }

    private func toggleCompletion(for item: VaultActionItemRecord) async {
        guard !item.isDone else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
            checklistScale[item.id] = 1.28
        }
        ActionItemCompletionFeedback.playCompletion()
        try? await Task.sleep(nanoseconds: 120_000_000)
        withAnimation(.easeOut(duration: 0.2)) {
            checklistScale[item.id] = 1
        }
        try? await vaultManager.updateActionItemCompletion(id: item.id, isDone: true)
        try? await Task.sleep(nanoseconds: 220_000_000)
        await reload()
    }

    private func deleteFrom(_ list: [VaultActionItemRecord], offsets: IndexSet) {
        Task {
            for i in offsets {
                try? await vaultManager.deleteActionItem(id: list[i].id)
            }
            await reload()
        }
    }

    private func templateDraftForNewItem() -> VaultActionItemRecord {
        var draft = VaultActionItemRecord(title: "")
        if let key = selectedSubjectKey, key != ActionItemsFeatureModel.unspecifiedSubjectKey {
            draft.subjectLabel = key
            if let def = ActionItemsFeatureModel.contextDefinition(matchingSubjectKey: key, definitions: contextDefinitions) {
                draft.contextId = def.id
            }
        }
        if let selectedProjectKey {
            if let project = projectDefinitions.first(where: {
                ActionItemsFeatureModel.normalizedProjectKey($0.name) == selectedProjectKey
            }) {
                draft.projectId = project.id
            }
        } else if let general = projectDefinitions.first(where: {
            ActionItemsFeatureModel.normalizedProjectKey($0.name) == ActionItemsFeatureModel.generalProjectName
        }) {
            draft.projectId = general.id
        }
        return draft
    }

    private func presentAddSheet() {
        editorPayload = MacActionItemEditorPayload(item: templateDraftForNewItem(), isNew: true)
    }

    private func reload() async {
        errorText = nil
        await vaultManager.performLifecycleSync(postNotification: false)
        do {
            allItems = try await vaultManager.listActionItems()
            let filtered = applyFilters(allItems)
            subjectGroups = ActionItemsFeatureModel.groupedBySubjectForSidebar(
                definitions: contextDefinitions,
                items: filtered
            )
            projectGroups = ActionItemsFeatureModel.groupedByProject(
                definitions: projectDefinitions,
                items: filtered
            )
        } catch {
            errorText = error.localizedDescription
            allItems = []
            subjectGroups = []
            projectGroups = []
        }
    }

    private func projectName(forProjectId projectId: String?) -> String {
        guard let projectId else { return ActionItemsFeatureModel.generalProjectName }
        return projectDefinitions.first(where: { $0.id == projectId })?.name ?? ActionItemsFeatureModel.generalProjectName
    }

    private func rowLabel(_ title: String, isSelected: Bool, tint: Color? = nil, trailing: String? = nil) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(tint ?? MacAppTheme.primaryText)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(MacAppTheme.secondaryText)
            }
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
}

// MARK: - macOS editor payload

private struct MacActionItemEditorPayload: Identifiable {
    let id = UUID()
    var item: VaultActionItemRecord
    var isNew: Bool
}
