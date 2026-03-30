//
//  MacVaultFeatureViews.swift
//  emptymyinboxMacApp
//

import SwiftUI
import EmptyMyInboxShared

struct MacVaultCalendarTab: View {
    @ObservedObject private var vaultManager = VaultManager.shared
    @State private var events: [VaultCalendarEventRecord] = []
    @State private var errorText: String?
    @State private var newTitle = ""
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Calendar")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MacAppTheme.primaryText)
                Spacer()
                Button {
                    newTitle = ""
                    isAdding = true
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .labelStyle(.iconOnly)
                .help("Add event")
            }
            .padding(MacAppTheme.spacingMedium)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, MacAppTheme.spacingMedium)
            }

            List {
                ForEach(events) { ev in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ev.title)
                            .foregroundStyle(MacAppTheme.primaryText)
                        if let s = ev.startDate {
                            Text(s.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(MacAppTheme.secondaryText)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: deleteAt)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppTheme.primaryBackground)
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .vaultDidSync)) { _ in
            Task { await reload() }
        }
        .sheet(isPresented: $isAdding) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New event")
                    .font(.headline)
                TextField("Title", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { isAdding = false }
                    Button("Save") {
                        Task {
                            let ev = VaultCalendarEventRecord(title: newTitle.isEmpty ? "Untitled" : newTitle)
                            try? await vaultManager.upsertCalendarEvent(ev)
                            isAdding = false
                            await reload()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(minWidth: 320)
        }
    }

    private func deleteAt(_ offsets: IndexSet) {
        Task {
            for i in offsets {
                try? await vaultManager.deleteCalendarEvent(id: events[i].id)
            }
            await reload()
        }
    }

    private func reload() async {
        errorText = nil
        do {
            events = try await vaultManager.listCalendarEvents()
        } catch {
            errorText = error.localizedDescription
            events = []
        }
    }
}

struct MacVaultActionItemsTab: View {
    @ObservedObject private var vaultManager = VaultManager.shared
    @State private var items: [VaultActionItemRecord] = []
    @State private var errorText: String?
    @State private var newTitle = ""
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Action Items")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MacAppTheme.primaryText)
                Spacer()
                Button {
                    newTitle = ""
                    isAdding = true
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .labelStyle(.iconOnly)
            }
            .padding(MacAppTheme.spacingMedium)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, MacAppTheme.spacingMedium)
            }

            List {
                ForEach(items) { item in
                    HStack {
                        Button {
                            Task {
                                var u = item
                                u.isDone.toggle()
                                try? await vaultManager.upsertActionItem(u)
                                await reload()
                            }
                        } label: {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.plain)
                        Text(item.title)
                            .strikethrough(item.isDone)
                            .foregroundStyle(MacAppTheme.primaryText)
                    }
                }
                .onDelete(perform: deleteAt)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppTheme.primaryBackground)
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .vaultDidSync)) { _ in
            Task { await reload() }
        }
        .sheet(isPresented: $isAdding) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New action")
                    .font(.headline)
                TextField("Title", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { isAdding = false }
                    Button("Save") {
                        Task {
                            let it = VaultActionItemRecord(title: newTitle.isEmpty ? "Untitled" : newTitle)
                            try? await vaultManager.upsertActionItem(it)
                            isAdding = false
                            await reload()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(minWidth: 320)
        }
    }

    private func deleteAt(_ offsets: IndexSet) {
        Task {
            for i in offsets {
                try? await vaultManager.deleteActionItem(id: items[i].id)
            }
            await reload()
        }
    }

    private func reload() async {
        errorText = nil
        do {
            items = try await vaultManager.listActionItems()
        } catch {
            errorText = error.localizedDescription
            items = []
        }
    }
}
