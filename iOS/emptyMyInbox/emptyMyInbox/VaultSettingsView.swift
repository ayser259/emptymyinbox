//
//  VaultSettingsView.swift
//  emptyMyInbox
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import EmptyMyInboxShared

struct VaultSettingsView: View {
    @ObservedObject private var vaultManager = VaultManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var pickFolder = false
    @State private var busy = false
    @State private var alertMessage: String?
    @State private var discoveredVaults: [DiscoveredVaultSummary] = []
    @State private var remoteDriveVaults: [DiscoveredRemoteGoogleDriveVaultSummary] = []
    @State private var attemptedRemoteDriveDiscovery = false
    @State private var showDeleteSheet = false
    @State private var deleteRemoteDriveToo = false

    /// Vaults you can switch to (excludes the one already active so rows stay tappable).
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
                    LabeledContent("Backend") {
                        Text(backendTitle(c.backend))
                    }
                    if let name = c.displayName, !name.isEmpty {
                        LabeledContent("Name") { Text(name) }
                    }
                    if let email = c.driveAccountEmail {
                        LabeledContent("Drive account") { Text(email) }
                    }
                } else {
                    Text("No vault loaded")
                        .secondaryText()
                }

                if let err = vaultManager.lastSyncErrorMessage {
                    Text(err)
                        .font(AppTheme.caption)
                        .foregroundColor(.orange)
                }
                if let t = vaultManager.lastSuccessfulSyncAt {
                    LabeledContent("Last sync") {
                        Text(t.formatted(date: .abbreviated, time: .shortened))
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
                                .foregroundColor(.primary)
                            Text(backendTitle(summary.backendKind))
                                .font(AppTheme.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
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
                        .secondaryText()
                } else if openableVaults.isEmpty {
                    Text("No other vaults to open. The active vault is already selected. Use Switch vault below to create another vault on this device.")
                        .secondaryText()
                }
            } header: {
                Text("Open vault")
            } footer: {
                Text("These are vault mirrors already stored on this device under the app’s local storage. Only one vault is active at a time—opening one replaces the current one. To use an external folder vault again, choose it with “Use folder”.")
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
                                .foregroundColor(.primary)
                            Text(summary.connectedAccountEmail)
                                .font(AppTheme.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
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
                        .secondaryText()
                } else if attemptedRemoteDriveDiscovery && openableRemoteDriveVaults.isEmpty && !remoteDriveVaults.isEmpty {
                    Text("The discovered Google Drive vault is already active on this device.")
                        .secondaryText()
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
                    pickFolder = true
                } label: {
                    Label("Use folder (iCloud Drive, Files…)", systemImage: "folder")
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
                Text("Creating or switching replaces the active vault. Local vaults stay on this device. A folder vault syncs via the system (e.g. Google Drive in Files). A Drive vault uses the Google Drive API with your signed-in Gmail account.")
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
                Text("Removes this vault from the app on this device. Files inside a chosen external folder are not deleted.")
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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshDiscoveredVaults() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showDeleteSheet) {
            NavigationStack {
                Form {
                    Section {
                        if vaultManager.activeConfiguration?.backend == .googleDrive {
                            Toggle("Also delete folder from Google Drive", isOn: $deleteRemoteDriveToo)
                        }
                    } footer: {
                        Text("Vault data is removed from this device. External folders you picked in Files are not deleted.")
                    }
                }
                .navigationTitle("Delete vault")
                .navigationBarTitleDisplayMode(.inline)
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
            .presentationDetents([.medium])
        }
        .fileImporter(
            isPresented: $pickFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                do {
                    #if os(iOS)
                    let bookmarkOpts: URL.BookmarkCreationOptions = []
                    #else
                    let bookmarkOpts: URL.BookmarkCreationOptions = [.withSecurityScope]
                    #endif
                    let bookmark = try url.bookmarkData(options: bookmarkOpts, includingResourceValuesForKeys: nil, relativeTo: nil)
                    Task {
                        await setBusy {
                            try await vaultManager.setExternalVault(bookmarkData: bookmark, displayName: url.lastPathComponent)
                            await vaultManager.performLifecycleSync()
                            refreshDiscoveredVaults()
                        }
                    }
                } catch {
                    alertMessage = error.localizedDescription
                }
            case .failure(let e):
                alertMessage = e.localizedDescription
            }
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

    private func createDriveVault() async {
        guard let vc = UIApplication.topViewControllerForPresentation() else {
            alertMessage = "Could not present Google permission UI."
            return
        }
        await setBusy {
            try await GmailAPIService.shared.requestGoogleDriveFileScope(presentingViewController: vc)
            try await vaultManager.createGoogleDriveVaultAfterScopeGranted(displayName: "Empty My Inbox Vault", accountEmail: nil)
            refreshDiscoveredVaults()
        }
    }

    private func discoverRemoteDriveVaults() async {
        guard let vc = UIApplication.topViewControllerForPresentation() else {
            alertMessage = "Could not present Google permission UI."
            return
        }
        await setBusy {
            try await GmailAPIService.shared.requestGoogleDriveFileScope(presentingViewController: vc)
            remoteDriveVaults = try await vaultManager.discoverRemoteGoogleDriveVaults()
            attemptedRemoteDriveDiscovery = true
        }
    }
}

extension UIApplication {
    static func topViewControllerForPresentation() -> UIViewController? {
        guard let scene = shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene.windows.first?.rootViewController
        else { return nil }
        return root.vault_topPresented()
    }
}

private extension UIViewController {
    func vault_topPresented() -> UIViewController {
        if let presented = presentedViewController {
            return presented.vault_topPresented()
        }
        if let nav = self as? UINavigationController, let visible = nav.visibleViewController {
            return visible.vault_topPresented()
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.vault_topPresented()
        }
        return self
    }
}
