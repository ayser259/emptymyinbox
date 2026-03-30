//
//  MacVaultSettingsView.swift
//  emptymyinboxMacApp
//

import AppKit
import SwiftUI
import EmptyMyInboxShared

struct MacVaultSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vaultManager = VaultManager.shared

    @State private var busy = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .frame(minWidth: 420, minHeight: 360)
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
        }
    }
}
