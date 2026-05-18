//
//  MacVaultFeatureViews.swift
//  emptymyinboxMacApp
//

import SwiftUI
import EmptyMyInboxShared

private enum MacCalendarSidebarTool: String, CaseIterable, Identifiable {
    case dashboard
    case starred
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .starred: return "Starred"
        case .calendar: return "Calendar"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .starred: return "star.fill"
        case .calendar: return "calendar"
        }
    }
}

private struct MacSidebarCalendarRow: Identifiable {
    let id: String
    let accountEmail: String
    let calendarId: String
    let title: String
    /// Google Calendar `backgroundColor` hex for a subtle sidebar tint.
    let backgroundColorHex: String?
    var isVisible: Bool
    var isStarred: Bool
}

struct MacVaultCalendarTab: View {
    @ObservedObject var model: GoogleCalendarViewModel
    let snapshot: DashboardDataSnapshot?
    let dashboardActionItems: [VaultActionItemRecord]
    let isRefreshing: Bool
    let refreshMessage: String?
    var refreshState: MacSidebarRefreshState = .init()
    var onOpenSettings: () -> Void
    @State private var showVisibility = false
    @State private var selectedTool: MacCalendarSidebarTool = .calendar
    @State private var calendarsSectionExpanded = false
    @State private var sidebarCalendars: [MacSidebarCalendarRow] = []
    @State private var sidebarCalendarsLoadError: String?

    private var calendarFeatureShortcutSection: MacSidebarFeatureShortcutSection? {
        if selectedTool == .calendar || selectedTool == .starred {
            return MacSidebarFeatureShortcutSection(title: "Calendar", shortcuts: MacSidebarShortcutLibrary.calendarModes)
        }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            MacSidebarShell(
                minColumnWidth: 220,
                idealColumnWidth: 248,
                maxColumnWidth: 320,
                featureShortcutSection: calendarFeatureShortcutSection,
                onRefresh: {
                    Task {
                        await VaultManager.shared.performLifecycleSync(postNotification: false)
                        await model.refresh()
                        await reloadSidebarCalendars()
                    }
                },
                onOpenSettings: onOpenSettings,
                refreshState: refreshState,
                bottomAccessory: {
                    AnyView(
                        MacCalendarMiniMonthView(selectedDate: $model.selectedDate, accentColor: MacAppTheme.accent)
                    )
                }
            ) {
                Section {
                    ForEach(MacCalendarSidebarTool.allCases) { tool in
                        MacSidebarListRowButton(
                            accentWhenSelected: false,
                            title: tool.title,
                            icon: .system(tool.systemImage),
                            isSelected: selectedTool == tool,
                            action: {
                                selectedTool = tool
                                syncStarredFilterWithSelection()
                            }
                        )
                    }
                } header: {
                    Text("Tools")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MacAppTheme.secondaryText)
                }

                Section {
                    DisclosureGroup(isExpanded: $calendarsSectionExpanded) {
                        if let err = sidebarCalendarsLoadError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if sidebarCalendars.isEmpty {
                            Text("No calendars loaded.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach($sidebarCalendars) { $row in
                                MacCalendarSidebarCalendarRowView(row: $row) {
                                    sortSidebarCalendarsByVisibility()
                                    Task {
                                        await model.invalidateCalendarListCacheAndRefresh()
                                        await reloadSidebarCalendars()
                                    }
                                } onStarChanged: {
                                    Task {
                                        await model.refreshStarredKeysFromStore()
                                        await reloadSidebarCalendars()
                                    }
                                }
                            }
                        }
                    } label: {
                        Text("Calendars")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
                }
            }
            .focusable()
            .onKeyPress { press in
                MacCalendarModeKeyPress.handle(
                    press,
                    calendarModesActive: selectedTool == .calendar || selectedTool == .starred,
                    setMode: { model.mode = $0 }
                )
            }
        } detail: {
            NavigationStack {
                Group {
                    switch selectedTool {
                    case .dashboard:
                        MacUnifiedDashboardView(
                            calendarModel: model,
                            snapshot: snapshot,
                            actionItems: dashboardActionItems,
                            isRefreshing: isRefreshing,
                            refreshMessage: refreshMessage
                            // onOpenBrief / onOpenStories not available in Calendar tab
                        )
                    case .starred, .calendar:
                        GoogleCalendarTabContent(
                            model: model,
                            onOpenVisibility: { showVisibility = true },
                            accentColor: MacAppTheme.accent,
                            showsBuiltInModePicker: true
                        )
                        .focusable()
                        .onKeyPress { press in
                            MacCalendarModeKeyPress.handle(
                                press,
                                calendarModesActive: true,
                                setMode: { model.mode = $0 }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacAppTheme.primaryBackground)
                .navigationTitle(selectedTool == .dashboard ? "Dashboard" : "Calendar")
            }
        }
        .background(MacAppTheme.primaryBackground)
        .task {
            await model.refreshStarredKeysFromStore()
            syncStarredFilterWithSelection()
            await reloadSidebarCalendars()
        }
        .onChange(of: selectedTool) { _, _ in
            syncStarredFilterWithSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarVisibilityDidChange)) { _ in
            Task { await reloadSidebarCalendars() }
        }
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

    private func syncStarredFilterWithSelection() {
        model.setRestrictToStarredCalendars(selectedTool == .starred)
    }

    /// Visible (checked) calendars first, then hidden; title within each group.
    private func sortSidebarCalendarsByVisibility() {
        sidebarCalendars.sort { a, b in
            if a.isVisible != b.isVisible { return a.isVisible && !b.isVisible }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    private func reloadSidebarCalendars() async {
        sidebarCalendarsLoadError = nil
        let accounts = GmailAPIService.shared.getAllAccounts()
        guard !accounts.isEmpty else {
            sidebarCalendars = []
            return
        }

        var rows: [MacSidebarCalendarRow] = []
        for account in accounts {
            let enabled = await CalendarVisibilityStore.shared.isAccountEnabledForCalendar(accountEmail: account.email)
            guard enabled else { continue }

            do {
                let list = try await GoogleCalendarAPIService.listCalendars(for: account)
                for item in list {
                    let vis = await CalendarVisibilityStore.shared.isCalendarVisible(accountEmail: account.email, calendarId: item.id)
                    let star = await CalendarVisibilityStore.shared.isCalendarStarred(accountEmail: account.email, calendarId: item.id)
                    let key = "\(account.email.lowercased())|\(item.id)"
                    rows.append(
                        MacSidebarCalendarRow(
                            id: key,
                            accountEmail: account.email,
                            calendarId: item.id,
                            title: "\(item.summary) — \(account.email)",
                            backgroundColorHex: item.backgroundColor,
                            isVisible: vis,
                            isStarred: star
                        )
                    )
                }
            } catch {
                if error.isURLSessionCancellation { continue }
                sidebarCalendarsLoadError = "Could not load calendars."
                logWarning("Mac calendar sidebar list failed: \(error)", category: "Calendar")
            }
        }
        rows.sort { a, b in
            if a.isVisible != b.isVisible { return a.isVisible && !b.isVisible }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        sidebarCalendars = rows
    }
}

private struct MacCalendarSidebarCalendarRowView: View {
    @Binding var row: MacSidebarCalendarRow
    var onVisibilityChanged: () -> Void
    var onStarChanged: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            calendarColorAccent
            Toggle(
                "",
                isOn: Binding(
                    get: { row.isVisible },
                    set: { newValue in
                        row.isVisible = newValue
                        Task {
                            await CalendarVisibilityStore.shared.setCalendarVisible(
                                accountEmail: row.accountEmail,
                                calendarId: row.calendarId,
                                visible: newValue
                            )
                            onVisibilityChanged()
                        }
                    }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text(row.title)
                .font(.body)
                .lineLimit(2)
                .foregroundStyle(MacAppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                let next = !row.isStarred
                row.isStarred = next
                Task {
                    await CalendarVisibilityStore.shared.setCalendarStarred(
                        accountEmail: row.accountEmail,
                        calendarId: row.calendarId,
                        starred: next
                    )
                    onStarChanged()
                }
            } label: {
                Image(systemName: row.isStarred ? "star.fill" : "star")
                    .font(.body)
                    .foregroundStyle(row.isStarred ? MacAppTheme.accent : MacAppTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .help(row.isStarred ? "Remove from Starred" : "Add to Starred")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var calendarColorAccent: some View {
        if let hex = row.backgroundColorHex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(hex: hex).opacity(0.42))
                .frame(width: 3, height: 20)
        } else {
            Color.clear.frame(width: 3, height: 20)
        }
    }
}

private let macActionItemsListMaxWidth: CGFloat = 620

/// List (centered column) vs horizontal board columns for Action Items detail.
private enum MacActionItemsDetailViewMode: String, CaseIterable, Identifiable, Hashable {
    case list
    case board
    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: return "List"
        case .board: return "Board"
        }
    }
}

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

/// Vertically scrolling list of action rows, capped width and centered (matches quick-add column).
private struct MacActionItemsCenteredScrollList<Row: View>: View {
    let items: [VaultActionItemRecord]
    @ViewBuilder var row: (VaultActionItemRecord) -> Row

    var body: some View {
        MacActionItemsCenteredColumn {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// List view with a section header per project (same width as `MacActionItemsCenteredScrollList`).
private struct MacActionItemsGroupedByProjectScrollList<Row: View>: View {
    let groups: [(key: String, items: [VaultActionItemRecord])]
    @ViewBuilder var row: (VaultActionItemRecord) -> Row

    var body: some View {
        MacActionItemsCenteredColumn {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groups, id: \.key) { pair in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ActionItemsFeatureModel.displayProjectPath(pair.key))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MacAppTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(pair.items) { item in
                                row(item)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacVaultActionItemsTab: View {
    @ObservedObject var calendarModel: GoogleCalendarViewModel
    let snapshot: DashboardDataSnapshot?
    /// Open tasks for the unified dashboard (from `ContentView` / vault).
    let dashboardActionItems: [VaultActionItemRecord]
    let isRefreshing: Bool
    let refreshMessage: String?
    var refreshState: MacSidebarRefreshState = .init()
    var onOpenSettings: () -> Void

    @ObservedObject private var vaultManager = VaultManager.shared
    @State private var allItems: [VaultActionItemRecord] = []
    /// First paint uses a neutral default; `applyInitialActionItemsRouteIfNeeded` sets Today vs Sticky Board after load.
    @State private var route: ActionItemsSidebarDestination = .stickyBoard
    @State private var hasAppliedInitialActionItemsRoute = false
    @State private var errorText: String?
    @State private var editorPayload: MacActionItemEditorPayload?
    @State private var contextDefinitions: [VaultContextDefinition] = []
    @State private var projectDefinitions: [VaultProjectDefinition] = []
    @State private var typeDefinitions: [VaultActionTypeDefinition] = []
    @State private var showTagLibrary = false
    @State private var checklistScale: [String: CGFloat] = [:]
    @State private var customHexSubjectKey: String?
    @State private var customHexDraft = ""
    @State private var lastAddedItemUndoId: String?
    @State private var showCreateLabelSheet = false
    @State private var showCreateProjectSheet = false
    @State private var newLabelName = ""
    @State private var newProjectName = ""
    @State private var sidebarPins: [ActionItemsSidebarPin] = []
    @State private var renamingTarget: RenamingTarget?
    @State private var renameFieldText = ""
    @State private var deletingTarget: DeletingTarget?
    /// Like Slack’s **Channels** list: project channels stay visible without selecting Projects first.
    @State private var projectsSidebarExpanded = true

    private let typePresets = ["Action item", "Learning", "Time block", "Meeting", "Event", "Reminder"]

    private var actionItemsFeatureShortcutSection: MacSidebarFeatureShortcutSection {
        MacSidebarFeatureShortcutSection(
            title: "Action Items",
            shortcuts: [
                MacSidebarContextualShortcut(title: "Priority", shortcutDisplay: "p0–p4"),
                MacSidebarContextualShortcut(title: "Urgency", shortcutDisplay: "u0–u4"),
                MacSidebarContextualShortcut(title: "Labels", shortcutDisplay: "@"),
                MacSidebarContextualShortcut(title: "Projects", shortcutDisplay: "#"),
            ]
        )
    }

    @AppStorage("macActionItemsDetailViewMode") private var detailViewModeRaw: String = MacActionItemsDetailViewMode.list.rawValue

    private var detailViewModeBinding: Binding<MacActionItemsDetailViewMode> {
        Binding(
            get: { MacActionItemsDetailViewMode(rawValue: detailViewModeRaw) ?? .list },
            set: { detailViewModeRaw = $0.rawValue }
        )
    }

    private var detailViewMode: MacActionItemsDetailViewMode {
        MacActionItemsDetailViewMode(rawValue: detailViewModeRaw) ?? .list
    }

    /// Dashboard / Planner use their own layout; everything else can switch list vs board.
    private var supportsActionItemsViewModeToggle: Bool {
        switch route {
        case .dashboard, .planner: return false
        default: return true
        }
    }

    /// Once per tab lifetime: if any task is scheduled for today, open Today; otherwise Sticky Board. (Does not run again after sync reloads.)
    private func applyInitialActionItemsRouteIfNeeded() {
        guard !hasAppliedInitialActionItemsRoute else { return }
        guard vaultManager.isVaultReady else { return }
        hasAppliedInitialActionItemsRoute = true
        let todayItems = ActionItemsFeatureModel.itemsScheduledForCalendarDay(
            referenceDay: Date(),
            calendar: .current,
            items: allItems
        )
        route = todayItems.isEmpty ? .stickyBoard : .today
    }

    private enum RenamingTarget: Identifiable, Equatable {
        case project(VaultProjectDefinition)
        case labelContext(VaultContextDefinition)
        case labelSubjectKey(String)
        var id: String {
            switch self {
            case .project(let p): return "rename-p-\(p.id)"
            case .labelContext(let c): return "rename-c-\(c.id)"
            case .labelSubjectKey(let k): return "rename-k-\(k)"
            }
        }
    }

    private enum DeletingTarget: Identifiable, Equatable {
        case project(VaultProjectDefinition)
        case labelSubjectKey(String)
        var id: String {
            switch self {
            case .project(let p): return "del-p-\(p.id)"
            case .labelSubjectKey(let k): return "del-k-\(k)"
            }
        }
    }

    var body: some View {
        Group {
            if vaultManager.isVaultReady {
                NavigationSplitView {
                    macActionItemsSidebar
                } detail: {
                    macActionItemsDetail
                }
            } else {
                macActionItemsVaultRequiredPlaceholder
            }
        }
        .tint(MacAppTheme.accent)
        .background(MacAppTheme.primaryBackground)
        .task {
            await reloadTagDefinitions()
            await reload()
            applyInitialActionItemsRouteIfNeeded()
        }
        .onChange(of: editorPayload) { _, new in
            if new == nil { lastAddedItemUndoId = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaultDidSync)) { _ in
            Task {
                await reloadTagDefinitions()
                await reload()
                applyInitialActionItemsRouteIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macActionItemsShouldReload)) { _ in
            Task { await reload() }
        }
        .onChange(of: vaultManager.activeConfiguration?.vaultId) { _, newId in
            if newId == nil {
                hasAppliedInitialActionItemsRoute = false
            }
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
        .sheet(isPresented: $showCreateLabelSheet) {
            createLabelSheet
        }
        .sheet(isPresented: $showCreateProjectSheet) {
            createProjectSheet
        }
        .sheet(item: $renamingTarget) { target in
            renameLabelOrProjectSheet(target: target)
        }
        .onChange(of: renamingTarget) { _, new in
            guard let new else { return }
            switch new {
            case .project(let p): renameFieldText = p.name
            case .labelContext(let c): renameFieldText = c.name
            case .labelSubjectKey(let k): renameFieldText = k
            }
        }
        .alert(deleteAlertTitle, isPresented: Binding(
            get: { deletingTarget != nil },
            set: { if !$0 { deletingTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { deletingTarget = nil }
            Button("Delete", role: .destructive) {
                let t = deletingTarget
                deletingTarget = nil
                if let t {
                    Task { await performDelete(t) }
                }
            }
        } message: {
            Text(deleteAlertMessage)
        }
    }

    private var deleteAlertTitle: String {
        switch deletingTarget {
        case .some(.project): return "Delete project?"
        case .some(.labelSubjectKey): return "Delete label?"
        case .none: return ""
        }
    }

    private var deleteAlertMessage: String {
        switch deletingTarget {
        case .some(.project(let p)):
            return "“\(p.name)” will be removed. Tasks in this project move to General."
        case .some(.labelSubjectKey(let key)):
            return "“\(key)” will be removed. Tasks lose this label."
        case .none:
            return ""
        }
    }

    private var macActionItemsVaultRequiredPlaceholder: some View {
        NavigationStack {
            ScrollView {
                ConfigureVaultPanel()
                    .padding(24)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacAppTheme.primaryBackground)
        }
    }

    private var prioritySidebarChannelIds: [String] {
        var ids = ["p0", "p1", "p2", "p3", "p4", "none"]
        if allItems.contains(where: { ActionItemsFeatureModel.priorityBucketId(for: $0) == "other" }) {
            ids.append("other")
        }
        return ids
    }

    private var urgencySidebarChannelIds: [String] {
        var ids = ["u0", "u1", "u2", "u3", "u4", "none"]
        if allItems.contains(where: { ActionItemsFeatureModel.urgencyBucketId(for: $0) == "other" }) {
            ids.append("other")
        }
        return ids
    }

    private var labelSidebarColumns: [ActionItemsBoardColumn] {
        ActionItemsFeatureModel.boardColumnsForLabels(definitions: contextDefinitions, items: allItems)
    }

    private var projectSidebarColumns: [ActionItemsBoardColumn] {
        ActionItemsFeatureModel.boardColumnsForProjects(definitions: projectDefinitions, items: allItems)
    }

    @ViewBuilder
    private var macActionItemsSidebar: some View {
        MacSidebarShell(
            minColumnWidth: 220,
            idealColumnWidth: 248,
            maxColumnWidth: 320,
            featureShortcutSection: actionItemsFeatureShortcutSection,
            onRefresh: { Task { await reload() } },
            onOpenSettings: onOpenSettings,
            refreshState: refreshState
        ) {
            Section {
                MacSidebarListRowButton(
                    title: "Dashboard",
                    icon: .system("gauge.with.dots.needle.33percent"),
                    isSelected: route == .dashboard,
                    action: { route = .dashboard }
                )
                MacSidebarListRowButton(
                    title: ActionItemsSection.planner.navigationTitle,
                    icon: .system(ActionItemsSection.planner.sidebarSystemImage),
                    isSelected: route == .planner,
                    action: { route = .planner }
                )
                MacSidebarListRowButton(
                    title: ActionItemsSidebarDestination.stickyBoard.navigationTitle,
                    icon: .system("rectangle.on.rectangle.angled"),
                    isSelected: route == .stickyBoard,
                    action: { route = .stickyBoard }
                )
                MacSidebarListRowButton(
                    title: ActionItemsSidebarDestination.today.navigationTitle,
                    icon: .system("sun.max.fill"),
                    isSelected: route == .today,
                    action: { route = .today }
                )
            } header: {
                Text("Tools")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MacAppTheme.secondaryText)
            }

            starredSidebarSection

            categoriesSidebarSection
        }
    }

    private var starredSidebarSection: some View {
        Section {
            ForEach(sidebarPins, id: \.self) { pin in
                starredSidebarPinRow(pin)
            }
        } header: {
            Text("Starred")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MacAppTheme.secondaryText)
        }
    }

    private var categoriesSidebarSection: some View {
        Section {
            MacSidebarListRowButton(
                title: ActionItemsSection.priority.navigationTitle,
                icon: .asset(MacActionItemsCategorySidebarAsset.priority),
                isSelected: route.isPriorityCategorySelected,
                action: { route = .priorityHome }
            )
            if route.isPriorityCategorySelected {
                ForEach(prioritySidebarChannelIds, id: \.self) { boardId in
                    let pin = ActionItemsSidebarPin(kind: .priorityChannel, identifier: boardId)
                    categoryChannelRow(
                        leadingInset: 10,
                        title: ActionItemsFeatureModel.priorityBoardTitle(forBoardId: boardId),
                        isSelected: route == .priorityChannel(boardId: boardId),
                        navigate: { route = .priorityChannel(boardId: boardId) },
                        pin: pin,
                        isPinned: sidebarPins.contains(pin)
                    )
                }
            }

            MacSidebarListRowButton(
                title: ActionItemsSection.urgency.navigationTitle,
                icon: .asset(MacActionItemsCategorySidebarAsset.urgency),
                isSelected: route.isUrgencyCategorySelected,
                action: { route = .urgencyHome }
            )
            if route.isUrgencyCategorySelected {
                ForEach(urgencySidebarChannelIds, id: \.self) { boardId in
                    let pin = ActionItemsSidebarPin(kind: .urgencyChannel, identifier: boardId)
                    categoryChannelRow(
                        leadingInset: 10,
                        title: ActionItemsFeatureModel.urgencyBoardTitle(forBoardId: boardId),
                        isSelected: route == .urgencyChannel(boardId: boardId),
                        navigate: { route = .urgencyChannel(boardId: boardId) },
                        pin: pin,
                        isPinned: sidebarPins.contains(pin)
                    )
                }
            }

            labelsCategoryRowWithMenu

            if route.isLabelsCategorySelected {
                ForEach(labelSidebarColumns, id: \.boardId) { col in
                    let pin = ActionItemsSidebarPin(kind: .labelChannel, identifier: col.boardId)
                    let canEditLabel = col.boardId != ActionItemsFeatureModel.unspecifiedSubjectKey
                    categoryChannelRow(
                        leadingInset: 10,
                        title: col.title,
                        isSelected: route == .labelChannel(subjectKey: col.boardId),
                        navigate: { route = .labelChannel(subjectKey: col.boardId) },
                        pin: pin,
                        isPinned: sidebarPins.contains(pin),
                        onRename: canEditLabel
                            ? {
                                if let t = renamingTargetForLabelColumn(col) { renamingTarget = t }
                            }
                            : nil,
                        onDelete: canEditLabel
                            ? { deletingTarget = .labelSubjectKey(col.boardId) }
                            : nil
                    )
                }
            }

            projectsCategoryRowWithMenu

            if projectsSidebarExpanded {
                ForEach(projectSidebarColumns, id: \.boardId) { col in
                    let pin = ActionItemsSidebarPin(kind: .projectChannel, identifier: col.boardId)
                    let projectDef = projectDefinitions.first(where: { ActionItemsFeatureModel.normalizedProjectKey($0.name) == col.boardId })
                    let canEditProject = projectDef != nil && col.boardId != ActionItemsFeatureModel.generalProjectName
                    categoryChannelRow(
                        leadingInset: 10,
                        title: col.title,
                        isSelected: route == .projectChannel(projectKey: col.boardId),
                        navigate: { route = .projectChannel(projectKey: col.boardId) },
                        pin: pin,
                        isPinned: sidebarPins.contains(pin),
                        onRename: canEditProject
                            ? {
                                if let t = renamingTargetForProjectColumn(col) { renamingTarget = t }
                            }
                            : nil,
                        onDelete: canEditProject
                            ? {
                                if let t = deletingTargetForProjectColumn(col) { deletingTarget = t }
                            }
                            : nil
                    )
                }
            }
        } header: {
            Text("Categories")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MacAppTheme.secondaryText)
        }
    }

    private var labelsCategoryRowWithMenu: some View {
        HStack(alignment: .center, spacing: 4) {
            Button {
                route = .labelsHome
            } label: {
                MacSidebarRowLeadingContent(
                    title: ActionItemsSection.labels.navigationTitle,
                    icon: .asset(MacActionItemsCategorySidebarAsset.labels)
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(route.isLabelsCategorySelected ? MacAppTheme.accent : MacAppTheme.primaryText)

            Menu {
                Button("New label…") {
                    newLabelName = ""
                    showCreateLabelSheet = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(MacAppTheme.secondaryText)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help("Label actions")
        }
        .listRowBackground(route.isLabelsCategorySelected ? MacAppTheme.sidebarSelectionBackground : Color.clear)
    }

    private var projectsCategoryRowWithMenu: some View {
        HStack(alignment: .center, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    projectsSidebarExpanded.toggle()
                }
            } label: {
                Image(systemName: projectsSidebarExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacAppTheme.secondaryText)
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(projectsSidebarExpanded ? "Collapse projects" : "Expand projects")

            HStack(alignment: .center, spacing: 4) {
                Button {
                    route = .projectsHome
                } label: {
                    MacSidebarRowLeadingContent(
                        title: ActionItemsSection.projects.navigationTitle,
                        icon: .asset(MacActionItemsCategorySidebarAsset.projects)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(route.isProjectsCategorySelected ? MacAppTheme.accent : MacAppTheme.primaryText)

                Menu {
                    Button("New project…") {
                        newProjectName = ""
                        showCreateProjectSheet = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(MacAppTheme.secondaryText)
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .help("Project actions")
            }
        }
        .listRowBackground(route.isProjectsCategorySelected ? MacAppTheme.sidebarSelectionBackground : Color.clear)
    }

    @ViewBuilder
    private func categoryChannelRow(
        leadingInset: CGFloat,
        title: String,
        isSelected: Bool,
        navigate: @escaping () -> Void,
        pin: ActionItemsSidebarPin,
        isPinned: Bool,
        onRename: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Button(action: navigate) {
                HStack(spacing: 8) {
                    if leadingInset > 0 {
                        Color.clear.frame(width: leadingInset)
                    }
                    Text(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelected ? MacAppTheme.accent : MacAppTheme.primaryText)

            Button {
                toggleSidebarPin(pin)
            } label: {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isPinned ? MacAppTheme.accent : MacAppTheme.secondaryText.opacity(0.88))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Remove from Starred section" : "Add to Starred section")
        }
        .optionalCategoryChannelContextMenu(onRename: onRename, onDelete: onDelete)
        .listRowBackground(isSelected ? MacAppTheme.sidebarSelectionBackground : Color.clear)
    }

    private func renamingTargetForLabelColumn(_ col: ActionItemsBoardColumn) -> RenamingTarget? {
        guard col.boardId != ActionItemsFeatureModel.unspecifiedSubjectKey else { return nil }
        if let def = ActionItemsFeatureModel.contextDefinition(matchingSubjectKey: col.boardId, definitions: contextDefinitions) {
            return .labelContext(def)
        }
        return .labelSubjectKey(col.boardId)
    }

    private func renamingTargetForProjectColumn(_ col: ActionItemsBoardColumn) -> RenamingTarget? {
        guard col.boardId != ActionItemsFeatureModel.generalProjectName else { return nil }
        guard let def = projectDefinitions.first(where: { ActionItemsFeatureModel.normalizedProjectKey($0.name) == col.boardId }) else { return nil }
        return .project(def)
    }

    private func deletingTargetForProjectColumn(_ col: ActionItemsBoardColumn) -> DeletingTarget? {
        guard col.boardId != ActionItemsFeatureModel.generalProjectName else { return nil }
        guard let def = projectDefinitions.first(where: { ActionItemsFeatureModel.normalizedProjectKey($0.name) == col.boardId }) else { return nil }
        return .project(def)
    }

    @ViewBuilder
    private func starredSidebarPinRow(_ pin: ActionItemsSidebarPin) -> some View {
        let destination = pin.toRoute()
        let isSelected = route == destination
        HStack(spacing: 4) {
            Button {
                route = destination
            } label: {
                Text(pin.pinRowTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelected ? MacAppTheme.accent : MacAppTheme.primaryText)

            Button {
                toggleSidebarPin(pin)
            } label: {
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacAppTheme.accent)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove from Starred section")
        }
        .listRowBackground(isSelected ? MacAppTheme.sidebarSelectionBackground : Color.clear)
    }

    private func toggleSidebarPin(_ pin: ActionItemsSidebarPin) {
        Task {
            var next = sidebarPins
            if let i = next.firstIndex(of: pin) {
                next.remove(at: i)
            } else {
                next.append(pin)
            }
            next.sort { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
            do {
                try await vaultManager.saveStarredSidebarChannels(next)
                await vaultManager.performLifecycleSync(postNotification: true)
                sidebarPins = try await vaultManager.loadStarredSidebarChannels()
            } catch {}
        }
    }

    private var createLabelSheet: some View {
        NavigationStack {
            Form {
                TextField("Label name", text: $newLabelName)
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            .navigationTitle("New label")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreateLabelSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createLabelFromSheet() }
                    }
                    .disabled(newLabelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 360, minHeight: 160)
        }
    }

    private var createProjectSheet: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            .navigationTitle("New project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreateProjectSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createProjectFromSheet() }
                    }
                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 360, minHeight: 160)
        }
    }

    @ViewBuilder
    private func renameLabelOrProjectSheet(target: RenamingTarget) -> some View {
        NavigationStack {
            Form {
                TextField("Name", text: $renameFieldText)
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            .navigationTitle("Rename")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { renamingTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await performRename(from: target) }
                    }
                    .disabled(renameFieldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 360, minHeight: 160)
        }
    }

    private func performRename(from target: RenamingTarget) async {
        let text = renameFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            renamingTarget = nil
            return
        }
        defer { renamingTarget = nil }
        switch target {
        case .project(let p):
            let oldKey = ActionItemsFeatureModel.normalizedProjectKey(p.name)
            let newKey = ActionItemsFeatureModel.normalizedProjectKey(text)
            do {
                try await vaultManager.renameProjectDefinition(id: p.id, newDisplayName: text)
                await migrateProjectPins(oldKey: oldKey, newKey: newKey)
                routeAfterProjectRename(oldKey: oldKey, newKey: newKey)
                await reloadTagDefinitions()
                await reload()
            } catch {}
        case .labelContext(let c):
            let oldKey = ActionItemsFeatureModel.normalizedSubjectKey(c.name)
            let newKey = ActionItemsFeatureModel.normalizedSubjectKey(text)
            do {
                try await vaultManager.renameContextDefinition(id: c.id, newDisplayName: text)
                await migrateLabelPins(oldKey: oldKey, newKey: newKey)
                routeAfterLabelRename(oldKey: oldKey, newKey: newKey)
                await reloadTagDefinitions()
                await reload()
            } catch {}
        case .labelSubjectKey(let key):
            let newKey = ActionItemsFeatureModel.normalizedSubjectKey(text)
            do {
                try await vaultManager.renameLabelBucketItemOnly(oldSubjectKey: key, newDisplayName: text)
                await migrateLabelPins(oldKey: key, newKey: newKey)
                routeAfterLabelRename(oldKey: key, newKey: newKey)
                await reloadTagDefinitions()
                await reload()
            } catch {}
        }
    }

    private func performDelete(_ target: DeletingTarget) async {
        switch target {
        case .project(let p):
            let key = ActionItemsFeatureModel.normalizedProjectKey(p.name)
            do {
                try await vaultManager.deleteProjectMovingTasksToGeneral(projectId: p.id)
                await removeProjectPins(projectKey: key)
                if case .projectChannel(let k) = route, k == key {
                    route = .projectsHome
                }
                await reloadTagDefinitions()
                await reload()
            } catch {}
        case .labelSubjectKey(let key):
            do {
                try await vaultManager.deleteLabelBucket(subjectKey: key)
                await removeLabelPins(subjectKey: key)
                if case .labelChannel(let k) = route, k == key {
                    route = .labelsHome
                }
                await reloadTagDefinitions()
                await reload()
            } catch {}
        }
    }

    private func migrateProjectPins(oldKey: String, newKey: String) async {
        guard oldKey != newKey else { return }
        let next = sidebarPins.map { p -> ActionItemsSidebarPin in
            if p.kind == .projectChannel && p.identifier == oldKey {
                return ActionItemsSidebarPin(kind: .projectChannel, identifier: newKey)
            }
            return p
        }
        do {
            try await vaultManager.saveStarredSidebarChannels(next)
            await vaultManager.performLifecycleSync(postNotification: true)
            sidebarPins = try await vaultManager.loadStarredSidebarChannels()
        } catch {}
    }

    private func migrateLabelPins(oldKey: String, newKey: String) async {
        guard oldKey != newKey else { return }
        let next = sidebarPins.map { p -> ActionItemsSidebarPin in
            if p.kind == .labelChannel && p.identifier == oldKey {
                return ActionItemsSidebarPin(kind: .labelChannel, identifier: newKey)
            }
            return p
        }
        do {
            try await vaultManager.saveStarredSidebarChannels(next)
            await vaultManager.performLifecycleSync(postNotification: true)
            sidebarPins = try await vaultManager.loadStarredSidebarChannels()
        } catch {}
    }

    private func removeProjectPins(projectKey: String) async {
        let next = sidebarPins.filter { !($0.kind == .projectChannel && $0.identifier == projectKey) }
        do {
            try await vaultManager.saveStarredSidebarChannels(next)
            await vaultManager.performLifecycleSync(postNotification: true)
            sidebarPins = try await vaultManager.loadStarredSidebarChannels()
        } catch {}
    }

    private func removeLabelPins(subjectKey: String) async {
        let next = sidebarPins.filter { !($0.kind == .labelChannel && $0.identifier == subjectKey) }
        do {
            try await vaultManager.saveStarredSidebarChannels(next)
            await vaultManager.performLifecycleSync(postNotification: true)
            sidebarPins = try await vaultManager.loadStarredSidebarChannels()
        } catch {}
    }

    private func routeAfterProjectRename(oldKey: String, newKey: String) {
        if case .projectChannel(let k) = route, k == oldKey {
            route = .projectChannel(projectKey: newKey)
        }
    }

    private func routeAfterLabelRename(oldKey: String, newKey: String) {
        if case .labelChannel(let k) = route, k == oldKey {
            route = .labelChannel(subjectKey: newKey)
        }
    }

    @ViewBuilder
    private var macActionItemsDetail: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, MacAppTheme.spacingMedium)
                    }

                    categoryDetailContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.easeInOut(duration: 0.22), value: route)

                    Divider()
                        .opacity(0.35)

                    MacActionItemsCenteredColumn {
                        List {
                            macAddOrEditorSection
                        }
                        .scrollContentBackground(.hidden)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 20, leading: 8, bottom: 24, trailing: 8))
                    }
                    .frame(maxWidth: .infinity)
                    .background(MacAppTheme.primaryBackground)
                }
                .background(MacAppTheme.primaryBackground)
                .navigationTitle(route.navigationTitle)
                .toolbar {
                    if supportsActionItemsViewModeToggle {
                        ToolbarItem(placement: .primaryAction) {
                            Picker("Layout", selection: detailViewModeBinding) {
                                ForEach(MacActionItemsDetailViewMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(minWidth: 176)
                            .help("List or board layout")
                        }
                    }
                }

                if let undoId = lastAddedItemUndoId {
                    HStack(spacing: 12) {
                        Text("Added")
                            .font(.subheadline)
                            .foregroundStyle(MacAppTheme.primaryText)
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
                        .foregroundStyle(MacAppTheme.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 420)
                    .background(
                        RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall)
                            .fill(MacAppTheme.secondaryBackground)
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
                    )
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: lastAddedItemUndoId)
            .task(id: lastAddedItemUndoId) {
                guard lastAddedItemUndoId != nil else { return }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                lastAddedItemUndoId = nil
            }
        }
    }

    /// All open tasks, grouped by project (same buckets as **Projects**).
    @ViewBuilder
    private var stickyBoardDetailContent: some View {
        let boardColumns = ActionItemsFeatureModel.boardColumnsForProjects(
            definitions: projectDefinitions,
            items: allItems
        )
        let listGroups = ActionItemsFeatureModel.groupedByProject(definitions: projectDefinitions, items: allItems)
            .filter { !$0.items.isEmpty }
        Group {
            if allItems.isEmpty {
                MacActionItemsCenteredColumn {
                    ContentUnavailableView {
                        Label("No action items", systemImage: "rectangle.on.rectangle.angled")
                    } description: {
                        Text("Add an action item using the form below.")
                    }
                    .foregroundStyle(MacAppTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if detailViewMode == .board {
                MacActionItemsBoardsScrollView(columns: boardColumns, row: { item in macActionRow(item) })
            } else {
                MacActionItemsGroupedByProjectScrollList(groups: listGroups, row: { macActionRow($0) })
            }
        }
    }

    /// Open tasks with `scheduledDate` on the current calendar day.
    @ViewBuilder
    private var todayDetailContent: some View {
        let items = ActionItemsFeatureModel.itemsScheduledForCalendarDay(
            referenceDay: Date(),
            calendar: .current,
            items: allItems
        )
        let boardColumn = ActionItemsBoardColumn(
            boardId: "today",
            title: "Today",
            items: items
        )
        Group {
            if items.isEmpty {
                MacActionItemsCenteredColumn {
                    ContentUnavailableView {
                        Label("Nothing scheduled today", systemImage: "sun.max")
                    } description: {
                        Text("Turn on Schedule in the quick-add card and pick a day. Tasks dated for today appear here.")
                    }
                    .foregroundStyle(MacAppTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if detailViewMode == .board {
                MacActionItemsBoardsScrollView(columns: [boardColumn], row: { item in macActionRow(item) })
            } else {
                MacActionItemsCenteredScrollList(items: items, row: { macActionRow($0) })
            }
        }
    }

    @ViewBuilder
    private var categoryDetailContent: some View {
        switch route {
        case .dashboard:
            MacUnifiedDashboardView(
                calendarModel: calendarModel,
                snapshot: snapshot,
                actionItems: dashboardActionItems,
                isRefreshing: isRefreshing,
                refreshMessage: refreshMessage
                // onOpenBrief / onOpenStories not available in Action Items tab
            )
        case .planner:
            MacPlannerPlaceholderView()
        case .stickyBoard:
            stickyBoardDetailContent
        case .today:
            todayDetailContent
        case .priorityHome:
            priorityHomeDetailContent
        case .priorityChannel(let boardId):
            singlePriorityColumn(boardId: boardId)
        case .urgencyHome:
            urgencyHomeDetailContent
        case .urgencyChannel(let boardId):
            singleUrgencyColumn(boardId: boardId)
        case .labelsHome:
            labelsHomeDetailContent
        case .labelChannel(let subjectKey):
            singleLabelColumn(subjectKey: subjectKey)
        case .projectsHome:
            projectsHomeDetailContent
        case .projectChannel(let projectKey):
            singleProjectColumn(projectKey: projectKey)
        }
    }

    @ViewBuilder
    private var priorityHomeDetailContent: some View {
        if detailViewMode == .board {
            MacActionItemsBoardsScrollView(
                columns: ActionItemsFeatureModel.boardColumnsForPriority(allItems),
                row: { item in macActionRow(item) }
            )
        } else if allItems.isEmpty {
            MacActionItemsCenteredColumn {
                ContentUnavailableView {
                    Label("No action items", systemImage: "checklist")
                } description: {
                    Text("Add an action item using the form below.")
                }
                .foregroundStyle(MacAppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MacActionItemsCenteredScrollList(
                items: ActionItemsFeatureModel.defaultSorted(allItems),
                row: { macActionRow($0) }
            )
        }
    }

    @ViewBuilder
    private var urgencyHomeDetailContent: some View {
        if detailViewMode == .board {
            MacActionItemsBoardsScrollView(
                columns: ActionItemsFeatureModel.boardColumnsForUrgency(allItems),
                row: { item in macActionRow(item) }
            )
        } else if allItems.isEmpty {
            MacActionItemsCenteredColumn {
                ContentUnavailableView {
                    Label("No action items", systemImage: "checklist")
                } description: {
                    Text("Add an action item using the form below.")
                }
                .foregroundStyle(MacAppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MacActionItemsCenteredScrollList(
                items: ActionItemsFeatureModel.defaultSorted(allItems),
                row: { macActionRow($0) }
            )
        }
    }

    @ViewBuilder
    private var labelsHomeDetailContent: some View {
        if detailViewMode == .board {
            MacActionItemsBoardsScrollView(
                columns: ActionItemsFeatureModel.boardColumnsForLabels(
                    definitions: contextDefinitions,
                    items: allItems
                ),
                isLabelsCategory: true,
                onAccentPreset: { subjectKey, hex in
                    Task { await setContextAccentHex(subjectKey: subjectKey, hex: hex) }
                },
                onAccentCustomRequest: { key in
                    customHexDraft = contextAccentHex(forSubjectKey: key)
                    customHexSubjectKey = key
                },
                row: { item in macActionRow(item) }
            )
        } else if allItems.isEmpty {
            MacActionItemsCenteredColumn {
                ContentUnavailableView {
                    Label("No action items", systemImage: "checklist")
                } description: {
                    Text("Add an action item using the form below.")
                }
                .foregroundStyle(MacAppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MacActionItemsCenteredScrollList(
                items: ActionItemsFeatureModel.defaultSorted(allItems),
                row: { macActionRow($0) }
            )
        }
    }

    @ViewBuilder
    private var projectsHomeDetailContent: some View {
        if detailViewMode == .board {
            MacActionItemsBoardsScrollView(
                columns: ActionItemsFeatureModel.boardColumnsForProjects(
                    definitions: projectDefinitions,
                    items: allItems
                ),
                row: { item in macActionRow(item) }
            )
        } else if allItems.isEmpty {
            MacActionItemsCenteredColumn {
                ContentUnavailableView {
                    Label("No action items", systemImage: "checklist")
                } description: {
                    Text("Add an action item using the form below.")
                }
                .foregroundStyle(MacAppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MacActionItemsCenteredScrollList(
                items: ActionItemsFeatureModel.defaultSorted(allItems),
                row: { macActionRow($0) }
            )
        }
    }

    @ViewBuilder
    private func singlePriorityColumn(boardId: String) -> some View {
        let title = ActionItemsFeatureModel.priorityBoardTitle(forBoardId: boardId)
        let items = ActionItemsFeatureModel.itemsInPriorityChannel(boardId: boardId, items: allItems)
        let col = ActionItemsBoardColumn(boardId: boardId, title: title, items: items)
        if detailViewMode == .board {
            MacActionItemsBoardsScrollView(columns: [col], row: { item in macActionRow(item) })
        } else if items.isEmpty {
            MacActionItemsCenteredColumn {
                ContentUnavailableView {
                    Label("No items", systemImage: "tray")
                } description: {
                    Text("Nothing in this priority bucket yet.")
                }
                .foregroundStyle(MacAppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MacActionItemsCenteredScrollList(items: items, row: { macActionRow($0) })
        }
    }

    @ViewBuilder
    private func singleUrgencyColumn(boardId: String) -> some View {
        let title = ActionItemsFeatureModel.urgencyBoardTitle(forBoardId: boardId)
        let items = ActionItemsFeatureModel.itemsInUrgencyChannel(boardId: boardId, items: allItems)
        let col = ActionItemsBoardColumn(boardId: boardId, title: title, items: items)
        if detailViewMode == .board {
            MacActionItemsBoardsScrollView(columns: [col], row: { item in macActionRow(item) })
        } else if items.isEmpty {
            MacActionItemsCenteredColumn {
                ContentUnavailableView {
                    Label("No items", systemImage: "tray")
                } description: {
                    Text("Nothing in this urgency bucket yet.")
                }
                .foregroundStyle(MacAppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MacActionItemsCenteredScrollList(items: items, row: { macActionRow($0) })
        }
    }

    @ViewBuilder
    private func singleLabelColumn(subjectKey: String) -> some View {
        let title = ActionItemsFeatureModel.displaySubjectHash(subjectKey)
        let items = ActionItemsFeatureModel.itemsInLabelChannel(
            subjectKey: subjectKey,
            definitions: contextDefinitions,
            items: allItems
        )
        let col = ActionItemsBoardColumn(boardId: subjectKey, title: title, items: items)
        if detailViewMode == .board {
            MacActionItemsBoardsScrollView(
                columns: [col],
                isLabelsCategory: true,
                onAccentPreset: { subjectKey, hex in
                    Task { await setContextAccentHex(subjectKey: subjectKey, hex: hex) }
                },
                onAccentCustomRequest: { key in
                    customHexDraft = contextAccentHex(forSubjectKey: key)
                    customHexSubjectKey = key
                },
                row: { item in macActionRow(item) }
            )
        } else if items.isEmpty {
            MacActionItemsCenteredColumn {
                ContentUnavailableView {
                    Label("No items", systemImage: "tray")
                } description: {
                    Text("Nothing with this label yet.")
                }
                .foregroundStyle(MacAppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MacActionItemsCenteredScrollList(items: items, row: { macActionRow($0) })
        }
    }

    @ViewBuilder
    private func singleProjectColumn(projectKey: String) -> some View {
        let title = ActionItemsFeatureModel.displayProjectPath(projectKey)
        let items = ActionItemsFeatureModel.itemsInProjectChannel(
            projectKey: projectKey,
            definitions: projectDefinitions,
            items: allItems
        )
        let col = ActionItemsBoardColumn(boardId: projectKey, title: title, items: items)
        if detailViewMode == .board {
            MacActionItemsBoardsScrollView(columns: [col], row: { item in macActionRow(item) })
        } else if items.isEmpty {
            MacActionItemsCenteredColumn {
                ContentUnavailableView {
                    Label("No items", systemImage: "tray")
                } description: {
                    Text("Nothing in this project yet.")
                }
                .foregroundStyle(MacAppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MacActionItemsCenteredScrollList(items: items, row: { macActionRow($0) })
        }
    }

    private func createLabelFromSheet() async {
        let name = newLabelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let order = (contextDefinitions.map(\.sortOrder).max() ?? 0) + 1
        let def = VaultContextDefinition(name: name, sortOrder: order)
        try? await vaultManager.upsertContextDefinition(def)
        await reloadTagDefinitions()
        await reload()
        showCreateLabelSheet = false
    }

    private func createProjectFromSheet() async {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let order = (projectDefinitions.map(\.sortOrder).max() ?? 0) + 1
        let def = VaultProjectDefinition(name: name, sortOrder: order)
        try? await vaultManager.upsertProjectDefinition(def)
        await reloadTagDefinitions()
        await reload()
        showCreateProjectSheet = false
    }

    private func reloadTagDefinitions() async {
        guard vaultManager.isVaultReady else {
            contextDefinitions = []
            projectDefinitions = []
            typeDefinitions = []
            return
        }
        try? await vaultManager.ensureDefaultContextDefinitions()
        _ = try? await vaultManager.ensureGeneralProjectDefinition()
        contextDefinitions = (try? await vaultManager.listContextDefinitions()) ?? []
        projectDefinitions = (try? await vaultManager.listProjectDefinitions()) ?? []
        typeDefinitions = (try? await vaultManager.listActionTypeDefinitions()) ?? []
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
                    onSave: { saved, isNew in
                        await reload()
                        await reloadTagDefinitions()
                        if isNew {
                            lastAddedItemUndoId = saved.id
                            editorPayload = MacActionItemEditorPayload(item: templateDraftForNewItem(), isNew: true)
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
            } else {
                Button {
                    presentAddSheet()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(MacAppTheme.accent)
                            .symbolRenderingMode(.hierarchical)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add Action Item")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(MacAppTheme.primaryText)
                            Text("Create a task with title, notes, labels, and schedule.")
                                .font(.subheadline)
                                .foregroundStyle(MacAppTheme.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
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
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
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
                    if let ctxLabel = ActionItemsFeatureModel.resolvedContextDisplayName(for: item, definitions: contextDefinitions) {
                        Text(ActionItemsFeatureModel.displaySubjectHash(ctxLabel))
                            .font(.caption2)
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
                    Text(ActionItemsFeatureModel.displayProjectPath(projectName(forProjectId: item.projectId)))
                        .font(.caption2)
                        .foregroundStyle(MacAppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Mark done") {
                Task { await toggleCompletion(for: item) }
            }
            Button("Delete", role: .destructive) {
                Task {
                    try? await vaultManager.deleteActionItem(id: item.id)
                    await reload()
                }
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
            await MainActor.run {
                errorText = error.localizedDescription
            }
            return
        }
        await MainActor.run {
            allItems.removeAll { $0.id == item.id }
            NotificationCenter.default.post(name: .macActionItemsShouldReload, object: nil)
        }
    }

    private func templateDraftForNewItem() -> VaultActionItemRecord {
        switch route {
        case .labelChannel(let key):
            let sk = key == ActionItemsFeatureModel.unspecifiedSubjectKey ? nil : key
            return ActionItemDraftComposer.newDraft(
                selectedSubjectKey: sk,
                selectedProjectKey: nil,
                contextDefinitions: contextDefinitions,
                projectDefinitions: projectDefinitions,
                defaultGeneralProjectWhenNoProjectSelected: true
            )
        case .projectChannel(let key):
            return ActionItemDraftComposer.newDraft(
                selectedSubjectKey: nil,
                selectedProjectKey: key,
                contextDefinitions: contextDefinitions,
                projectDefinitions: projectDefinitions,
                defaultGeneralProjectWhenNoProjectSelected: true
            )
        case .priorityChannel(let boardId):
            var draft = ActionItemDraftComposer.newDraft(
                selectedSubjectKey: nil,
                selectedProjectKey: nil,
                contextDefinitions: contextDefinitions,
                projectDefinitions: projectDefinitions,
                defaultGeneralProjectWhenNoProjectSelected: true
            )
            applyPriorityChannel(boardId, to: &draft)
            return draft
        case .urgencyChannel(let boardId):
            var draft = ActionItemDraftComposer.newDraft(
                selectedSubjectKey: nil,
                selectedProjectKey: nil,
                contextDefinitions: contextDefinitions,
                projectDefinitions: projectDefinitions,
                defaultGeneralProjectWhenNoProjectSelected: true
            )
            applyUrgencyChannel(boardId, to: &draft)
            return draft
        default:
            return ActionItemDraftComposer.newDraft(
                selectedSubjectKey: nil,
                selectedProjectKey: nil,
                contextDefinitions: contextDefinitions,
                projectDefinitions: projectDefinitions,
                defaultGeneralProjectWhenNoProjectSelected: true
            )
        }
    }

    private func applyPriorityChannel(_ boardId: String, to draft: inout VaultActionItemRecord) {
        if boardId == "none" {
            draft.priority = nil
        } else if boardId.hasPrefix("p"), boardId.count > 1,
                  let n = Int(String(boardId.dropFirst())), (0 ... 4).contains(n) {
            draft.priority = n
        }
    }

    private func applyUrgencyChannel(_ boardId: String, to draft: inout VaultActionItemRecord) {
        if boardId == "none" {
            draft.urgency = nil
        } else if boardId.hasPrefix("u"), boardId.count > 1,
                  let n = Int(String(boardId.dropFirst())), (0 ... 4).contains(n) {
            draft.urgency = n
        }
    }

    private func presentAddSheet() {
        lastAddedItemUndoId = nil
        editorPayload = MacActionItemEditorPayload(item: templateDraftForNewItem(), isNew: true)
    }

    private enum LegacySidebarPins {
        static let userDefaultsKey = "MacActionItemsSidebarPins.v1"
    }

    private func migrateLegacySidebarPinsIfNeeded() async {
        guard UserDefaults.standard.data(forKey: LegacySidebarPins.userDefaultsKey) != nil else { return }
        do {
            let current = try await vaultManager.loadStarredSidebarChannels()
            guard current.isEmpty else {
                UserDefaults.standard.removeObject(forKey: LegacySidebarPins.userDefaultsKey)
                return
            }
            guard let data = UserDefaults.standard.data(forKey: LegacySidebarPins.userDefaultsKey),
                  let legacy = try? JSONDecoder().decode([ActionItemsSidebarPin].self, from: data),
                  !legacy.isEmpty
            else {
                UserDefaults.standard.removeObject(forKey: LegacySidebarPins.userDefaultsKey)
                return
            }
            try await vaultManager.saveStarredSidebarChannels(legacy)
            UserDefaults.standard.removeObject(forKey: LegacySidebarPins.userDefaultsKey)
        } catch {}
    }

    private func reloadSidebarPins() async {
        await migrateLegacySidebarPinsIfNeeded()
        do {
            sidebarPins = try await vaultManager.loadStarredSidebarChannels()
        } catch {}
    }

    /// Loads open tasks from disk, then syncs, then reloads again so UI reflects local writes before remote merge.
    private func reload() async {
        errorText = nil
        guard vaultManager.isVaultReady else {
            allItems = []
            return
        }
        await refreshAllItemsFromVault()
        await reloadSidebarPins()
        await vaultManager.performLifecycleSync(postNotification: false)
        await refreshAllItemsFromVault()
        await reloadSidebarPins()
    }

    private func refreshAllItemsFromVault() async {
        do {
            allItems = try await vaultManager.listActionItems()
        } catch {
            errorText = error.localizedDescription
            allItems = []
        }
    }

    private func projectName(forProjectId projectId: String?) -> String {
        guard let projectId else { return ActionItemsFeatureModel.generalProjectName }
        return projectDefinitions.first(where: { $0.id == projectId })?.name ?? ActionItemsFeatureModel.generalProjectName
    }

}

private extension View {
    @ViewBuilder
    func optionalCategoryChannelContextMenu(
        onRename: (() -> Void)?,
        onDelete: (() -> Void)?
    ) -> some View {
        if onRename != nil || onDelete != nil {
            self.contextMenu {
                if let onRename {
                    Button("Rename…") { onRename() }
                }
                if let onDelete {
                    Button("Delete…", role: .destructive) { onDelete() }
                }
            }
        } else {
            self
        }
    }
}

// MARK: - macOS editor payload

private struct MacActionItemEditorPayload: Identifiable, Equatable {
    let id = UUID()
    var item: VaultActionItemRecord
    var isNew: Bool
}
