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

    @ObservedObject private var vaultManager = VaultManager.shared
    @State private var events: [VaultCalendarEventRecord] = []
    @State private var errorText: String?
    @State private var showAdd = false
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()

                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        MainAppTopBar(center: {
                            Text("Calendar")
                                .font(AppTheme.headline)
                                .primaryText()
                        }, onMenuTap: onMenuTap)

                        if let errorText {
                            Text(errorText)
                                .font(AppTheme.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal)
                        }

                        List {
                            ForEach(events) { ev in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ev.title)
                                        .font(AppTheme.body)
                                        .primaryText()
                                    if let s = ev.startDate {
                                        Text(s.formatted(date: .abbreviated, time: .shortened))
                                            .font(AppTheme.caption)
                                            .secondaryText()
                                    }
                                }
                                .listRowBackground(AppTheme.secondaryBackground.opacity(0.35))
                            }
                            .onDelete(perform: deleteEvents)
                        }
                        .scrollContentBackground(.hidden)
                        .listStyle(.plain)
                    }

                    Button {
                        newTitle = ""
                        showAdd = true
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
        .onReceive(NotificationCenter.default.publisher(for: .vaultDidSync)) { _ in
            Task { await reload() }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    TextField("Title", text: $newTitle)
                }
                .navigationTitle("New event")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAdd = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                let ev = VaultCalendarEventRecord(title: newTitle.isEmpty ? "Untitled" : newTitle)
                                try? await vaultManager.upsertCalendarEvent(ev)
                                showAdd = false
                                await reload()
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func deleteEvents(at offsets: IndexSet) {
        Task {
            for i in offsets {
                let id = events[i].id
                try? await vaultManager.deleteCalendarEvent(id: id)
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

struct ActionItemsSkeletonView: View {
    var onMenuTap: () -> Void

    @ObservedObject private var vaultManager = VaultManager.shared
    @State private var items: [VaultActionItemRecord] = []
    @State private var errorText: String?
    @State private var showAdd = false
    @State private var newTitle = ""

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

                        if let errorText {
                            Text(errorText)
                                .font(AppTheme.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal)
                        }

                        List {
                            ForEach(items) { item in
                                HStack(alignment: .center, spacing: AppTheme.spacingMedium) {
                                    Button {
                                        Task {
                                            var u = item
                                            u.isDone.toggle()
                                            try? await vaultManager.upsertActionItem(u)
                                            await reload()
                                        }
                                    } label: {
                                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.isDone ? AppTheme.accent : AppTheme.secondaryText)
                                    }
                                    .buttonStyle(.plain)

                                    Text(item.title)
                                        .font(AppTheme.body)
                                        .strikethrough(item.isDone)
                                        .primaryText()
                                }
                                .listRowBackground(AppTheme.secondaryBackground.opacity(0.35))
                            }
                            .onDelete(perform: deleteItems)
                        }
                        .scrollContentBackground(.hidden)
                        .listStyle(.plain)
                    }

                    Button {
                        newTitle = ""
                        showAdd = true
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
        .onReceive(NotificationCenter.default.publisher(for: .vaultDidSync)) { _ in
            Task { await reload() }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    TextField("Title", text: $newTitle)
                }
                .navigationTitle("New action")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAdd = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                let it = VaultActionItemRecord(title: newTitle.isEmpty ? "Untitled" : newTitle)
                                try? await vaultManager.upsertActionItem(it)
                                showAdd = false
                                await reload()
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        Task {
            for i in offsets {
                let id = items[i].id
                try? await vaultManager.deleteActionItem(id: id)
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
