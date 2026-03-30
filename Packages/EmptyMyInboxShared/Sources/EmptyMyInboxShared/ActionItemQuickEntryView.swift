//
//  ActionItemQuickEntryView.swift
//  EmptyMyInboxShared
//

import SwiftUI

public enum ActionItemQuickEntryStyle: Sendable {
    case macCard
    case iosSheet
}

/// Quick-add / quick-edit UI for action items (matches iOS + Mac reference layouts).
public struct ActionItemQuickEntryView: View {
    @State private var draft: VaultActionItemRecord
    let isNew: Bool
    let contexts: [VaultContextDefinition]
    let types: [VaultActionTypeDefinition]
    let typePresets: [String]
    let allTasks: [VaultActionItemRecord]
    let style: ActionItemQuickEntryStyle
    let vaultManager: VaultManager
    let onSave: () async -> Void
    let onCancel: () -> Void
    let onManageTags: (() -> Void)?

    @State private var hasStart: Bool
    @State private var hasEnd: Bool
    @State private var newComment = ""
    @State private var subtaskTitle = ""
    @State private var parentSelection: String = ""
    @State private var showMore = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case title, description }

    public init(
        initial: VaultActionItemRecord,
        isNew: Bool,
        contexts: [VaultContextDefinition],
        types: [VaultActionTypeDefinition],
        typePresets: [String],
        allTasks: [VaultActionItemRecord],
        style: ActionItemQuickEntryStyle,
        vaultManager: VaultManager,
        onSave: @escaping () async -> Void,
        onCancel: @escaping () -> Void,
        onManageTags: (() -> Void)? = nil
    ) {
        _draft = State(initialValue: initial)
        self.isNew = isNew
        self.contexts = contexts
        self.types = types
        self.typePresets = typePresets
        self.allTasks = allTasks
        self.style = style
        self.vaultManager = vaultManager
        self.onSave = onSave
        self.onCancel = onCancel
        self.onManageTags = onManageTags
        _hasStart = State(initialValue: initial.startDate != nil)
        _hasEnd = State(initialValue: initial.endDate != nil)
        _parentSelection = State(initialValue: initial.parentTaskId ?? "")
    }

    public var body: some View {
        Group {
            switch style {
            case .macCard:
                macCardBody
            case .iosSheet:
                iosSheetBody
                    .background(SharedAppTheme.primaryBackground)
            }
        }
        .onAppear {
            if style == .iosSheet {
                focusedField = .title
            }
        }
        .sheet(isPresented: $showMore) {
            NavigationStack {
                moreForm
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var macCardBody: some View {
        VStack(alignment: .leading, spacing: SharedAppTheme.spacingMedium) {
            headerRow
            titleBlock
            chipRows
            footerRow
        }
        .padding(SharedAppTheme.spacingMedium)
        .background(
            RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusLarge)
                .fill(SharedAppTheme.secondaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusLarge)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var iosSheetBody: some View {
        VStack(alignment: .leading, spacing: SharedAppTheme.spacingMedium) {
            headerRow
            titleBlock
            chipRows
            iosAccessoryRow
            footerRow
        }
        .padding(SharedAppTheme.spacingMedium)
        .background(SharedAppTheme.secondaryBackground)
    }

    private var headerRow: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button {
                    showMore = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(SharedAppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                Image(systemName: "waveform")
                    .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.5))
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Action Name", text: $draft.title, axis: .vertical)
                .font(SharedAppTheme.title3)
                .foregroundStyle(SharedAppTheme.primaryText)
                .focused($focusedField, equals: .title)
            TextField("Description", text: Binding(
                get: { draft.taskDescription ?? "" },
                set: { draft.taskDescription = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .font(SharedAppTheme.subheadline)
            .foregroundStyle(SharedAppTheme.secondaryText)
            .focused($focusedField, equals: .description)
        }
    }

    private var chipRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            chipScrollRow {
                priorityChip
                todayChip
                labelsChip
                remindersStubChip
                deadlineChip
            }
            chipScrollRow {
                attachmentStubChip
                moreChip
            }
        }
    }

    private func chipScrollRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
        }
    }

    private var priorityChip: some View {
        Menu {
            Button("None") { draft.priority = nil }
            ForEach(0 ... 3, id: \.self) { p in
                Button("Priority \(p)") { draft.priority = p }
            }
        } label: {
            chipLabel(icon: "flag", text: draft.priority.map { "P\($0)" } ?? "Priority", accent: false)
        }
        .buttonStyle(.plain)
    }

    private var todayChip: some View {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let isToday = draft.startDate.map { cal.isDate($0, inSameDayAs: Date()) } ?? false
        return Button {
            if isToday {
                draft.startDate = nil
                hasStart = false
            } else {
                draft.startDate = todayStart
                hasStart = true
            }
        } label: {
            chipLabel(icon: "calendar", text: "Today", accent: isToday)
        }
        .buttonStyle(.plain)
    }

    private var labelsChip: some View {
        Menu {
            Button("None") {
                draft.contextId = nil
                draft.subjectLabel = nil
            }
            ForEach(sortedContexts) { c in
                Button(c.name) {
                    draft.contextId = c.id
                    draft.subjectLabel = c.name
                }
            }
            if let onManageTags {
                Divider()
                Button("Manage contexts…") { onManageTags() }
            }
        } label: {
            chipLabel(icon: "tag", text: draft.subjectLabel ?? "Labels", accent: draft.contextId != nil)
        }
        .buttonStyle(.plain)
    }

    private var remindersStubChip: some View {
        chipLabel(icon: "alarm", text: "Reminders", accent: false)
            .opacity(0.45)
    }

    private var deadlineChip: some View {
        Menu {
            Button("No deadline") {
                draft.endDate = nil
                hasEnd = false
            }
            Button("In one hour") {
                hasEnd = true
                draft.endDate = Date().addingTimeInterval(3600)
            }
            Button("End of day") {
                hasEnd = true
                draft.endDate = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date()) ?? Date()
            }
        } label: {
            chipLabel(icon: "scope", text: draft.endDate == nil ? "Deadline" : "Due", accent: draft.endDate != nil)
        }
        .buttonStyle(.plain)
    }

    private var attachmentStubChip: some View {
        chipLabel(icon: "paperclip", text: "Attachment", accent: false)
            .opacity(0.45)
    }

    private var moreChip: some View {
        Button {
            showMore = true
        } label: {
            chipLabel(icon: "ellipsis", text: "More", accent: false)
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(icon: String, text: String, accent: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(SharedAppTheme.caption)
        }
        .foregroundStyle(accent ? Color.green : SharedAppTheme.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var sortedContexts: [VaultContextDefinition] {
        contexts.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var sortedTypes: [VaultActionTypeDefinition] {
        types.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var canSaveDraft: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var iosAccessoryRow: some View {
        HStack {
            Menu {
                Button("Inbox (uncategorized)") {
                    draft.contextId = nil
                    draft.subjectLabel = "Inbox"
                }
                ForEach(sortedContexts) { c in
                    Button(c.name) {
                        draft.contextId = c.id
                        draft.subjectLabel = c.name
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.fill")
                    Text(draft.subjectLabel ?? "Inbox")
                        .font(SharedAppTheme.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(SharedAppTheme.secondaryText)
            }
            Spacer()
            Circle()
                .fill(Color(red: 0.89, green: 0.36, blue: 0.36))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "waveform")
                        .foregroundStyle(.white)
                }
                .opacity(0.35)
        }
    }

    private var footerRow: some View {
        VStack(spacing: 12) {
            Divider().opacity(0.3)
            HStack {
                Menu {
                    Button("Inbox (uncategorized)") {
                        draft.contextId = nil
                        draft.subjectLabel = "Inbox"
                    }
                    ForEach(sortedContexts) { c in
                        Button(c.name) {
                            draft.contextId = c.id
                            draft.subjectLabel = c.name
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.fill")
                        Text(draft.subjectLabel ?? "Inbox")
                            .font(SharedAppTheme.subheadline)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(SharedAppTheme.primaryText)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                Button(isNew ? "Add Action" : "Save") {
                    Task { await persist() }
                }
                .buttonStyle(.borderedProminent)
                .tint(SharedAppTheme.accent)
                .disabled(!canSaveDraft)
                .opacity(canSaveDraft ? 1 : 0.45)
            }
        }
    }

    private var moreForm: some View {
        Form {
            Section("Type") {
                Menu {
                    Button("None") {
                        draft.typeId = nil
                        draft.typeLabel = nil
                    }
                    ForEach(sortedTypes) { t in
                        Button(t.name) {
                            draft.typeId = t.id
                            draft.typeLabel = t.name
                        }
                    }
                    Divider()
                    ForEach(typePresets, id: \.self) { p in
                        Button(p) {
                            draft.typeId = nil
                            draft.typeLabel = p
                        }
                    }
                } label: {
                    HStack {
                        Text("Work type")
                        Spacer()
                        Text(draft.typeLabel ?? "None")
                            .foregroundStyle(SharedAppTheme.secondaryText)
                    }
                }
            }
            Section("Schedule") {
                Toggle("Start", isOn: $hasStart)
                if hasStart {
                    DatePicker("Starts", selection: Binding(
                        get: { draft.startDate ?? Date() },
                        set: { draft.startDate = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                }
                Toggle("End", isOn: $hasEnd)
                if hasEnd {
                    DatePicker("Ends", selection: Binding(
                        get: { draft.endDate ?? Date() },
                        set: { draft.endDate = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                }
            }
            Section("Parent task") {
                Picker("Parent", selection: $parentSelection) {
                    Text("None").tag("")
                    ForEach(allTasks.filter { $0.id != draft.id }) { t in
                        Text(t.title).tag(t.id)
                    }
                }
            }
            Section("Comments") {
                ForEach(draft.comments, id: \.id) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.text)
                            .font(SharedAppTheme.body)
                        Text(c.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                    }
                }
                TextField("New comment", text: $newComment, axis: .vertical)
                Button("Add comment") {
                    let t = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    draft.comments.append(VaultActionItemCommentRecord(text: t))
                    newComment = ""
                }
            }
            if !isNew {
                Section("Subtasks") {
                    TextField("New subtask title", text: $subtaskTitle)
                    Button("Create subtask") {
                        let t = subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        Task {
                            _ = try? await vaultManager.createChildTask(fromParentId: draft.id, title: t)
                            subtaskTitle = ""
                            await onSave()
                        }
                    }
                }
            }
        }
        .navigationTitle("More")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showMore = false }
            }
        }
    }

    private func persist() async {
        if !hasStart { draft.startDate = nil }
        if !hasEnd { draft.endDate = nil }
        draft.parentTaskId = parentSelection.isEmpty ? nil : parentSelection
        do {
            try await vaultManager.upsertActionItem(draft)
            await onSave()
        } catch {}
    }
}
