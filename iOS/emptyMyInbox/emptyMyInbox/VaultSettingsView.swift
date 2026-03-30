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

    @State private var pickFolder = false
    @State private var busy = false
    @State private var alertMessage: String?

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
            } header: {
                Text("Current vault")
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
                Text("Local vaults stay on this device. A folder vault syncs via the system (e.g. Google Drive in Files). A Drive vault uses the Google Drive API with your signed-in Gmail account.")
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
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
