//
//  MacVaultSettingsView.swift
//  emptymyinboxMacApp
//

import AppKit
import SwiftUI
import EmptyMyInboxShared

struct MacVaultSettingsView: View {
    /// When opened from the Settings `NavigationStack`, the system back control is enough; a second "Close" clashes with the toolbar.
    var showDismissToolbar: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var vaultManager = VaultManager.shared

    @State private var busy = false
    @State private var alertMessage: String?
    @State private var discoveredVaults: [DiscoveredVaultSummary] = []
    @State private var remoteDriveVaults: [DiscoveredRemoteGoogleDriveVaultSummary] = []
    @State private var attemptedRemoteDriveDiscovery = false
    @State private var showDeleteSheet = false
    @State private var deleteRemoteDriveToo = false

    private var openableVaults: [DiscoveredVaultSummary] {
        guard let activeId = vaultManager.activeConfiguration?.vaultId else {
            return discoveredVaults
        }
        return discoveredVaults.filter { $0.vaultId != activeId }
    }

    private var openableRemoteDriveVaults: [DiscoveredRemoteGoogleDriveVaultSummary] {
        guard let active = vaultManager.activeConfiguration else {
            return remoteDriveVaults
        }
        return remoteDriveVaults.filter {
            $0.vaultId != active.vaultId && $0.driveRootFolderId != active.driveRootFolderId
        }
    }

    var body: some View {
        List {
                Section {
                    if let c = vaultManager.activeConfiguration {
                        LabeledContent("Backend") { Text(backendTitle(c.backend)) }
                        if let name = c.displayName, !name.isEmpty {
                            LabeledContent("Name") { Text(name) }
                        }
                        if let email = c.driveAccountEmail {
                            LabeledContent("Drive account") { Text(email) }
                        }
                    } else {
                        Text("No vault loaded").foregroundStyle(MacAppTheme.secondaryText)
                    }
                    if let err = vaultManager.lastSyncErrorMessage {
                        Text(err).font(.caption).foregroundStyle(.orange)
                    }
                    if let t = vaultManager.lastSuccessfulSyncAt {
                        LabeledContent("Last sync") {
                            Text(t.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    if vaultManager.activeConfiguration != nil {
                        Button {
                            revealCurrentVaultInFinder()
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                    }
                    if let url = vaultManager.activeConfiguration?.googleDriveRootWebURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open in Google Drive", systemImage: "arrow.up.right.square")
                        }
                    }
                } header: {
                    Text("Current vault")
                }

                Section {
                    ForEach(openableVaults) { summary in
                        Button {
                            Task { await openDiscovered(summary) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.displayName ?? summary.vaultId)
                                    .foregroundStyle(.primary)
                                Text(backendTitle(summary.backendKind))
                                    .font(.caption)
                                    .foregroundStyle(MacAppTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .contextMenu {
                            if let url = summary.googleDriveRootWebURL {
                                Button {
                                    openURL(url)
                                } label: {
                                    Label("Open in Google Drive", systemImage: "arrow.up.right.square")
                                }
                            }
                        }
                    }
                    if discoveredVaults.isEmpty {
                        Text("No saved vault mirrors on this device yet.")
                            .foregroundStyle(MacAppTheme.secondaryText)
                    } else if openableVaults.isEmpty {
                        Text("No other vaults to open. The active vault is already selected. Use Switch vault below to create another vault on this device.")
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
                } header: {
                    Text("Open vault")
                } footer: {
                    Text("These are vault mirrors already stored on this device under the app’s local storage. Disconnecting a Google account removes its vault from the app and deletes the on-device mirror (your Google Drive folder is unchanged). Only one vault is active at a time—opening one replaces the current one. To use an external folder vault again, choose it with “Choose folder…”.")
                }

                Section {
                    Button {
                        Task { await discoverRemoteDriveVaults() }
                    } label: {
                        Label("Find existing Google Drive vaults", systemImage: "magnifyingglass")
                    }
                    .disabled(busy)

                    ForEach(openableRemoteDriveVaults) { summary in
                        Button {
                            Task { await openRemoteDriveVault(summary) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.displayName ?? summary.vaultId)
                                    .foregroundStyle(.primary)
                                Text(summary.connectedAccountEmail)
                                    .font(.caption)
                                    .foregroundStyle(MacAppTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .contextMenu {
                            if let url = summary.googleDriveRootWebURL {
                                Button {
                                    openURL(url)
                                } label: {
                                    Label("Open in Google Drive", systemImage: "arrow.up.right.square")
                                }
                            }
                        }
                    }

                    if attemptedRemoteDriveDiscovery && remoteDriveVaults.isEmpty {
                        Text("No existing Google Drive vaults were found for this signed-in account.")
                            .foregroundStyle(MacAppTheme.secondaryText)
                    } else if attemptedRemoteDriveDiscovery && openableRemoteDriveVaults.isEmpty && !remoteDriveVaults.isEmpty {
                        Text("The discovered Google Drive vault is already active on this device.")
                            .foregroundStyle(MacAppTheme.secondaryText)
                    }
                } header: {
                    Text("Open Google Drive vault")
                } footer: {
                    Text("Google Drive vaults always keep a local mirror on each device. Use this to connect this device to a vault folder that was created on another device.")
                }

                Section {
                    Button {
                        Task { await createLocalVault() }
                    } label: {
                        Label("New local vault", systemImage: "folder.badge.plus")
                    }
                    .disabled(busy)

                    Button {
                        chooseExternalFolder()
                    } label: {
                        Label("Choose folder…", systemImage: "folder")
                    }
                    .disabled(busy)

                    Button {
                        Task { await createDriveVault() }
                    } label: {
                        Label("New Google Drive vault", systemImage: "externaldrive")
                    }
                    .disabled(busy)
                } header: {
                    Text("Switch vault")
                } footer: {
                    Text("Creating or switching replaces the active vault. Local vaults stay on this device. A folder vault syncs via the system. A Drive vault uses the Google Drive API with your signed-in Gmail account.")
                }

                Section {
                    if vaultManager.activeConfiguration != nil {
                        Button(role: .destructive) {
                            deleteRemoteDriveToo = false
                            showDeleteSheet = true
                        } label: {
                            Label("Delete current vault…", systemImage: "trash")
                        }
                        .disabled(busy)
                    }
                } footer: {
                    Text("Removes this vault from the app on this device. Files inside a chosen folder are not deleted.")
                }

                Section {
                    Button {
                        Task { await vaultManager.performLifecycleSync() }
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(busy || vaultManager.activeConfiguration?.backend != .googleDrive)
                }
            }
            .navigationTitle("Vault")
            .onAppear { refreshDiscoveredVaults() }
            .toolbar {
                if showDismissToolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 360)
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .background(MacAppTheme.primaryBackground)
        .sheet(isPresented: $showDeleteSheet) {
            NavigationStack {
                Form {
                    Section {
                        if vaultManager.activeConfiguration?.backend == .googleDrive {
                            Toggle("Also delete folder from Google Drive", isOn: $deleteRemoteDriveToo)
                        }
                    } footer: {
                        Text("Vault data is removed from this device. External folders you chose are not deleted.")
                    }
                }
                .navigationTitle("Delete vault")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showDeleteSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Delete", role: .destructive) {
                            showDeleteSheet = false
                            Task { await deleteCurrentVault() }
                        }
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 220)
        }
        .alert("Vault", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func revealCurrentVaultInFinder() {
        guard let backend = vaultManager.activeFolderBackend() else {
            alertMessage = "Could not locate the vault folder."
            return
        }
        let url = backend.vaultRoot
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func refreshDiscoveredVaults() {
        discoveredVaults = vaultManager.discoverLocalMirrorVaults()
    }

    private func openDiscovered(_ summary: DiscoveredVaultSummary) async {
        await setBusy {
            try await vaultManager.openDiscoveredVault(summary)
            refreshDiscoveredVaults()
        }
    }

    private func openRemoteDriveVault(_ summary: DiscoveredRemoteGoogleDriveVaultSummary) async {
        await setBusy {
            try await vaultManager.openRemoteGoogleDriveVault(summary)
            refreshDiscoveredVaults()
            remoteDriveVaults = try await vaultManager.discoverRemoteGoogleDriveVaults(accountEmail: summary.connectedAccountEmail)
            attemptedRemoteDriveDiscovery = true
        }
    }

    private func deleteCurrentVault() async {
        guard let id = vaultManager.activeConfiguration?.vaultId else { return }
        await setBusy {
            try await vaultManager.deleteVault(vaultId: id, deleteRemoteDriveFolder: deleteRemoteDriveToo)
            deleteRemoteDriveToo = false
            refreshDiscoveredVaults()
        }
    }

    private func backendTitle(_ k: VaultBackendKind) -> String {
        switch k {
        case .local: return "On device"
        case .externalFolder: return "External folder"
        case .googleDrive: return "Google Drive"
        }
    }

    @MainActor
    private func setBusy(_ work: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func createLocalVault() async {
        await setBusy {
            try await vaultManager.createLocalVault(displayName: "Local vault")
            await vaultManager.performLifecycleSync()
            refreshDiscoveredVaults()
        }
    }

    private func chooseExternalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose Vault Folder"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                Task { @MainActor in
                    await setBusy {
                        try await vaultManager.setExternalVault(bookmarkData: bookmark, displayName: url.lastPathComponent)
                        await vaultManager.performLifecycleSync()
                        refreshDiscoveredVaults()
                    }
                }
            } catch {
                Task { @MainActor in alertMessage = error.localizedDescription }
            }
        }
    }

    private func createDriveVault() async {
        await setBusy {
            try await GmailAPIService.shared.requestGoogleDriveFileScope(presentingWindow: NSApp.keyWindow)
            try await vaultManager.createGoogleDriveVaultAfterScopeGranted(displayName: "Empty My Inbox Vault", accountEmail: nil)
            refreshDiscoveredVaults()
        }
    }

    private func discoverRemoteDriveVaults() async {
        await setBusy {
            try await GmailAPIService.shared.requestGoogleDriveFileScope(presentingWindow: NSApp.keyWindow)
            remoteDriveVaults = try await vaultManager.discoverRemoteGoogleDriveVaults()
            attemptedRemoteDriveDiscovery = true
        }
    }
}
