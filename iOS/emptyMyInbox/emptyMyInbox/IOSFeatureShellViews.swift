//
//  IOSFeatureShellViews.swift
//  emptyMyInbox
//
//  Shared top chrome and Calendar / Action Items tabs (vault-backed).
//

import SwiftUI
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

    @StateObject private var calendarModel = GoogleCalendarViewModel()
    @State private var showVisibility = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    MainAppTopBar(center: {
                        Text("Calendar")
                            .font(AppTheme.headline)
                            .primaryText()
                    }, onMenuTap: onMenuTap)

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
    }

    private var calendarModeCarousel: some View {
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
                    Task { await calendarModel.refresh() }
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
            .padding(.horizontal, AppTheme.spacingMedium)
            .padding(.vertical, AppTheme.spacingSmall)
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

struct ActionItemsSkeletonView: View {
    var onMenuTap: () -> Void

    @ObservedObject private var vaultManager = VaultManager.shared
    @State private var mode: ActionItemsChromeMode = .today
    @State private var allItems: [VaultActionItemRecord] = []
    @State private var scheduledToday: [VaultActionItemRecord] = []
    @State private var unscheduledToday: [VaultActionItemRecord] = []
    @State private var subjectGroups: [(key: String, items: [VaultActionItemRecord])] = []
    @State private var selectedSubject: String?
    @State private var calendarMonth: Date = Date()
    @State private var calendarByDay: [(day: Date, items: [VaultActionItemRecord])] = []
    @State private var errorText: String?
    @State private var editorPayload: ActionItemEditorPayload?

    private let typePresets = ["Action item", "Learning", "Time block", "Meeting", "Event", "Reminder"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()

                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        MainAppTopBar(center: {
                            Text("Action Items")
                                .font(AppTheme.headline)
                                .primaryText()
                        }, onMenuTap: onMenuTap)

                        actionItemsModeCarousel

                        if let errorText {
                            Text(errorText)
                                .font(AppTheme.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal)
                        }

                        Group {
                            switch mode {
                            case .today:
                                todayContent
                            case .context:
                                contextContent
                            case .calendar:
                                calendarContent
                            }
                        }
                    }

                    Button {
                        presentAddSheet()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding(.trailing, AppTheme.spacingMedium)
                    .padding(.top, AppTheme.spacingSmall)
                }
            }
            .navigationBarHidden(true)
        }
        .task { await reload() }
        .onChange(of: mode) { _, _ in
            Task { await reload() }
        }
        .onChange(of: calendarMonth) { _, _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaultDidSync)) { _ in
            Task { await reload() }
        }
        .sheet(item: $editorPayload) { payload in
            NavigationStack {
                ActionItemIOSFormView(
                    initial: payload.item,
                    isNew: payload.isNew,
                    allTasks: allItems,
                    typePresets: typePresets,
                    vaultManager: vaultManager,
                    onSave: {
                        await reload()
                        editorPayload = nil
                    },
                    onCancel: { editorPayload = nil }
                )
            }
            .presentationDetents([.large])
        }
    }

    private var actionItemsModeCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacingMedium) {
                ForEach(ActionItemsChromeMode.allCases) { m in
                    Button {
                        mode = m
                    } label: {
                        Text(m.title)
                            .font(AppTheme.subheadline)
                            .foregroundColor(mode == m ? AppTheme.primaryText : AppTheme.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .fill(mode == m ? AppTheme.secondaryBackground : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .stroke(AppTheme.accent.opacity(mode == m ? 0.5 : 0.15), lineWidth: 1)
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
            }
            .padding(.horizontal, AppTheme.spacingMedium)
            .padding(.bottom, AppTheme.spacingSmall)
        }
    }

    // MARK: - Today

    @ViewBuilder
    private var todayContent: some View {
        List {
            if !scheduledToday.isEmpty {
                Section("Scheduled") {
                    ForEach(scheduledToday) { item in
                        actionRow(item)
                    }
                    .onDelete { offsets in deleteFrom(scheduledToday, offsets: offsets) }
                }
            }
            Section("Unscheduled") {
                ForEach(unscheduledToday) { item in
                    actionRow(item)
                }
                .onDelete { offsets in deleteFrom(unscheduledToday, offsets: offsets) }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
    }

    // MARK: - Context (sidebar channels)

    @ViewBuilder
    private var contextContent: some View {
        NavigationSplitView {
            List(selection: $selectedSubject) {
                ForEach(subjectGroups, id: \.key) { group in
                    HStack {
                        Text(group.key)
                            .primaryText()
                        Spacer()
                        Text("\(group.items.count)")
                            .font(AppTheme.caption)
                            .secondaryText()
                    }
                    .tag(group.key as String?)
                    .listRowBackground(AppTheme.secondaryBackground.opacity(0.35))
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Contexts")
        } detail: {
            if let key = selectedSubject, let group = subjectGroups.first(where: { $0.key == key }) {
                List {
                    ForEach(group.items) { item in
                        actionRow(item)
                    }
                    .onDelete { offsets in deleteFrom(group.items, offsets: offsets) }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle(key)
            } else {
                ContentUnavailableView {
                    Label("Select a context", systemImage: "tray")
                }
            }
        }
    }

    // MARK: - Calendar (month sections by day)

    @ViewBuilder
    private var calendarContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(calendarMonth.formatted(.dateTime.month(.wide).year()))
                    .font(AppTheme.headline)
                    .primaryText()
                Spacer()
                Button {
                    calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.horizontal, AppTheme.spacingMedium)
            .padding(.vertical, AppTheme.spacingSmall)

            List {
                if calendarByDay.isEmpty {
                    Section {
                        Text("No tasks with dates in this month")
                            .font(AppTheme.caption)
                            .secondaryText()
                    }
                } else {
                    ForEach(calendarByDay, id: \.day.timeIntervalSince1970) { section in
                        Section(section.day.formatted(date: .abbreviated, time: .omitted)) {
                            ForEach(section.items) { item in
                                actionRow(item)
                            }
                            .onDelete { offsets in deleteFrom(section.items, offsets: offsets) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func actionRow(_ item: VaultActionItemRecord) -> some View {
        HStack(alignment: .center, spacing: AppTheme.spacingMedium) {
            Button {
                Task {
                    try? await vaultManager.updateActionItemCompletion(id: item.id, isDone: !item.isDone)
                    await reload()
                }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? AppTheme.accent : AppTheme.secondaryText)
            }
            .buttonStyle(.plain)

            Button {
                editorPayload = ActionItemEditorPayload(item: item, isNew: false)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(AppTheme.body)
                        .strikethrough(item.isDone)
                        .primaryText()
                    if let p = item.priority {
                        Text("P\(p)")
                            .font(.caption2)
                            .secondaryText()
                    }
                    if let s = item.startDate {
                        Text(s.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .secondaryText()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(AppTheme.secondaryBackground.opacity(0.35))
        .contextMenu {
            Button(item.isDone ? "Mark incomplete" : "Mark done") {
                Task {
                    try? await vaultManager.updateActionItemCompletion(id: item.id, isDone: !item.isDone)
                    await reload()
                }
            }
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
        editorPayload = ActionItemEditorPayload(item: draft, isNew: true)
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

// MARK: - Editor payload + form (iOS)

private struct ActionItemEditorPayload: Identifiable {
    let id = UUID()
    var item: VaultActionItemRecord
    var isNew: Bool
}

private struct ActionItemIOSFormView: View {
    @State private var item: VaultActionItemRecord
    let isNew: Bool
    let allTasks: [VaultActionItemRecord]
    let typePresets: [String]
    let vaultManager: VaultManager
    let onSave: () async -> Void
    let onCancel: () -> Void

    @State private var hasStart = false
    @State private var hasEnd = false
    @State private var newComment = ""
    @State private var subtaskTitle = ""
    @State private var parentSelection: String = ""

    init(
        initial: VaultActionItemRecord,
        isNew: Bool,
        allTasks: [VaultActionItemRecord],
        typePresets: [String],
        vaultManager: VaultManager,
        onSave: @escaping () async -> Void,
        onCancel: @escaping () -> Void
    ) {
        _item = State(initialValue: initial)
        self.isNew = isNew
        self.allTasks = allTasks
        self.typePresets = typePresets
        self.vaultManager = vaultManager
        self.onSave = onSave
        self.onCancel = onCancel
        _hasStart = State(initialValue: initial.startDate != nil)
        _hasEnd = State(initialValue: initial.endDate != nil)
        _parentSelection = State(initialValue: initial.parentTaskId ?? "")
    }

    var body: some View {
        Form {
            Section("Task") {
                TextField("Title", text: $item.title)
                Toggle("Done", isOn: Binding(
                    get: { item.isDone },
                    set: { newVal in
                        item.isDone = newVal
                        item.completedAt = newVal ? (item.completedAt ?? Date()) : nil
                    }
                ))
            }

            Section("Schedule") {
                Toggle("Start", isOn: $hasStart)
                if hasStart {
                    DatePicker("Starts", selection: Binding(
                        get: { item.startDate ?? Date() },
                        set: { item.startDate = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                }
                Toggle("End", isOn: $hasEnd)
                if hasEnd {
                    DatePicker("Ends", selection: Binding(
                        get: { item.endDate ?? Date() },
                        set: { item.endDate = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                }
            }

            Section("Labels") {
                TextField("Context / subject", text: Binding(
                    get: { item.subjectLabel ?? "" },
                    set: { item.subjectLabel = $0.isEmpty ? nil : $0 }
                ))
                Picker("Type", selection: Binding(
                    get: { item.typeLabel ?? "" },
                    set: { item.typeLabel = $0.isEmpty ? nil : $0 }
                )) {
                    Text("None").tag("")
                    ForEach(typePresets, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                Picker("Priority", selection: Binding(
                    get: { item.priority.map { String($0) } ?? "" },
                    set: { s in
                        if s.isEmpty { item.priority = nil }
                        else { item.priority = Int(s).map { min(3, max(0, $0)) } }
                    }
                )) {
                    Text("None").tag("")
                    Text("0").tag("0")
                    Text("1").tag("1")
                    Text("2").tag("2")
                    Text("3 (highest)").tag("3")
                }
            }

            Section("Documentation") {
                TextField("Notes", text: Binding(
                    get: { item.notes ?? "" },
                    set: { item.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                TextField("Description", text: Binding(
                    get: { item.taskDescription ?? "" },
                    set: { item.taskDescription = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                TextField("Context notes / tags", text: Binding(
                    get: { item.contextNotes ?? "" },
                    set: { item.contextNotes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
            }

            Section("Parent task") {
                Picker("Parent (optional link)", selection: $parentSelection) {
                    Text("None").tag("")
                    ForEach(allTasks.filter { $0.id != item.id }) { t in
                        Text(t.title).tag(t.id)
                    }
                }
            }

            Section("Comments") {
                ForEach(item.comments, id: \.id) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.text)
                            .font(AppTheme.body)
                            .primaryText()
                        Text(c.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .secondaryText()
                    }
                }
                TextField("New comment", text: $newComment, axis: .vertical)
                Button("Add comment") {
                    let t = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    item.comments.append(VaultActionItemCommentRecord(text: t))
                    newComment = ""
                }
            }

            if !isNew {
                Section("Subtasks") {
                    TextField("New subtask title", text: $subtaskTitle)
                    Button("Create subtask (snapshot labels)") {
                        let t = subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        Task {
                            try? await vaultManager.createChildTask(fromParentId: item.id, title: t)
                            subtaskTitle = ""
                            await onSave()
                        }
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New task" : "Edit task")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await persist()
                    }
                }
            }
        }
    }

    private func persist() async {
        if !hasStart { item.startDate = nil }
        if !hasEnd { item.endDate = nil }
        item.parentTaskId = parentSelection.isEmpty ? nil : parentSelection
        do {
            try await vaultManager.upsertActionItem(item)
            await onSave()
        } catch {
            // Best-effort; vault manager logs elsewhere
        }
    }
}
