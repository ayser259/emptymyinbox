//
//  VaultManager.swift
//  EmptyMyInboxShared
//
//  Active vault selection, folder backend, CRUD helpers, and lifecycle sync.
//

import Combine
import Foundation

@MainActor
public final class VaultManager: ObservableObject {
    public static let shared = VaultManager()

    @Published public private(set) var activeConfiguration: VaultActiveConfiguration?
    @Published public private(set) var lastSyncErrorMessage: String?
    @Published public private(set) var lastSuccessfulSyncAt: Date?

    private var folderBackend: (any VaultFolderBackend)?
    private var isSyncing = false

    private init() {}

    // MARK: - Lifecycle

    /// Load saved vault or create a default local vault.
    public func reloadFromPreferences() async {
        let config = await VaultSettingsStore.shared.activeConfiguration()
        await applyConfiguration(config)
        if config == nil {
            await createDefaultLocalVaultIfNeeded()
        } else {
            try? await runMigrationIfPossible()
        }
    }

    private func createDefaultLocalVaultIfNeeded() async {
        let current = await VaultSettingsStore.shared.activeConfiguration()
        guard current == nil else { return }
        do {
            try await createLocalVault(displayName: "Default vault")
        } catch {
            logError("Vault: default local vault failed: \(error)", category: "Vault")
        }
    }

    private func applyConfiguration(_ config: VaultActiveConfiguration?) async {
        activeConfiguration = config
        folderBackend = nil
        guard let config else { return }
        do {
            switch config.backend {
            case .local:
                folderBackend = VaultLocalFolderBackend(vaultRoot: VaultLocalFolderBackend.localRoot(forVaultId: config.vaultId))
            case .externalFolder:
                guard let data = config.securityScopedBookmarkData else {
                    logWarning("Vault: external vault missing bookmark", category: "Vault")
                    return
                }
                folderBackend = try VaultExternalFolderBackend(bookmarkData: data)
            case .googleDrive:
                folderBackend = VaultLocalFolderBackend(vaultRoot: VaultLocalFolderBackend.localRoot(forVaultId: config.vaultId))
            }
        } catch {
            logError("Vault: backend init failed: \(error)", category: "Vault")
        }
    }

    public func activeFolderBackend() -> (any VaultFolderBackend)? {
        folderBackend
    }

    // MARK: - Create / switch vault

    public func createLocalVault(displayName: String?) async throws {
        let id = UUID().uuidString
        let config = VaultActiveConfiguration(vaultId: id, backend: .local, displayName: displayName)
        let backend = VaultLocalFolderBackend(vaultRoot: VaultLocalFolderBackend.localRoot(forVaultId: id))
        try await backend.ensureStructure()
        try await VaultBootstrap.ensureManifestIfMissing(folderBackend: backend, configuration: config)
        await VaultSettingsStore.shared.setActiveConfiguration(config)
        folderBackend = backend
        activeConfiguration = config
        try await VaultMigrationImporter.importInterestProfileOnce(folderBackend: backend)
    }

    public func setExternalVault(bookmarkData: Data, displayName: String? = nil) async throws {
        let backend = try VaultExternalFolderBackend(bookmarkData: bookmarkData)
        var config = VaultActiveConfiguration(vaultId: UUID().uuidString, backend: .externalFolder, displayName: displayName)
        config.securityScopedBookmarkData = bookmarkData
        try await backend.ensureStructure()
        try await VaultBootstrap.ensureManifestIfMissing(folderBackend: backend, configuration: config)
        await VaultSettingsStore.shared.setActiveConfiguration(config)
        folderBackend = backend
        activeConfiguration = config
        try await VaultMigrationImporter.importInterestProfileOnce(folderBackend: backend)
    }

    /// Call after `GmailAPIService.requestGoogleDriveFileScope` succeeds. Creates a Drive folder and local mirror.
    public func createGoogleDriveVaultAfterScopeGranted(displayName: String?, accountEmail: String?) async throws {
        let account: GmailAccount
        if let email = accountEmail, let a = GmailAPIService.shared.getAccount(byEmail: email) {
            account = a
        } else if let first = GmailAPIService.shared.getAllAccounts().first {
            account = first
        } else {
            throw VaultError.noGoogleAccount
        }

        let token = try await GmailAPIService.shared.getValidAccessToken(for: account)
        let rootId = try await GoogleDriveVaultAPI.createFolder(
            name: displayName ?? "Empty My Inbox Vault",
            parentId: "root",
            accessToken: token
        )

        let id = UUID().uuidString
        let config = VaultActiveConfiguration(
            vaultId: id,
            backend: .googleDrive,
            displayName: displayName,
            driveRootFolderId: rootId,
            driveAccountEmail: account.email
        )
        let backend = VaultLocalFolderBackend(vaultRoot: VaultLocalFolderBackend.localRoot(forVaultId: id))
        try await backend.ensureStructure()
        try await VaultBootstrap.ensureManifestIfMissing(folderBackend: backend, configuration: config)
        await VaultSettingsStore.shared.setActiveConfiguration(config)
        folderBackend = backend
        activeConfiguration = config
        try await VaultMigrationImporter.importInterestProfileOnce(folderBackend: backend)
        try await VaultSyncCoordinator.syncGoogleDriveVault(configuration: config, folderBackend: backend, accessToken: token)
        lastSuccessfulSyncAt = Date()
        lastSyncErrorMessage = nil
        NotificationCenter.default.post(name: .vaultDidSync, object: nil)
    }

    public func switchToLocalVault(vaultId: String, displayName: String? = nil) async throws {
        let config = VaultActiveConfiguration(vaultId: vaultId, backend: .local, displayName: displayName)
        let backend = VaultLocalFolderBackend(vaultRoot: VaultLocalFolderBackend.localRoot(forVaultId: vaultId))
        try await backend.ensureStructure()
        try await VaultBootstrap.ensureManifestIfMissing(folderBackend: backend, configuration: config)
        await VaultSettingsStore.shared.setActiveConfiguration(config)
        folderBackend = backend
        activeConfiguration = config
        try await runMigrationIfPossible()
    }

    // MARK: - Sync

    public func performLifecycleSync() async {
        guard let config = activeConfiguration, let backend = folderBackend else { return }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            if config.backend == .googleDrive {
                guard let email = config.driveAccountEmail,
                      let acct = GmailAPIService.shared.getAccount(byEmail: email) else {
                    throw VaultError.noGoogleAccount
                }
                let token = try await GmailAPIService.shared.getValidAccessToken(for: acct)
                try await VaultSyncCoordinator.syncGoogleDriveVault(
                    configuration: config,
                    folderBackend: backend,
                    accessToken: token
                )
            }
            lastSuccessfulSyncAt = Date()
            lastSyncErrorMessage = nil
            NotificationCenter.default.post(name: .vaultDidSync, object: nil)
        } catch {
            lastSyncErrorMessage = error.localizedDescription
            logError("Vault sync: \(error)", category: "Vault")
        }
    }

    // MARK: - Calendar

    public func listCalendarEvents() async throws -> [VaultCalendarEventRecord] {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let prefix = "\(VaultLayout.calendarFolder)/\(VaultLayout.calendarEventsSubfolder)/"
        let paths = try await backend.listRelativeFilePaths()
            .filter { $0.hasPrefix(prefix) && $0.lowercased().hasSuffix(".json") }
        var out: [VaultCalendarEventRecord] = []
        for p in paths {
            guard let data = try? await backend.read(relativePath: p),
                  let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultCalendarEventRecord>.self, from: data)
            else { continue }
            out.append(env.payload)
        }
        return out.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    public func upsertCalendarEvent(_ event: VaultCalendarEventRecord) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = "\(VaultLayout.calendarFolder)/\(VaultLayout.calendarEventsSubfolder)/\(event.id).json"
        let existing = try? await backend.read(relativePath: path)
        let token = VaultLWWHelpers.nextWriteToken(existingData: existing)
        let envelope = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: event)
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: path, data: data)
    }

    public func deleteCalendarEvent(id: String) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = "\(VaultLayout.calendarFolder)/\(VaultLayout.calendarEventsSubfolder)/\(id).json"
        try await backend.remove(relativePath: path)
    }

    // MARK: - Action items

    public func listActionItems() async throws -> [VaultActionItemRecord] {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let prefix = "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsSubfolder)/"
        let paths = try await backend.listRelativeFilePaths()
            .filter { $0.hasPrefix(prefix) && $0.lowercased().hasSuffix(".json") }
        var out: [VaultActionItemRecord] = []
        for p in paths {
            guard let data = try? await backend.read(relativePath: p),
                  let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemRecord>.self, from: data)
            else { continue }
            out.append(env.payload)
        }
        return out.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func upsertActionItem(_ item: VaultActionItemRecord) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsSubfolder)/\(item.id).json"
        let existing = try? await backend.read(relativePath: path)
        let token = VaultLWWHelpers.nextWriteToken(existingData: existing)
        let envelope = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: item)
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: path, data: data)
    }

    public func deleteActionItem(id: String) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsSubfolder)/\(id).json"
        try await backend.remove(relativePath: path)
    }

    // MARK: - Migration

    private func runMigrationIfPossible() async throws {
        guard let backend = folderBackend else { return }
        try await VaultMigrationImporter.importInterestProfileOnce(folderBackend: backend)
    }
}
