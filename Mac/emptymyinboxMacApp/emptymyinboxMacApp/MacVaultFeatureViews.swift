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
                        Task { await model.refresh() }
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

private enum MacActionItemsMode: String, CaseIterable, Identifiable {
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

    var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .context: return "square.grid.2x2"
        case .calendar: return "calendar"
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
    @State private var mode: MacActionItemsMode = .today
    @State private var allItems: [VaultActionItemRecord] = []
    @State private var scheduledToday: [VaultActionItemRecord] = []
    @State private var unscheduledToday: [VaultActionItemRecord] = []
    @State private var subjectGroups: [(key: String, items: [VaultActionItemRecord])] = []
    @State private var selectedSubject: String?
    @State private var calendarMonth: Date = Date()
    @State private var calendarByDay: [(day: Date, items: [VaultActionItemRecord])] = []
    @State private var errorText: String?
    @State private var editorPayload: MacActionItemEditorPayload?
    @State private var contextDefinitions: [VaultContextDefinition] = []
    @State private var typeDefinitions: [VaultActionTypeDefinition] = []
    @State private var showTagLibrary = false
    @State private var checklistScale: [String: CGFloat] = [:]

    private let typePresets = ["Action item", "Learning", "Time block", "Meeting", "Event", "Reminder"]

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    ForEach(MacActionItemsMode.allCases) { m in
                        Button {
                            mode = m
                        } label: {
                            Label(m.title, systemImage: m.systemImage)
                        }
                    }
                    Button {
                        Task { await reload() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        showTagLibrary = true
                    } label: {
                        Label("Tags", systemImage: "tag")
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
                VStack(alignment: .leading, spacing: 0) {
                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, MacAppTheme.spacingMedium)
                    }

                    MacActionItemsCenteredColumn {
                        Group {
                            switch mode {
                            case .today:
                                macTodayList
                            case .context:
                                macContextSplit
                            case .calendar:
                                macCalendarList
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(MacAppTheme.primaryBackground)
                .navigationTitle("Action Items")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showTagLibrary = true
                        } label: {
                            Label("Tags", systemImage: "tag")
                        }
                    }
                }
            }
        }
        .background(MacAppTheme.primaryBackground)
        .task {
            await reload()
            await reloadTagDefinitions()
        }
        .onChange(of: mode) { _, _ in Task { await reload() } }
        .onChange(of: calendarMonth) { _, _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .vaultDidSync)) { _ in
            Task {
                await reload()
                await reloadTagDefinitions()
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
    }

    private func reloadTagDefinitions() async {
        contextDefinitions = (try? await vaultManager.listContextDefinitions()) ?? []
        typeDefinitions = (try? await vaultManager.listActionTypeDefinitions()) ?? []
    }

    @ViewBuilder
    private var macTodayList: some View {
        List {
            if !scheduledToday.isEmpty {
                Section("Scheduled") {
                    ForEach(scheduledToday) { item in
                        macActionRow(item)
                    }
                    .onDelete { offsets in deleteFrom(scheduledToday, offsets: offsets) }
                }
            }
            Section("Unscheduled") {
                ForEach(unscheduledToday) { item in
                    macActionRow(item)
                }
                .onDelete { offsets in deleteFrom(unscheduledToday, offsets: offsets) }
            }
            macAddOrEditorSection
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var macAddOrEditorSection: some View {
        Section {
            if let payload = editorPayload {
                ActionItemQuickEntryView(
                    initial: payload.item,
                    isNew: payload.isNew,
                    contexts: contextDefinitions,
                    types: typeDefinitions,
                    typePresets: typePresets,
                    allTasks: allItems,
                    style: .macCard,
                    vaultManager: vaultManager,
                    onSave: {
                        await reload()
                        editorPayload = nil
                    },
                    onCancel: { editorPayload = nil },
                    onManageTags: { showTagLibrary = true }
                )
            } else {
                Button {
                    presentAddSheet()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(MacAppTheme.accent)
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
    private var macContextSplit: some View {
        NavigationSplitView {
            List(selection: $selectedSubject) {
                ForEach(subjectGroups, id: \.key) { group in
                    HStack {
                        Text(group.key)
                            .foregroundStyle(MacAppTheme.primaryText)
                        Spacer()
                        Text("\(group.items.count)")
                            .font(.caption)
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
                    .tag(group.key as String?)
                }
            }
            .scrollContentBackground(.hidden)
        } detail: {
            if let key = selectedSubject, let group = subjectGroups.first(where: { $0.key == key }) {
                List {
                    ForEach(group.items) { item in
                        macActionRow(item)
                    }
                    .onDelete { offsets in deleteFrom(group.items, offsets: offsets) }
                    macAddOrEditorSection
                }
                .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView {
                    Label("Select a context", systemImage: "tray")
                }
            }
        }
    }

    @ViewBuilder
    private var macCalendarList: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(calendarMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .foregroundStyle(MacAppTheme.primaryText)
                Spacer()
                Button {
                    calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.horizontal, MacAppTheme.spacingMedium)
            .padding(.vertical, 8)

            List {
                if calendarByDay.isEmpty {
                    Text("No tasks with dates in this month")
                        .foregroundStyle(MacAppTheme.secondaryText)
                } else {
                    ForEach(calendarByDay, id: \.day.timeIntervalSince1970) { section in
                        Section(section.day.formatted(date: .abbreviated, time: .omitted)) {
                            ForEach(section.items) { item in
                                macActionRow(item)
                            }
                            .onDelete { offsets in deleteFrom(section.items, offsets: offsets) }
                        }
                    }
                }
                macAddOrEditorSection
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func macActionRow(_ item: VaultActionItemRecord) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                Task { await toggleCompletion(for: item) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? MacAppTheme.accent : MacAppTheme.secondaryText)
                    .scaleEffect(checklistScale[item.id] ?? 1)
            }
            .buttonStyle(.plain)

            Button {
                editorPayload = MacActionItemEditorPayload(item: item, isNew: false)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if item.numericId > 0 {
                            Text("#\(item.numericId)")
                                .font(.caption2)
                                .foregroundStyle(MacAppTheme.accent)
                        }
                        Text(item.title)
                            .strikethrough(item.isDone)
                            .foregroundStyle(MacAppTheme.primaryText)
                    }
                    if let p = item.priority {
                        Text("P\(p)")
                            .font(.caption2)
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
                    if let s = item.startDate {
                        Text(s.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
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

    private func presentAddSheet() {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var draft = VaultActionItemRecord(title: "")
        switch mode {
        case .today:
            draft.startDate = todayStart
        case .context:
            if let key = selectedSubject, key != "Uncategorized" {
                draft.subjectLabel = key
            }
        case .calendar:
            if cal.isDate(Date(), equalTo: calendarMonth, toGranularity: .month) {
                draft.startDate = todayStart
            } else if let interval = cal.dateInterval(of: .month, for: calendarMonth) {
                draft.startDate = interval.start
            } else {
                draft.startDate = todayStart
            }
        }
        editorPayload = MacActionItemEditorPayload(item: draft, isNew: true)
    }

    private func reload() async {
        errorText = nil
        await vaultManager.performLifecycleSync(postNotification: false)
        do {
            allItems = try await vaultManager.listActionItems()
            let todayParts = ActionItemsFeatureModel.itemsForTodayList(allItems, referenceDay: Date(), calendar: .current)
            scheduledToday = todayParts.scheduled
            unscheduledToday = todayParts.unscheduled
            subjectGroups = ActionItemsFeatureModel.groupedBySubject(allItems)
            if selectedSubject == nil {
                selectedSubject = subjectGroups.first?.key
            }
            let cal = Calendar.current
            if let interval = cal.dateInterval(of: .month, for: calendarMonth) {
                let monthItems = ActionItemsFeatureModel.itemsIntersectingRange(
                    allItems,
                    rangeStart: interval.start,
                    rangeEnd: interval.end,
                    calendar: cal
                )
                let grouped = Dictionary(grouping: monthItems) { item -> Date in
                    let anchor = item.startDate ?? item.endDate ?? Date()
                    return cal.startOfDay(for: anchor)
                }
                calendarByDay = grouped.keys.sorted().map { day in
                    (day, ActionItemsFeatureModel.defaultSortedForCalendar(grouped[day] ?? []))
                }
            } else {
                calendarByDay = []
            }
        } catch {
            errorText = error.localizedDescription
            allItems = []
            scheduledToday = []
            unscheduledToday = []
            subjectGroups = []
            calendarByDay = []
        }
    }
}

// MARK: - macOS editor payload

private struct MacActionItemEditorPayload: Identifiable {
    let id = UUID()
    var item: VaultActionItemRecord
    var isNew: Bool
}
