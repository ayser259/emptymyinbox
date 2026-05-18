//
//  ConfigureVaultPanel.swift
//  EmptyMyInboxShared
//
//  Configure Vault UI: open an existing mirror or create a new vault (local / folder / Drive).
//

import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if os(iOS)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Primary setup surface when no vault is active: open a discovered vault or create one.
public struct ConfigureVaultPanel: View {
    @ObservedObject private var vaultManager = VaultManager.shared

    @State private var busy = false
    @State private var alertMessage: String?
    @State private var discoveredVaults: [DiscoveredVaultSummary] = []
    @State private var remoteDriveVaults: [DiscoveredRemoteGoogleDriveVaultSummary] = []
    @State private var attemptedRemoteDriveDiscovery = false
    #if os(iOS)
    @State private var pickFolder = false
    #endif

    public init() {}

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

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Configure Vault")
                    .font(.title2.weight(.semibold))
                Text("Open a vault already on this device or in Google Drive, or create a new one so you know where data is saved.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            List {
                Section {
                    if openableVaults.isEmpty {
                        Text("No vault mirrors on this device yet. Create a new vault below, or find one in Google Drive.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(openableVaults) { summary in
                        Button {
                            Task { await openDiscovered(summary) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.displayName ?? summary.vaultId)
                                    .foregroundStyle(.primary)
                                Text(backendTitle(summary.backendKind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                } header: {
                    Text("Open an existing vault")
                } footer: {
                    Text("Vaults listed here are already stored under this app’s local storage. Opening one makes it active.")
                }

                Section {
                    Button {
                        Task { await discoverRemoteDriveVaults() }
                    } label: {
                        Label("Find Google Drive vaults", systemImage: "magnifyingglass")
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
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }

                    if attemptedRemoteDriveDiscovery && remoteDriveVaults.isEmpty {
                        Text("No Google Drive vaults found for the signed-in account.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if attemptedRemoteDriveDiscovery && openableRemoteDriveVaults.isEmpty && !remoteDriveVaults.isEmpty {
                        Text("The vault on Drive is already active on this device.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Google Drive")
                } footer: {
                    Text("Searches your Google account for vault folders. Each device keeps a local mirror.")
                }

                Section {
                    Button {
                        Task { await createLocalVault() }
                    } label: {
                        Label("New local vault", systemImage: "folder.badge.plus")
                    }
                    .disabled(busy)

                    #if os(iOS)
                    Button {
                        pickFolder = true
                    } label: {
                        Label("Use folder (iCloud Drive, Files…)", systemImage: "folder")
                    }
                    .disabled(busy)
                    #elseif os(macOS)
                    Button {
                        chooseExternalFolder()
                    } label: {
                        Label("Choose folder…", systemImage: "folder")
                    }
                    .disabled(busy)
                    #endif

                    Button {
                        Task { await createDriveVault() }
                    } label: {
                        Label("New Google Drive vault", systemImage: "externaldrive")
                    }
                    .disabled(busy)
                } header: {
                    Text("Create a new vault")
                } footer: {
                    Text("Local vaults stay on this device. A folder vault syncs via the system. A Drive vault uses the Google Drive API with your signed-in Google account.")
                }
            }
            #if os(macOS)
            .listStyle(.sidebar)
            #else
            .listStyle(.insetGrouped)
            #endif
            .frame(minHeight: 280)
            #if os(iOS)
            .scrollContentBackground(.hidden)
            #endif
        }
        .onAppear { refreshDiscoveredVaults() }
        .alert("Vault", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        #if os(iOS)
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
                    let bookmarkOpts: URL.BookmarkCreationOptions = []
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
        #endif
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
        #if os(iOS)
        guard let vc = UIApplication.emptyMyInbox_topPresentedViewController() else {
            alertMessage = "Could not present Google permission UI."
            return
        }
        await setBusy {
            try await GmailAPIService.shared.requestGoogleDriveFileScope(presentingViewController: vc)
            try await vaultManager.createGoogleDriveVaultAfterScopeGranted(displayName: "Empty My Inbox Vault", accountEmail: nil)
            refreshDiscoveredVaults()
        }
        #elseif os(macOS)
        await setBusy {
            try await GmailAPIService.shared.requestGoogleDriveFileScope(presentingWindow: NSApp.keyWindow)
            try await vaultManager.createGoogleDriveVaultAfterScopeGranted(displayName: "Empty My Inbox Vault", accountEmail: nil)
            refreshDiscoveredVaults()
        }
        #endif
    }

    private func discoverRemoteDriveVaults() async {
        #if os(iOS)
        guard let vc = UIApplication.emptyMyInbox_topPresentedViewController() else {
            alertMessage = "Could not present Google permission UI."
            return
        }
        await setBusy {
            try await GmailAPIService.shared.requestGoogleDriveFileScope(presentingViewController: vc)
            remoteDriveVaults = try await vaultManager.discoverRemoteGoogleDriveVaults()
            attemptedRemoteDriveDiscovery = true
        }
        #elseif os(macOS)
        await setBusy {
            try await GmailAPIService.shared.requestGoogleDriveFileScope(presentingWindow: NSApp.keyWindow)
            remoteDriveVaults = try await vaultManager.discoverRemoteGoogleDriveVaults()
            attemptedRemoteDriveDiscovery = true
        }
        #endif
    }

    #if os(macOS)
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
    #endif
}

#if os(iOS)
extension UIApplication {
    /// Best-effort presenter for Google Sign-In / Drive scope sheets from shared UI.
    static func emptyMyInbox_topPresentedViewController() -> UIViewController? {
        guard let scene = shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene.windows.first?.rootViewController
        else { return nil }
        return root.emptyMyInbox_topPresented()
    }
}

private extension UIViewController {
    func emptyMyInbox_topPresented() -> UIViewController {
        if let presented = presentedViewController {
            return presented.emptyMyInbox_topPresented()
        }
        if let nav = self as? UINavigationController, let visible = nav.visibleViewController {
            return visible.emptyMyInbox_topPresented()
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.emptyMyInbox_topPresented()
        }
        return self
    }
}
#endif
