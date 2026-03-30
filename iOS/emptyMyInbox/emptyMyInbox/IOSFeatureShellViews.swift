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
        .onReceive(NotificationCenter.default.publisher(for: .companionVaultCalendarActionItemsRefresh)) { _ in
            Task { await calendarModel.refresh() }
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
    @State private var contextDefinitions: [VaultContextDefinition] = []
    @State private var typeDefinitions: [VaultActionTypeDefinition] = []
    @State private var showTagLibrary = false
    @State private var checklistScale: [String: CGFloat] = [:]

    private let typePresets = ["Action item", "Learning", "Time block", "Meeting", "Event", "Reminder"]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AppTheme.primaryBackground
                    .ignoresSafeArea()

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

                    ActionItemsCenteredColumn {
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
            }
            .navigationBarHidden(true)
        }
        .task {
            await reload()
            await reloadTagDefinitions()
        }
        .onChange(of: mode) { _, _ in
            Task { await reload() }
        }
        .onChange(of: calendarMonth) { _, _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaultDidSync)) { _ in
            Task {
                await reload()
                await reloadTagDefinitions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .companionVaultCalendarActionItemsRefresh)) { _ in
            Task {
                await reload()
                await reloadTagDefinitions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountAdded)) { _ in
            Task {
                await reload()
                await reloadTagDefinitions()
            }
        }
        .sheet(item: $editorPayload) { payload in
            NavigationStack {
                ActionItemQuickEntryView(
                    initial: payload.item,
                    isNew: payload.isNew,
                    contexts: contextDefinitions,
                    types: typeDefinitions,
                    typePresets: typePresets,
                    allTasks: allItems,
                    style: .iosSheet,
                    vaultManager: vaultManager,
                    onSave: {
                        await reload()
                        editorPayload = nil
                    },
                    onCancel: { editorPayload = nil },
                    onManageTags: { showTagLibrary = true }
                )
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(payload.isNew ? "New action" : "Edit action")
                            .font(AppTheme.headline)
                            .primaryText()
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

    private func reloadTagDefinitions() async {
        contextDefinitions = (try? await vaultManager.listContextDefinitions()) ?? []
        typeDefinitions = (try? await vaultManager.listActionTypeDefinitions()) ?? []
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
                    showTagLibrary = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tag")
                        Text("Tags")
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
                Task { await toggleCompletion(for: item) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? AppTheme.accent : AppTheme.secondaryText)
                    .scaleEffect(checklistScale[item.id] ?? 1)
            }
            .buttonStyle(.plain)

            Button {
                editorPayload = ActionItemEditorPayload(item: item, isNew: false)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if item.numericId > 0 {
                            Text("#\(item.numericId)")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.accent)
                        }
                        Text(item.title)
                            .font(AppTheme.body)
                            .strikethrough(item.isDone)
                            .primaryText()
                    }
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

// MARK: - Editor payload (iOS)

private struct ActionItemEditorPayload: Identifiable {
    let id = UUID()
    var item: VaultActionItemRecord
    var isNew: Bool
}
