//
//  IOSFeatureShellViews.swift
//  emptyMyInbox
//
//  Shared top chrome and Calendar / Action Items tabs (vault-backed).
//

import SwiftUI
import UIKit
import EmptyMyInboxShared

struct MainAppTopBar<Center: View>: View {
    @ViewBuilder var center: () -> Center
    var onMenuTap: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            LogoView(size: 40)

            Spacer()

            center()

            Spacer()

            Button(action: onMenuTap) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20))
                    .primaryText()
            }
            .iconButton()
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, AppTheme.spacingMedium)
    }
}

struct CalendarSkeletonView: View {
    var onMenuTap: () -> Void
    @EnvironmentObject private var rootState: AdaptiveRootState

    @StateObject private var calendarModel = GoogleCalendarViewModel()
    @State private var showVisibility = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if !rootState.usesWideChrome {
                        MainAppTopBar(center: {
                            Text("Calendar")
                                .font(AppTheme.headline)
                                .primaryText()
                        }, onMenuTap: onMenuTap)
                    }

                    calendarModeCarousel

                    GoogleCalendarTabContent(
                        model: calendarModel,
                        onOpenVisibility: { showVisibility = true },
                        accentColor: AppTheme.accent,
                        showsBuiltInModePicker: false
                    )
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showVisibility) {
            NavigationStack {
                CalendarVisibilitySettingsView()
                    .primaryBackground()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showVisibility = false }
                                .textButton()
                        }
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .companionVaultCalendarActionItemsRefresh)) { _ in
            Task { await calendarRefresh() }
        }
    }

    private func calendarRefresh() async {
        await VaultManager.shared.performLifecycleSync(postNotification: false)
        await calendarModel.refresh()
    }

    private var calendarModeCarousel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacingMedium) {
                    ForEach(GoogleCalendarViewModel.ViewMode.allCases, id: \.self) { mode in
                        Button {
                            calendarModel.mode = mode
                        } label: {
                            Text(mode.rawValue.capitalized)
                                .font(AppTheme.subheadline)
                                .foregroundColor(calendarModel.mode == mode ? AppTheme.primaryText : AppTheme.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                        .fill(calendarModel.mode == mode ? AppTheme.secondaryBackground : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                        .stroke(AppTheme.accent.opacity(calendarModel.mode == mode ? 0.5 : 0.15), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        Task { await calendarRefresh() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                                .font(AppTheme.subheadline)
                        }
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, AppTheme.spacingSmall)
            }

            VaultRefreshStatusLabel(font: .caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, AppTheme.spacingSmall)
        }
    }
}

private enum ActionItemsChromeMode: String, CaseIterable, Identifiable {
    case today
    case context
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .context: return "Context"
        case .calendar: return "Calendar"
        }
    }
}

private let actionItemsListMaxWidth: CGFloat = 600

private struct ActionItemsCenteredColumn<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            content()
                .frame(maxWidth: actionItemsListMaxWidth)
            Spacer(minLength: 0)
        }
    }
}

struct ActionItemsSkeletonView: View {
    var onMenuTap: () -> Void
    @EnvironmentObject private var rootState: AdaptiveRootState

    @ObservedObject private var vaultManager: VaultManager = .shared
    @State private var allItems: [VaultActionItemRecord] = []
    @State private var subjectGroups: [(key: String, items: [VaultActionItemRecord])] = []
    @State private var projectGroups: [(key: String, items: [VaultActionItemRecord])] = []
    @State private var selectedSubjectKey: String?
    @State private var selectedProjectKey: String?
    @State private var errorText: String?
    @State private var editorPayload: ActionItemEditorPayload?
    @State private var contextDefinitions: [VaultContextDefinition] = []
    @State private var projectDefinitions: [VaultProjectDefinition] = []
    @State private var typeDefinitions: [VaultActionTypeDefinition] = []
    @State private var showTagLibrary = false
    @State private var checklistScale: [String: CGFloat] = [:]
    @State private var priorityFilter: Int?
    @State private var urgencyFilter: Int?
    /// When set, shows a transient “Added / Undo” bar after creating an item.
    @State private var lastAddedItemUndoId: String?

    private let typePresets = ["Action item", "Learning", "Time block", "Meeting", "Event", "Reminder"]

    var body: some View {
        NavigationStack {
            actionItemsRootZStack
                .navigationBarHidden(true)
        }
        .task {
            await reloadTagDefinitions()
            await reload()
        }
        .onChange(of: priorityFilter) { _, _ in
            Task { await reload() }
        }
        .onChange(of: urgencyFilter) { _, _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaultDidSync)) { _ in
            Task {
                await reloadTagDefinitions()
                await reload()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .companionVaultCalendarActionItemsRefresh)) { _ in
            Task {
                await reloadTagDefinitions()
                await reload()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountAdded)) { _ in
            Task {
                await reloadTagDefinitions()
                await reload()
            }
        }
        .sheet(item: $editorPayload, content: editorSheet)
        .onChange(of: editorPayload) { _, new in
            if new == nil { lastAddedItemUndoId = nil }
        }
        .task(id: lastAddedItemUndoId) {
            guard lastAddedItemUndoId != nil else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            lastAddedItemUndoId = nil
        }
        .sheet(isPresented: $showTagLibrary) {
            NavigationStack {
                ActionItemTagLibraryView()
                    .primaryBackground()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showTagLibrary = false }
                        }
                    }
            }
        }
    }

    private var actionItemsRootZStack: some View {
        ZStack(alignment: .bottomTrailing) {
            AppTheme.primaryBackground
                .ignoresSafeArea()

            if vaultManager.isVaultReady {
                VStack(spacing: 0) {
                    if !rootState.usesWideChrome {
                        MainAppTopBar(center: {
                            Text("Action Items")
                                .font(AppTheme.headline)
                                .primaryText()
                        }, onMenuTap: onMenuTap)
                    }

                    actionItemsFilterCarousel

                    if let errorText {
                        Text(errorText)
                            .font(AppTheme.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal)
                    }

                    ActionItemsCenteredColumn {
                        listContent
                    }
                }

                Button {
                    presentAddSheet()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 62, height: 62)
                        .background(
                            Circle()
                                .fill(AppTheme.accent)
                                .shadow(color: AppTheme.accent.opacity(0.45), radius: 12, y: 4)
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, AppTheme.spacingMedium)
                .padding(.bottom, 56)
                .accessibilityLabel("Add Action Item")
            } else {
                VStack(spacing: 0) {
                    if !rootState.usesWideChrome {
                        MainAppTopBar(center: {
                            Text("Action Items")
                                .font(AppTheme.headline)
                                .primaryText()
                        }, onMenuTap: onMenuTap)
                    }

                    ScrollView {
                        ConfigureVaultPanel()
                            .padding(.horizontal, AppTheme.spacingMedium)
                            .padding(.vertical, AppTheme.spacingSmall)
                    }
                    .background(AppTheme.primaryBackground)
                }
            }
        }
    }

    @ViewBuilder
    private func editorSheet(payload: ActionItemEditorPayload) -> some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                ActionItemQuickEntryView(
                    initial: payload.item,
                    isNew: payload.isNew,
                    contexts: contextDefinitions,
                    projects: projectDefinitions,
                    types: typeDefinitions,
                    typePresets: typePresets,
                    allTasks: allItems,
                    style: .iosSheet,
                    vaultManager: vaultManager,
                    onSave: { saved, isNew in
                        await reload()
                        await reloadTagDefinitions()
                        if isNew {
                            lastAddedItemUndoId = saved.id
                            if #available(iOS 17.0, *) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            editorPayload = ActionItemEditorPayload(item: templateDraftForNewItem(), isNew: true)
                        } else {
                            lastAddedItemUndoId = nil
                            editorPayload = nil
                        }
                    },
                    onCancel: {
                        lastAddedItemUndoId = nil
                        editorPayload = nil
                    },
                    onManageTags: { showTagLibrary = true }
                )
                .id(payload.id)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(payload.isNew ? "New action" : "Edit action")
                            .font(AppTheme.headline)
                            .primaryText()
                    }
                }
            }

            if let undoId = lastAddedItemUndoId {
                HStack(spacing: 12) {
                    Text("Added")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer(minLength: 0)
                    Button("Undo") {
                        Task {
                            try? await vaultManager.deleteActionItem(id: undoId)
                            lastAddedItemUndoId = nil
                            await reload()
                            await reloadTagDefinitions()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .fill(AppTheme.secondaryBackground)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: lastAddedItemUndoId)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func reloadTagDefinitions() async {
        let vault = VaultManager.shared
        guard vault.isVaultReady else {
            contextDefinitions = []
            projectDefinitions = []
            typeDefinitions = []
            return
        }
        try? await vault.ensureDefaultContextDefinitions()
        _ = try? await vault.ensureGeneralProjectDefinition()
        contextDefinitions = (try? await vault.listContextDefinitions()) ?? []
        projectDefinitions = (try? await vault.listProjectDefinitions()) ?? []
        typeDefinitions = (try? await vault.listActionTypeDefinitions()) ?? []
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
                ActionItemsFeatureModel.contextBucketKey(for: $0, definitions: contextDefinitions) == selectedSubjectKey
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

    private var actionItemsFilterCarousel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacingMedium) {
                    Button {
                        selectedSubjectKey = nil
                        selectedProjectKey = nil
                    } label: {
                        Text("All")
                            .font(AppTheme.subheadline)
                            .foregroundColor(selectedSubjectKey == nil && selectedProjectKey == nil ? AppTheme.primaryText : AppTheme.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .fill(selectedSubjectKey == nil && selectedProjectKey == nil ? AppTheme.secondaryBackground : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)

                    ForEach(subjectGroups, id: \.key) { group in
                        Button {
                            selectedSubjectKey = selectedSubjectKey == group.key ? nil : group.key
                            if selectedSubjectKey != nil { selectedProjectKey = nil }
                        } label: {
                            Text(ActionItemsFeatureModel.displaySubjectHash(group.key))
                                .font(AppTheme.subheadline)
                                .foregroundColor(selectedSubjectKey == group.key ? AppTheme.primaryText : AppTheme.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                        .fill(selectedSubjectKey == group.key ? AppTheme.secondaryBackground : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(projectGroups, id: \.key) { group in
                        Button {
                            selectedProjectKey = selectedProjectKey == group.key ? nil : group.key
                            if selectedProjectKey != nil { selectedSubjectKey = nil }
                        } label: {
                            Text(ActionItemsFeatureModel.displayProjectPath(group.key))
                                .font(AppTheme.subheadline)
                                .foregroundColor(selectedProjectKey == group.key ? AppTheme.primaryText : AppTheme.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                        .fill(selectedProjectKey == group.key ? AppTheme.secondaryBackground : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        Task { await reload() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                                .font(AppTheme.subheadline)
                        }
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showTagLibrary = true
                    } label: {
                        Text("Contexts")
                            .font(AppTheme.subheadline)
                            .foregroundColor(AppTheme.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AppTheme.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    }
                    .buttonStyle(.plain)

                    ForEach(0 ... 4, id: \.self) { p in
                        Button {
                            priorityFilter = p
                        } label: {
                            Text("P\(p)")
                                .font(AppTheme.subheadline)
                                .foregroundColor(priorityFilter == p ? AppTheme.primaryText : AppTheme.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                        .fill(priorityFilter == p ? AppTheme.secondaryBackground : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                        .stroke(
                                            (priorityFilter == p ? ActionItemPriorityColors.color(forStoredPriority: p) : AppTheme.accent)
                                                .opacity(priorityFilter == p ? 0.55 : 0.15),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        urgencyFilter = nil
                    } label: {
                        Text("All U")
                            .font(AppTheme.subheadline)
                            .foregroundColor(urgencyFilter == nil ? AppTheme.primaryText : AppTheme.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .fill(urgencyFilter == nil ? AppTheme.secondaryBackground : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)

                    ForEach(0 ... 4, id: \.self) { u in
                        Button {
                            urgencyFilter = u
                        } label: {
                            Text("U\(u)")
                                .font(AppTheme.subheadline)
                                .foregroundColor(urgencyFilter == u ? AppTheme.primaryText : AppTheme.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                        .fill(urgencyFilter == u ? AppTheme.secondaryBackground : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                        .stroke(
                                            (urgencyFilter == u ? ActionItemPriorityColors.color(forStoredPriority: u) : AppTheme.accent)
                                                .opacity(urgencyFilter == u ? 0.55 : 0.15),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.spacingMedium)
                .padding(.bottom, AppTheme.spacingSmall)
            }

            VaultRefreshStatusLabel(font: .caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.spacingMedium)
                .padding(.bottom, AppTheme.spacingSmall)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            ForEach(filteredItems) { item in
                actionRow(item)
            }
            .onDelete { offsets in deleteFrom(filteredItems, offsets: offsets) }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
    }

    @ViewBuilder
    private func actionRow(_ item: VaultActionItemRecord) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacingMedium) {
            Button {
                Task { await toggleCompletion(for: item) }
            } label: {
                ZStack {
                    if item.isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    } else {
                        if let p = item.priority {
                            Circle()
                                .strokeBorder(ActionItemPriorityColors.color(forStoredPriority: p), lineWidth: 2)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
                .scaleEffect(checklistScale[item.id] ?? 1)
            }
            .buttonStyle(.plain)

            Button {
                editorPayload = ActionItemEditorPayload(item: item, isNew: false)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(AppTheme.body)
                            .strikethrough(item.isDone)
                            .primaryText()
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
                    if let ctxLabel = ActionItemsFeatureModel.resolvedContextDisplayName(for: item, definitions: contextDefinitions) {
                        Text(ActionItemsFeatureModel.displaySubjectHash(ctxLabel))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Text(ActionItemsFeatureModel.displayProjectPath(projectName(forProjectId: item.projectId)))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(AppTheme.secondaryBackground.opacity(0.35))
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
        do {
            try await vaultManager.updateActionItemCompletion(id: item.id, isDone: true)
        } catch {
            errorText = error.localizedDescription
            return
        }
        try? await Task.sleep(nanoseconds: 220_000_000)
        await reload()
    }

    private func templateDraftForNewItem() -> VaultActionItemRecord {
        ActionItemDraftComposer.newDraft(
            selectedSubjectKey: selectedSubjectKey,
            selectedProjectKey: selectedProjectKey,
            contextDefinitions: contextDefinitions,
            projectDefinitions: projectDefinitions,
            defaultGeneralProjectWhenNoProjectSelected: false
        )
    }

    private func presentAddSheet() {
        lastAddedItemUndoId = nil
        editorPayload = ActionItemEditorPayload(item: templateDraftForNewItem(), isNew: true)
    }

    private func projectName(forProjectId projectId: String?) -> String {
        guard let projectId else { return ActionItemsFeatureModel.generalProjectName }
        return projectDefinitions.first(where: { $0.id == projectId })?.name ?? ActionItemsFeatureModel.generalProjectName
    }

    private func deleteFrom(_ list: [VaultActionItemRecord], offsets: IndexSet) {
        Task {
            for i in offsets {
                try? await vaultManager.deleteActionItem(id: list[i].id)
            }
            await reload()
        }
    }

    private func reload() async {
        errorText = nil
        let vault = VaultManager.shared
        guard vault.isVaultReady else {
            allItems = []
            subjectGroups = []
            projectGroups = []
            return
        }
        await refreshListsFromVault(using: vault)
        await vault.performLifecycleSync(postNotification: false)
        await refreshListsFromVault(using: vault)
    }

    private func refreshListsFromVault(using vault: VaultManager) async {
        do {
            allItems = try await vault.listActionItems()
            let filtered = applyFilters(allItems)
            subjectGroups = ActionItemsFeatureModel.groupedBySubjectForSidebar(
                definitions: contextDefinitions,
                items: filtered
            )
            projectGroups = ActionItemsFeatureModel.groupedByProject(definitions: projectDefinitions, items: filtered)
        } catch {
            errorText = error.localizedDescription
            allItems = []
            subjectGroups = []
            projectGroups = []
        }
    }
}

// MARK: - Editor payload (iOS)

private struct ActionItemEditorPayload: Identifiable, Equatable {
    let id = UUID()
    var item: VaultActionItemRecord
    var isNew: Bool
}
