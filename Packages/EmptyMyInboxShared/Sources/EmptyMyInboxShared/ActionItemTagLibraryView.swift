//
//  ActionItemTagLibraryView.swift
//  EmptyMyInboxShared
//

import SwiftUI

/// Manage saved contexts and action types (rich tagging).
public struct ActionItemTagLibraryView: View {
    @ObservedObject private var vaultManager = VaultManager.shared
    @State private var segment = 0
    @State private var contexts: [VaultContextDefinition] = []
    @State private var types: [VaultActionTypeDefinition] = []
    @State private var editingContext: VaultContextDefinition?
    @State private var editingType: VaultActionTypeDefinition?
    @State private var errorText: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                Text("Contexts").tag(0)
                Text("Types").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if let errorText {
                Text(errorText)
                    .font(SharedAppTheme.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            if segment == 0 {
                contextList
            } else {
                typeList
            }
        }
        .navigationTitle("Tags")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if segment == 0 {
                        editingContext = VaultContextDefinition(name: "New context")
                    } else {
                        editingType = VaultActionTypeDefinition(name: "New type")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await reload() }
        .sheet(item: $editingContext) { ctx in
            NavigationStack {
                contextEditorForm(ctx)
            }
        }
        .sheet(item: $editingType) { t in
            NavigationStack {
                typeEditorForm(t)
            }
        }
    }

    private var contextList: some View {
        List {
            ForEach(contexts.sorted(by: { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) })) { c in
                Button {
                    editingContext = c
                } label: {
                    HStack {
                        Image(systemName: resolvedSymbolName(c.symbolName, fallback: "tag.fill"))
                            .foregroundStyle(Color(hex: c.accentColorHex ?? "#f6ac0a"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name)
                                .font(SharedAppTheme.body)
                                .foregroundStyle(SharedAppTheme.primaryText)
                            if let n = c.notes, !n.isEmpty {
                                Text(n)
                                    .font(SharedAppTheme.caption)
                                    .foregroundStyle(SharedAppTheme.secondaryText)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .onDelete { offsets in
                Task {
                    let sorted = contexts.sorted(by: { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) })
                    for i in offsets {
                        try? await vaultManager.deleteContextDefinition(id: sorted[i].id)
                    }
                    await reload()
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var typeList: some View {
        List {
            ForEach(types.sorted(by: { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) })) { t in
                Button {
                    editingType = t
                } label: {
                    HStack {
                        Image(systemName: resolvedSymbolName(t.symbolName, fallback: "square.grid.2x2"))
                            .foregroundStyle(Color(hex: t.accentColorHex ?? "#f6ac0a"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name)
                                .font(SharedAppTheme.body)
                                .foregroundStyle(SharedAppTheme.primaryText)
                            if let n = t.notes, !n.isEmpty {
                                Text(n)
                                    .font(SharedAppTheme.caption)
                                    .foregroundStyle(SharedAppTheme.secondaryText)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .onDelete { offsets in
                Task {
                    let sorted = types.sorted(by: { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) })
                    for i in offsets {
                        try? await vaultManager.deleteActionTypeDefinition(id: sorted[i].id)
                    }
                    await reload()
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func contextEditorForm(_ ctx: VaultContextDefinition) -> some View {
        ContextTypeEditorForm(
            title: "Context",
            name: ctx.name,
            notes: ctx.notes ?? "",
            accentHex: ctx.accentColorHex ?? "f6ac0a",
            symbolName: ctx.symbolName ?? "",
            sortOrder: ctx.sortOrder,
            id: ctx.id,
            onSave: { name, notes, hex, sym, order in
                Task {
                    var next = ctx
                    next.name = name
                    next.notes = notes.isEmpty ? nil : notes
                    next.accentColorHex = hex.isEmpty ? nil : hex
                    next.symbolName = sym.isEmpty ? nil : sym
                    next.sortOrder = order
                    try? await vaultManager.upsertContextDefinition(next)
                    editingContext = nil
                    await reload()
                }
            },
            onCancel: { editingContext = nil }
        )
    }

    private func typeEditorForm(_ t: VaultActionTypeDefinition) -> some View {
        ContextTypeEditorForm(
            title: "Type",
            name: t.name,
            notes: t.notes ?? "",
            accentHex: t.accentColorHex ?? "f6ac0a",
            symbolName: t.symbolName ?? "",
            sortOrder: t.sortOrder,
            id: t.id,
            onSave: { name, notes, hex, sym, order in
                Task {
                    var next = t
                    next.name = name
                    next.notes = notes.isEmpty ? nil : notes
                    next.accentColorHex = hex.isEmpty ? nil : hex
                    next.symbolName = sym.isEmpty ? nil : sym
                    next.sortOrder = order
                    try? await vaultManager.upsertActionTypeDefinition(next)
                    editingType = nil
                    await reload()
                }
            },
            onCancel: { editingType = nil }
        )
    }

    private func reload() async {
        errorText = nil
        do {
            contexts = try await vaultManager.listContextDefinitions()
            types = try await vaultManager.listActionTypeDefinitions()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func resolvedSymbolName(_ symbol: String?, fallback: String) -> String {
        guard let s = symbol, !s.isEmpty else { return fallback }
        return s
    }
}

// MARK: - Editor forms (shared)

private struct ContextTypeEditorForm: View {
    let title: String
    @State private var name: String
    @State private var notes: String
    @State private var accentHex: String
    @State private var symbolName: String
    @State private var sortOrder: Int
    let id: String
    let onSave: (String, String, String, String, Int) -> Void
    let onCancel: () -> Void

    init(
        title: String,
        name: String,
        notes: String,
        accentHex: String,
        symbolName: String,
        sortOrder: Int,
        id: String,
        onSave: @escaping (String, String, String, String, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        _name = State(initialValue: name)
        _notes = State(initialValue: notes)
        _accentHex = State(initialValue: accentHex)
        _symbolName = State(initialValue: symbolName)
        _sortOrder = State(initialValue: sortOrder)
        self.id = id
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Notes", text: $notes, axis: .vertical)
                TextField("Accent #hex", text: $accentHex)
                TextField("SF Symbol name", text: $symbolName)
                Stepper("Sort order: \(sortOrder)", value: $sortOrder, in: 0 ... 10_000)
            }
        }
        .id(id)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(name, notes, accentHex, symbolName, sortOrder)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
