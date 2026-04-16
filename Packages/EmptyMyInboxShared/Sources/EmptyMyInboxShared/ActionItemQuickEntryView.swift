//
//  ActionItemQuickEntryView.swift
//  EmptyMyInboxShared
//

import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#endif

public enum ActionItemQuickEntryStyle: Sendable {
    case macCard
    case iosSheet
}

/// Asset names in the macOS app catalog (`MacActionItemsCategorySidebarAsset`); used for chip icons to match the sidebar.
private enum ActionItemsQuickEntryChipMacAsset {
    static let priority = "ActionItemsCategoryPriority"
    static let urgency = "ActionItemsCategoryUrgency"
    static let labels = "ActionItemsCategoryLabels"
    static let projects = "ActionItemsCategoryProjects"
}

/// Quick-add / quick-edit UI for action items (matches iOS + Mac reference layouts).
public struct ActionItemQuickEntryView: View {
    @State private var draft: VaultActionItemRecord
    let isNew: Bool
    let contexts: [VaultContextDefinition]
    let projects: [VaultProjectDefinition]
    let types: [VaultActionTypeDefinition]
    let typePresets: [String]
    let allTasks: [VaultActionItemRecord]
    let style: ActionItemQuickEntryStyle
    let vaultManager: VaultManager
    /// Second parameter is `true` when this save created a new item (vs editing existing).
    let onSave: (VaultActionItemRecord, Bool) async -> Void
    let onCancel: () -> Void
    let onManageTags: (() -> Void)?

    @FocusState private var focusedField: Field?
    @State private var hashHighlightedIndex: Int = 0
    @State private var projectHighlightedIndex: Int = 0
    /// Whether context/priority/urgency/project last changed via title tokens (`.title`) or chips/menus (`.menu`). Used for conflict resolution on save.
    @State private var lastShortcutEditSource: ShortcutEditSource = .title

    private enum ShortcutEditSource: Hashable { case title, menu }

    private enum Field: Hashable { case title, description, priority, urgency, context, project, submit }

    /// Larger chrome for the macOS card quick-add (`.macCard`); iOS always `false`.
    private var isMacProminentQuickEntry: Bool {
        #if os(macOS)
        return style == .macCard
        #else
        return false
        #endif
    }

    private var hashSuggestionTopInset: CGFloat {
        isMacProminentQuickEntry ? 58 : 36
    }

    private func markMenuEdit() {
        lastShortcutEditSource = .menu
    }

    /// Parsed shortcuts from the current title (same as save). Chips read from this + `draft` so labels update live like `@` tags.
    private var shortcutsPreview: ActionItemTitleParsing.ParsedShortcuts {
        ActionItemTitleParsing.parseShortcuts(from: draft.title)
    }

    private var displayedPriority: Int? {
        shortcutsPreview.priority ?? draft.priority
    }

    private var displayedUrgency: Int? {
        shortcutsPreview.urgency ?? draft.urgency
    }

    /// Same resolution as list/board subtitles: `@` in title → menu/contextId → freeform `subjectLabel`.
    private var resolvedContextNameForChip: String? {
        if let name = shortcutsPreview.contextName, !name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            return name
        }
        return ActionItemsFeatureModel.resolvedContextDisplayName(for: draft, definitions: contexts)
    }

    /// Label text for the context chip: last `@tag` in the title wins over menu selection when present.
    private var displayedContextChipText: String {
        ActionItemsFeatureModel.displaySubjectHash(resolvedContextNameForChip)
    }

    private var displayedContextChipAccent: Bool {
        shortcutsPreview.contextName != nil
            || draft.contextId != nil
            || (draft.subjectLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    /// Project shown on the chip: `#path` in the title overrides the menu when present.
    private var displayedProjectNameForChip: String? {
        if let fromTitle = shortcutsPreview.projectName, !fromTitle.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            return fromTitle
        }
        return projectNameForCurrentDraft
    }

    public init(
        initial: VaultActionItemRecord,
        isNew: Bool,
        contexts: [VaultContextDefinition],
        projects: [VaultProjectDefinition],
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
        self.projects = projects
        self.types = types
        self.typePresets = typePresets
        self.allTasks = allTasks
        self.style = style
        self.vaultManager = vaultManager
        self.onSave = onSave
        self.onCancel = onCancel
        self.onManageTags = onManageTags
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
            focusedField = .title
        }
        .onChange(of: draft.title) { _, _ in
            if hashRowCount > 0 {
                hashHighlightedIndex = min(max(0, hashHighlightedIndex), hashRowCount - 1)
            } else {
                hashHighlightedIndex = 0
            }
            if !projectFilteredDefinitions.isEmpty {
                projectHighlightedIndex = min(max(0, projectHighlightedIndex), projectFilteredDefinitions.count - 1)
            } else {
                projectHighlightedIndex = 0
            }
        }
#if os(macOS)
        .onMoveCommand(perform: handleMoveCommand)
#endif
    }

    private var macCardBody: some View {
        VStack(alignment: .leading, spacing: isMacProminentQuickEntry ? 20 : SharedAppTheme.spacingMedium) {
            if isMacProminentQuickEntry {
                macQuickEntryHeader
            }
            titleBlock
            inlineHashChips
            chipRows
            scheduleRow
            footerRow
        }
        .padding(isMacProminentQuickEntry ? 24 : SharedAppTheme.spacingMedium)
        .background(
            Group {
                if isMacProminentQuickEntry {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#1e1e1e"),
                                    SharedAppTheme.secondaryBackground
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            SharedAppTheme.accent.opacity(0.42),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: .black.opacity(0.55), radius: 28, y: 12)
                } else {
                    RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusLarge)
                        .fill(SharedAppTheme.secondaryBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusLarge)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        )
        .modifier(HashKeyPressModifier(
            isActive: labelCompletionVisible,
            count: hashRowCount,
            highlightedIndex: $hashHighlightedIndex
        ))
        .modifier(HashKeyPressModifier(
            isActive: projectCompletionVisible && !projectFilteredDefinitions.isEmpty,
            count: projectFilteredDefinitions.count,
            highlightedIndex: $projectHighlightedIndex
        ))
        #if os(macOS)
        .background(
            MacQuickEntryKeyboardMonitor(
                shouldHandle: { focusedField != nil },
                onReturn: { Task { await submitDraft() } },
                onShiftReturn: { advanceFocusCycle() }
            )
        )
        #endif
    }

    private var iosSheetBody: some View {
        VStack(alignment: .leading, spacing: SharedAppTheme.spacingMedium) {
            titleBlock
            inlineHashChips
            chipRows
            scheduleRow
            footerRow
        }
        .padding(SharedAppTheme.spacingMedium)
        .background(SharedAppTheme.secondaryBackground)
        .modifier(HashKeyPressModifier(
            isActive: labelCompletionVisible,
            count: hashRowCount,
            highlightedIndex: $hashHighlightedIndex
        ))
        .modifier(HashKeyPressModifier(
            isActive: projectCompletionVisible && !projectFilteredDefinitions.isEmpty,
            count: projectFilteredDefinitions.count,
            highlightedIndex: $projectHighlightedIndex
        ))
    }

    /// Trailing `@query` fragment for the active label token (may be empty while typing `@`).
    private var hashActiveQuery: String {
        guard let (_, q) = ActionItemTitleParsing.activeLabelSuffix(in: draft.title) else { return "" }
        return q
    }

    /// Offer “create this label” when nothing matches but the user typed a non-empty query after `@`.
    private var hashShowsCreateRow: Bool {
        guard ActionItemTitleParsing.activeLabelSuffix(in: draft.title) != nil else { return false }
        return hashFilteredContexts.isEmpty && !hashActiveQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Show the label overlay when there are suggestions **or** a create-new-context row.
    private var labelCompletionVisible: Bool {
        guard ActionItemTitleParsing.activeLabelSuffix(in: draft.title) != nil else { return false }
        return !hashFilteredContexts.isEmpty || hashShowsCreateRow
    }

    private var hashRowCount: Int {
        let n = hashFilteredContexts.count
        return hashShowsCreateRow ? n + 1 : n
    }

    /// `true` while the title ends with a `#`, `_`, or `/` project token (show picker even when the filter list is empty).
    private var projectCompletionVisible: Bool {
        ActionItemTitleParsing.activeProjectSuffix(in: draft.title) != nil
    }

    private enum CompletionMode {
        case hash
        case project
    }

    private var activeCompletionMode: CompletionMode? {
        let hashRange = ActionItemTitleParsing.activeLabelSuffix(in: draft.title)?.fullTokenRange
        let projectRange = ActionItemTitleParsing.activeProjectSuffix(in: draft.title)?.fullTokenRange
        switch (hashRange, projectRange) {
        case (nil, nil):
            return nil
        case (.some, nil):
            return labelCompletionVisible ? .hash : nil
        case (nil, .some):
            return projectCompletionVisible ? .project : nil
        case let (h?, p?):
            if h.lowerBound > p.lowerBound {
                return labelCompletionVisible ? .hash : nil
            }
            return projectCompletionVisible ? .project : nil
        }
    }

    private var hashFilteredContexts: [VaultContextDefinition] {
        guard let (_, q) = ActionItemTitleParsing.activeLabelSuffix(in: draft.title) else { return [] }
        let sorted = dedupedContextDefinitions
        if q.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var projectFilteredDefinitions: [VaultProjectDefinition] {
        guard let (_, q) = ActionItemTitleParsing.activeProjectSuffix(in: draft.title) else { return [] }
        let sorted = sortedProjects
        if q.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    /// User edits to the title field use shortcut tokens; programmatic updates from @ / # overlays use `commitHashSelection` / `commitProjectSelection` + `markMenuEdit()`.
    private var titleFieldBinding: Binding<String> {
        Binding(
            get: { draft.title },
            set: { new in
                draft.title = new
                lastShortcutEditSource = .title
            }
        )
    }

    /// Applies a picked label: updates bottom chips, strips `@…` from the title, prefers menu resolution on save.
    private func commitHashSelection(context def: VaultContextDefinition) {
        let t = ActionItemTitleParsing.applyLabelSelection(title: draft.title, contextName: def.name)
        let parsed = ActionItemTitleParsing.parseShortcuts(from: t)
        draft.title = parsed.cleanedTitle
        draft.contextId = def.id
        draft.subjectLabel = def.name
        markMenuEdit()
    }

    /// New label from the “Create @…” row: chips show the name; title loses the `@` token (definition created on save).
    private func commitHashCreateQuery(_ rawQuery: String) {
        let name = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let t = ActionItemTitleParsing.applyLabelSelection(title: draft.title, contextName: name)
        let parsed = ActionItemTitleParsing.parseShortcuts(from: t)
        draft.title = parsed.cleanedTitle
        draft.contextId = nil
        draft.subjectLabel = name
        markMenuEdit()
    }

    /// Applies a picked project: updates the project chip, strips `#…` (or legacy `_…` / `/…`) from the title.
    private func commitProjectSelection(project def: VaultProjectDefinition) {
        let t = ActionItemTitleParsing.applyProjectSelection(title: draft.title, projectName: def.name)
        let parsed = ActionItemTitleParsing.parseShortcuts(from: t)
        draft.title = parsed.cleanedTitle
        draft.projectId = def.id
        markMenuEdit()
    }

    private var macQuickEntryHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: isNew ? "plus.circle.fill" : "square.and.pencil.circle.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(SharedAppTheme.accent)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 4) {
                Text(isNew ? "New action item" : "Edit action item")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(SharedAppTheme.primaryText)
                macQuickEntryHeaderShortcutLine
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Subtitle under the “New action item” header — accent highlights on shortcut keys.
    private var macQuickEntryHeaderShortcutLine: some View {
        (Text("Put ")
            + Text("p0").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text("–")
            + Text("p4").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text(", ")
            + Text("u0").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text("–")
            + Text("u4").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text(", ")
            + Text("@").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text(", ")
            + Text("#").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text(", or ")
            + Text("!").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text(" as separate words in the title (e.g. ")
            + Text("Call p2 u1").foregroundStyle(SharedAppTheme.accent).fontWeight(.medium)
            + Text("). ")
            + Text("!").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text(" counts: ")
            + Text("!").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text(" = P1 … ")
            + Text("!!!!").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text(" = P4."))
            .font(.subheadline)
            .foregroundStyle(SharedAppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Helper line above the notes field — same key highlights as the header subtitle.
    private var macProminentShortcutHelper: some View {
        (Text("Separate words: ")
            + Text("p0–p4").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text(" · ")
            + Text("u0–u4").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text(" · ")
            + Text("@").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text(" · ")
            + Text("#").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text(" · ")
            + Text("!").foregroundStyle(SharedAppTheme.accent).fontWeight(.semibold)
            + Text("→P1…P4"))
            .font(.subheadline)
            .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.95))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var titleBlock: some View {
        Group {
            if isMacProminentQuickEntry {
                macProminentTitleFields
            } else {
                standardTitleFields
            }
        }
    }

    private var standardTitleFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextField("Action Name", text: titleFieldBinding)
                    .font(SharedAppTheme.title3)
                    .foregroundStyle(SharedAppTheme.primaryText)
                    .focused($focusedField, equals: .title)
                    .lineLimit(1 ... 4)
                    #if !os(macOS)
                    .onSubmit {
                        Task { await submitDraft() }
                    }
                    #endif
                    .accessibilityHint("Use at sign for labels, number sign for projects, P0 through P4 or exclamation marks for priority, U0 through U4 for urgency.")

                if labelCompletionVisible {
                    hashSuggestionOverlay
                        .padding(.top, hashSuggestionTopInset)
                } else if projectCompletionVisible {
                    projectSuggestionOverlay
                        .padding(.top, hashSuggestionTopInset)
                }
            }

            Text("@ sets labels; # sets projects; P0–P4 or exclamation marks set priority; U0–U4 sets urgency.")
                .font(SharedAppTheme.caption)
                .foregroundStyle(SharedAppTheme.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Description", text: Binding(
                get: { draft.taskDescription ?? "" },
                set: { draft.taskDescription = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .font(SharedAppTheme.subheadline)
            .foregroundStyle(SharedAppTheme.secondaryText)
            .focused($focusedField, equals: .description)
            #if !os(macOS)
            .onSubmit {
                Task { await submitDraft() }
            }
            #endif
        }
    }

    private var macProminentTitleFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextField("What needs to be done?", text: titleFieldBinding)
                    .textFieldStyle(.plain)
                    .font(SharedAppTheme.title2)
                    .foregroundStyle(SharedAppTheme.primaryText)
                    .focused($focusedField, equals: .title)
                    .lineLimit(2 ... 6)
                    .padding(18)
                    .frame(minHeight: 64, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusMedium, style: .continuous)
                            .fill(Color.black.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusMedium, style: .continuous)
                                    .strokeBorder(
                                        focusedField == .title ? SharedAppTheme.accent.opacity(0.55) : Color.white.opacity(0.14),
                                        lineWidth: focusedField == .title ? 1.5 : 1
                                    )
                            )
                    )
                    .accessibilityHint("Use at sign for labels, number sign for projects, P0 through P4 or exclamation marks for priority, U0 through U4 for urgency.")

                if labelCompletionVisible {
                    hashSuggestionOverlay
                        .padding(.top, 72)
                } else if projectCompletionVisible {
                    projectSuggestionOverlay
                        .padding(.top, 72)
                }
            }

            macProminentShortcutHelper

            TextField("Notes (optional)", text: Binding(
                get: { draft.taskDescription ?? "" },
                set: { draft.taskDescription = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(SharedAppTheme.body)
            .foregroundStyle(SharedAppTheme.primaryText.opacity(0.95))
            .lineLimit(3 ... 7)
            .padding(14)
            .frame(minHeight: 76, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusMedium, style: .continuous)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusMedium, style: .continuous)
                            .strokeBorder(
                                focusedField == .description ? SharedAppTheme.accent.opacity(0.45) : Color.white.opacity(0.12),
                                lineWidth: focusedField == .description ? 1.5 : 1
                            )
                    )
            )
            .focused($focusedField, equals: .description)
        }
    }

    private var hashSuggestionOverlay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(hashFilteredContexts.enumerated()), id: \.element.id) { idx, c in
                    Button {
                        commitHashSelection(context: c)
                        hashHighlightedIndex = 0
                    } label: {
                        HStack(spacing: 8) {
                            Text("@")
                                .foregroundStyle(Color(hex: c.accentColorHex ?? ContextAccentPalette.defaultGreyHex))
                            Text(c.name)
                                .foregroundStyle(SharedAppTheme.primaryText)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(idx == hashHighlightedIndex ? Color.white.opacity(0.12) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
                if hashShowsCreateRow {
                    let createIdx = hashFilteredContexts.count
                    let q = hashActiveQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    Button {
                        commitHashCreateQuery(q)
                        hashHighlightedIndex = 0
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(SharedAppTheme.accent)
                            Text("Create “@\(q)” on save")
                                .foregroundStyle(SharedAppTheme.primaryText)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(createIdx == hashHighlightedIndex ? Color.white.opacity(0.12) : Color.clear)
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

    private var projectSuggestionOverlay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(projectFilteredDefinitions.enumerated()), id: \.element.id) { idx, p in
                    Button {
                        commitProjectSelection(project: p)
                        projectHighlightedIndex = 0
                    } label: {
                        HStack(spacing: 8) {
                            Text("#")
                                .foregroundStyle(SharedAppTheme.accent)
                            Text(p.name)
                                .foregroundStyle(SharedAppTheme.primaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(idx == projectHighlightedIndex ? Color.white.opacity(0.12) : Color.clear)
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
        let tags = ActionItemTitleParsing.labelTagNames(in: draft.title)
        guard !tags.isEmpty else { return AnyView(EmptyView()) }
        let tagFont: Font = isMacProminentQuickEntry ? .subheadline.weight(.medium) : SharedAppTheme.caption
        let hPad: CGFloat = isMacProminentQuickEntry ? 14 : 8
        let vPad: CGFloat = isMacProminentQuickEntry ? 8 : 4
        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: isMacProminentQuickEntry ? 10 : 6) {
                    ForEach(tags, id: \.self) { tag in
                        let hex = contexts.first(where: { $0.name.caseInsensitiveCompare(tag) == .orderedSame })?.accentColorHex
                            ?? ContextAccentPalette.defaultGreyHex
                        Text("@" + tag)
                            .font(tagFont)
                            .foregroundStyle(SharedAppTheme.primaryText)
                            .padding(.horizontal, hPad)
                            .padding(.vertical, vPad)
                            .background(
                                RoundedRectangle(cornerRadius: isMacProminentQuickEntry ? 8 : 6)
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
            urgencyChip
            contextChip
            projectChip
        }
    }

    private var scheduleRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Schedule")
                .font(isMacProminentQuickEntry ? .subheadline.weight(.semibold) : SharedAppTheme.caption)
                .foregroundStyle(SharedAppTheme.secondaryText)
                .frame(minWidth: isMacProminentQuickEntry ? 88 : 72, alignment: .leading)
            Spacer(minLength: 0)
            Toggle(
                "",
                isOn: Binding(
                    get: { draft.scheduledDate != nil },
                    set: { on in
                        if on {
                            draft.scheduledDate = Calendar.current.startOfDay(for: Date())
                        } else {
                            draft.scheduledDate = nil
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(isMacProminentQuickEntry ? .regular : .small)
            if draft.scheduledDate != nil {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { draft.scheduledDate ?? Date() },
                        set: { draft.scheduledDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .fixedSize()
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
            Button("None") { markMenuEdit(); draft.priority = nil }
            ForEach(0 ... 4, id: \.self) { p in
                Button("Priority \(p)") { markMenuEdit(); draft.priority = p }
            }
        } label: {
            chipLabel(
                macAssetName: ActionItemsQuickEntryChipMacAsset.priority,
                systemImage: ActionItemsSection.priority.sidebarSystemImage,
                text: displayedPriority.map { "P\($0)" } ?? "Priority",
                accent: false,
                tint: displayedPriority.map { ActionItemPriorityColors.color(forStoredPriority: $0) }
            )
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($focusedField, equals: .priority)
    }

    private var urgencyChip: some View {
        Menu {
            Button("None") { markMenuEdit(); draft.urgency = nil }
            ForEach(0 ... 4, id: \.self) { u in
                Button("Urgency \(u)") { markMenuEdit(); draft.urgency = u }
            }
        } label: {
            chipLabel(
                macAssetName: ActionItemsQuickEntryChipMacAsset.urgency,
                systemImage: ActionItemsSection.urgency.sidebarSystemImage,
                text: displayedUrgency.map { "U\($0)" } ?? "Urgency",
                accent: false,
                tint: displayedUrgency.map { ActionItemPriorityColors.color(forStoredPriority: $0) }
            )
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($focusedField, equals: .urgency)
    }

    private var contextChip: some View {
        Menu {
            Button(ActionItemsFeatureModel.unspecifiedSubjectKey) {
                markMenuEdit()
                draft.contextId = nil
                draft.subjectLabel = nil
            }
            ForEach(contextPickerEntries, id: \.key) { entry in
                Button(entry.key) {
                    markMenuEdit()
                    if let c = entry.context {
                        draft.contextId = c.id
                        draft.subjectLabel = c.name
                    } else {
                        draft.contextId = nil
                        draft.subjectLabel = nil
                    }
                }
            }
            if let onManageTags {
                Divider()
                Button("Manage labels…") { onManageTags() }
            }
        } label: {
            chipLabel(
                macAssetName: ActionItemsQuickEntryChipMacAsset.labels,
                systemImage: ActionItemsSection.labels.sidebarSystemImage,
                text: displayedContextChipText,
                accent: displayedContextChipAccent
            )
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($focusedField, equals: .context)
    }

    private var projectChip: some View {
        Menu {
            Button("#\(ActionItemsFeatureModel.generalProjectName)") {
                markMenuEdit()
                draft.projectId = nil
            }
            ForEach(sortedProjects) { project in
                Button("#\(project.name)") {
                    markMenuEdit()
                    draft.projectId = project.id
                }
            }
        } label: {
            chipLabel(
                macAssetName: ActionItemsQuickEntryChipMacAsset.projects,
                systemImage: ActionItemsSection.projects.sidebarSystemImage,
                text: ActionItemsFeatureModel.displayProjectPath(displayedProjectNameForChip),
                accent: displayedProjectNameForChip != nil
            )
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($focusedField, equals: .project)
    }

    @ViewBuilder
    private func chipLeadingIcon(macAssetName: String, systemImage: String) -> some View {
        #if os(macOS)
        Image(macAssetName)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: isMacProminentQuickEntry ? 18 : 14, height: isMacProminentQuickEntry ? 18 : 14)
        #else
        Image(systemName: systemImage)
            .font(.caption.weight(.semibold))
        #endif
    }

    private func chipLabel(macAssetName: String, systemImage: String, text: String, accent: Bool, tint: Color? = nil) -> some View {
        let fg = tint ?? (accent ? Color.green : SharedAppTheme.secondaryText)
        let border = tint ?? Color.white.opacity(0.2)
        let chipFont: Font = isMacProminentQuickEntry ? .subheadline.weight(.medium) : SharedAppTheme.caption
        let hPad: CGFloat = isMacProminentQuickEntry ? 14 : 10
        let vPad: CGFloat = isMacProminentQuickEntry ? 10 : 6
        let spacing: CGFloat = isMacProminentQuickEntry ? 8 : 6
        return HStack(spacing: spacing) {
            chipLeadingIcon(macAssetName: macAssetName, systemImage: systemImage)
            Text(text)
                .font(chipFont)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .background(
            Capsule()
                .stroke(border, lineWidth: isMacProminentQuickEntry ? 1.25 : 1)
        )
    }

    private var sortedContexts: [VaultContextDefinition] {
        contexts.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var sortedProjects: [VaultProjectDefinition] {
        projects.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var contextPickerEntries: [ActionItemsFeatureModel.ContextPickerEntry] {
        ActionItemsFeatureModel.dedupedContextPickerEntries(definitions: contexts)
    }

    private var dedupedContextDefinitions: [VaultContextDefinition] {
        contextPickerEntries.compactMap(\.context)
    }

    private var projectNameForCurrentDraft: String? {
        guard let projectId = draft.projectId else { return nil }
        return projects.first(where: { $0.id == projectId })?.name
    }

    private var canSaveDraft: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var footerRow: some View {
        VStack(spacing: isMacProminentQuickEntry ? 16 : 12) {
            Divider().opacity(0.3)
            HStack(spacing: 14) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                    .font(isMacProminentQuickEntry ? .body : .callout)
                Button(isNew ? "Add Action Item" : "Save") {
                    Task { await submitDraft() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .controlSize(isMacProminentQuickEntry ? .large : .regular)
                .font(isMacProminentQuickEntry ? .body.weight(.semibold) : .body)
                .focusable(true)
                .focused($focusedField, equals: .submit)
                .disabled(!canSaveDraft)
                .opacity(canSaveDraft ? 1 : 0.45)
            }
        }
    }

    private func submitDraft() async {
        guard canSaveDraft else { return }
        if activeCompletionMode == .hash {
            guard hashRowCount > 0 else {
                await persist()
                return
            }
            let i = min(max(0, hashHighlightedIndex), hashRowCount - 1)
            if i < hashFilteredContexts.count {
                commitHashSelection(context: hashFilteredContexts[i])
            } else if hashShowsCreateRow {
                let name = hashActiveQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                commitHashCreateQuery(name)
            }
            hashHighlightedIndex = 0
            return
        }
        if activeCompletionMode == .project {
            if !projectFilteredDefinitions.isEmpty {
                let i = min(max(0, projectHighlightedIndex), projectFilteredDefinitions.count - 1)
                commitProjectSelection(project: projectFilteredDefinitions[i])
            } else {
                await persist()
            }
            return
        }
        await persist()
    }

    /// Persists the draft. Shortcut tokens are always stripped from the stored title. If the user last edited via the title field, parsed `@`/`#`/`p`/`u` tokens win; if they last used chips/menus, chip state wins for priority, urgency, and labels.
    private func persist() async {
        let parsed = ActionItemTitleParsing.parseShortcuts(from: draft.title)

        switch lastShortcutEditSource {
        case .title:
            var toSave = draft
            toSave.title = parsed.cleanedTitle
            toSave.priority = parsed.priority ?? draft.priority
            toSave.urgency = parsed.urgency ?? draft.urgency

            if let ctxName = parsed.contextName {
                let trimmed = ctxName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if let existing = dedupedContextDefinitions.first(where: { ActionItemsFeatureModel.normalizedSubjectKey($0.name) == ActionItemsFeatureModel.normalizedSubjectKey(trimmed) }) {
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

            if let parsedProject = parsed.projectName {
                let trimmed = parsedProject.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if let existing = sortedProjects.first(where: {
                        ActionItemsFeatureModel.normalizedProjectKey($0.name).lowercased() == ActionItemsFeatureModel.normalizedProjectKey(trimmed).lowercased()
                    }) {
                        toSave.projectId = existing.id
                    } else {
                        let order = sortedProjects.map(\.sortOrder).max() ?? 0
                        let newDef = VaultProjectDefinition(name: trimmed, sortOrder: order + 1)
                        do {
                            try await vaultManager.upsertProjectDefinition(newDef)
                            toSave.projectId = newDef.id
                        } catch {
                            return
                        }
                    }
                }
            }

            normalizeScheduledDate(&toSave)
            do {
                try await vaultManager.upsertActionItem(toSave)
                await onSave(toSave, isNew)
            } catch {}

        case .menu:
            var toSave = draft
            toSave.title = parsed.cleanedTitle
            toSave.priority = draft.priority
            toSave.urgency = draft.urgency
            toSave.contextId = draft.contextId
            toSave.subjectLabel = draft.subjectLabel
            toSave.projectId = draft.projectId

            if toSave.contextId == nil,
               let sl = toSave.subjectLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !sl.isEmpty,
               ActionItemsFeatureModel.normalizedSubjectKey(sl) != ActionItemsFeatureModel.unspecifiedSubjectKey
            {
                if let existing = dedupedContextDefinitions.first(where: { ActionItemsFeatureModel.normalizedSubjectKey($0.name) == ActionItemsFeatureModel.normalizedSubjectKey(sl) }) {
                    toSave.contextId = existing.id
                    toSave.subjectLabel = existing.name
                } else {
                    let order = sortedContexts.map(\.sortOrder).max() ?? 0
                    let newDef = VaultContextDefinition(
                        name: sl,
                        accentColorHex: ContextAccentPalette.defaultGreyHex,
                        sortOrder: order + 1
                    )
                    do {
                        try await vaultManager.upsertContextDefinition(newDef)
                        toSave.contextId = newDef.id
                        toSave.subjectLabel = sl
                    } catch {
                        return
                    }
                }
            }

            normalizeScheduledDate(&toSave)
            do {
                try await vaultManager.upsertActionItem(toSave)
                await onSave(toSave, isNew)
            } catch {}
        }
    }

    private func normalizeScheduledDate(_ item: inout VaultActionItemRecord) {
        if let s = item.scheduledDate {
            item.scheduledDate = Calendar.current.startOfDay(for: s)
        }
    }

    #if os(macOS)
    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard activeCompletionMode == nil else { return }
        switch direction {
        case .up:
            moveFocus(up: true)
        case .down:
            moveFocus(up: false)
        default:
            break
        }
    }
    #endif

    private func moveFocus(up: Bool) {
        let order: [Field] = [.title, .description, .priority, .urgency, .context, .project, .submit]
        let current = focusedField ?? .title
        guard let idx = order.firstIndex(of: current) else {
            focusedField = .title
            return
        }
        let next = up ? max(0, idx - 1) : min(order.count - 1, idx + 1)
        focusedField = order[next]
    }

    /// Shift+Return cycles: Action Name → Description → Priority → Urgency → Label → Project → Add Action Item → …
    private func advanceFocusCycle() {
        let order: [Field] = [.title, .description, .priority, .urgency, .context, .project, .submit]
        let current = focusedField ?? .title
        guard let idx = order.firstIndex(of: current) else {
            focusedField = order[0]
            return
        }
        let next = (idx + 1) % order.count
        focusedField = order[next]
    }
}

// MARK: - macOS Return / Shift+Return (SwiftUI onKeyPress cannot read modifiers on this SDK)

#if os(macOS)
private struct MacQuickEntryKeyboardMonitor: NSViewRepresentable {
    var shouldHandle: () -> Bool
    var onReturn: () -> Void
    var onShiftReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.isHidden = true
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator
        c.shouldHandle = shouldHandle
        c.onReturn = onReturn
        c.onShiftReturn = onShiftReturn
        c.installIfNeeded()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var shouldHandle: () -> Bool = { false }
        var onReturn: () -> Void = {}
        var onShiftReturn: () -> Void = {}
        var monitor: Any?

        deinit {
            remove()
        }

        /// `kVK_Return` — main keyboard Return; also handles Enter on numeric keypad via `kVK_ANSI_KeypadEnter` (76).
        func installIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard event.keyCode == 36 || event.keyCode == 76 else { return event }
                guard self.shouldHandle() else { return event }
                if event.modifierFlags.contains(.shift) {
                    self.onShiftReturn()
                } else {
                    self.onReturn()
                }
                return nil
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
#endif

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
        #elseif os(iOS)
        if #available(iOS 17.0, *) {
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
