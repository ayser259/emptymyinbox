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
    /// Second parameter is `true` when this save created a new item (vs editing existing).
    let onSave: (VaultActionItemRecord, Bool) async -> Void
    let onCancel: () -> Void
    let onManageTags: (() -> Void)?

    @State private var hasStart: Bool
    @FocusState private var focusedField: Field?
    @State private var hashHighlightedIndex: Int = 0

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
        onSave: @escaping (VaultActionItemRecord, Bool) async -> Void,
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
        .onChange(of: draft.title) { _, _ in
            if !hashFilteredContexts.isEmpty {
                hashHighlightedIndex = min(max(0, hashHighlightedIndex), hashFilteredContexts.count - 1)
            } else {
                hashHighlightedIndex = 0
            }
        }
    }

    private var macCardBody: some View {
        VStack(alignment: .leading, spacing: SharedAppTheme.spacingMedium) {
            titleBlock
            inlineHashChips
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
        .modifier(HashKeyPressModifier(
            isActive: hashMenuOpen,
            count: hashFilteredContexts.count,
            highlightedIndex: $hashHighlightedIndex
        ))
    }

    private var iosSheetBody: some View {
        VStack(alignment: .leading, spacing: SharedAppTheme.spacingMedium) {
            titleBlock
            inlineHashChips
            chipRows
            footerRow
        }
        .padding(SharedAppTheme.spacingMedium)
        .background(SharedAppTheme.secondaryBackground)
        .modifier(HashKeyPressModifier(
            isActive: hashMenuOpen,
            count: hashFilteredContexts.count,
            highlightedIndex: $hashHighlightedIndex
        ))
    }

    private var hashMenuOpen: Bool {
        ActionItemTitleParsing.activeHashSuffix(in: draft.title) != nil && !hashFilteredContexts.isEmpty
    }

    private var hashFilteredContexts: [VaultContextDefinition] {
        guard let (_, q) = ActionItemTitleParsing.activeHashSuffix(in: draft.title) else { return [] }
        let sorted = sortedContexts
        if q.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextField("Action Name", text: $draft.title)
                    .font(SharedAppTheme.title3)
                    .foregroundStyle(SharedAppTheme.primaryText)
                    .focused($focusedField, equals: .title)
                    .lineLimit(1 ... 4)
                    .onSubmit {
                        Task { await submitDraft() }
                    }

                if hashMenuOpen {
                    hashSuggestionOverlay
                        .padding(.top, 36)
                }
            }

            TextField("Description", text: Binding(
                get: { draft.taskDescription ?? "" },
                set: { draft.taskDescription = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .font(SharedAppTheme.subheadline)
            .foregroundStyle(SharedAppTheme.secondaryText)
            .focused($focusedField, equals: .description)
        }
    }

    private var hashSuggestionOverlay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(hashFilteredContexts.enumerated()), id: \.element.id) { idx, c in
                    Button {
                        draft.title = ActionItemTitleParsing.applyHashSelection(title: draft.title, contextName: c.name)
                        hashHighlightedIndex = 0
                    } label: {
                        HStack(spacing: 8) {
                            Text("#")
                                .foregroundStyle(Color(hex: c.accentColorHex ?? ContextAccentPalette.defaultGreyHex))
                            Text(c.name)
                                .foregroundStyle(SharedAppTheme.primaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(idx == hashHighlightedIndex ? Color.white.opacity(0.12) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusSmall)
                .fill(SharedAppTheme.secondaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusSmall)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    private var inlineHashChips: some View {
        let tags = ActionItemTitleParsing.hashTagNames(in: draft.title)
        guard !tags.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        let hex = contexts.first(where: { $0.name.caseInsensitiveCompare(tag) == .orderedSame })?.accentColorHex
                            ?? ContextAccentPalette.defaultGreyHex
                        Text("#" + tag)
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.primaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(hex: hex).opacity(0.35))
                            )
                    }
                }
            }
        )
    }

    private var chipRows: some View {
        chipScrollRow {
            priorityChip
            todayChip
            labelsChip
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
            ForEach(0 ... 4, id: \.self) { p in
                Button("Priority \(p)") { draft.priority = p }
            }
        } label: {
            chipLabel(
                icon: "flag",
                text: draft.priority.map { "P\($0)" } ?? "Priority",
                accent: false,
                tint: draft.priority.map { ActionItemPriorityColors.color(forStoredPriority: $0) }
            )
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
                Button("Manage labels…") { onManageTags() }
            }
        } label: {
            chipLabel(
                icon: "tag",
                text: ActionItemsFeatureModel.displaySubjectHash(draft.subjectLabel),
                accent: draft.contextId != nil
            )
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(icon: String, text: String, accent: Bool, tint: Color? = nil) -> some View {
        let fg = tint ?? (accent ? Color.green : SharedAppTheme.secondaryText)
        let border = tint ?? Color.white.opacity(0.2)
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(SharedAppTheme.caption)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .stroke(border, lineWidth: 1)
        )
    }

    private var sortedContexts: [VaultContextDefinition] {
        contexts.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var canSaveDraft: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var footerRow: some View {
        VStack(spacing: 12) {
            Divider().opacity(0.3)
            HStack {
                Menu {
                    Button(ActionItemsFeatureModel.unspecifiedSubjectKey) {
                        draft.contextId = nil
                        draft.subjectLabel = nil
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
                        Text(ActionItemsFeatureModel.displaySubjectHash(draft.subjectLabel))
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
                    Task { await submitDraft() }
                }
                .buttonStyle(.borderedProminent)
                .tint(SharedAppTheme.accent)
                .disabled(!canSaveDraft)
                .opacity(canSaveDraft ? 1 : 0.45)
            }
        }
    }

    private func submitDraft() async {
        guard canSaveDraft else { return }
        if hashMenuOpen {
            let i = min(max(0, hashHighlightedIndex), hashFilteredContexts.count - 1)
            let c = hashFilteredContexts[i]
            draft.title = ActionItemTitleParsing.applyHashSelection(title: draft.title, contextName: c.name)
            return
        }
        await persist()
    }

    private func persist() async {
        if !hasStart { draft.startDate = nil }

        let parsed = ActionItemTitleParsing.parseShortcuts(from: draft.title)
        var toSave = draft
        toSave.title = parsed.cleanedTitle
        toSave.priority = parsed.priority ?? draft.priority

        if let ctxName = parsed.contextName {
            let trimmed = ctxName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let existing = contexts.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                    toSave.contextId = existing.id
                    toSave.subjectLabel = existing.name
                } else {
                    let order = sortedContexts.map(\.sortOrder).max() ?? 0
                    let newDef = VaultContextDefinition(
                        name: trimmed,
                        accentColorHex: ContextAccentPalette.defaultGreyHex,
                        sortOrder: order + 1
                    )
                    do {
                        try await vaultManager.upsertContextDefinition(newDef)
                        toSave.contextId = newDef.id
                        toSave.subjectLabel = trimmed
                    } catch {
                        return
                    }
                }
            }
        }

        do {
            try await vaultManager.upsertActionItem(toSave)
            await onSave(toSave, isNew)
        } catch {}
    }
}

// MARK: - macOS arrow keys for hash menu

private struct HashKeyPressModifier: ViewModifier {
    let isActive: Bool
    let count: Int
    @Binding var highlightedIndex: Int

    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.upArrow) {
                    guard isActive, count > 0 else { return .ignored }
                    highlightedIndex = max(0, highlightedIndex - 1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard isActive, count > 0 else { return .ignored }
                    highlightedIndex = min(count - 1, highlightedIndex + 1)
                    return .handled
                }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
