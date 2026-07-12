//
//  VaultManager.swift
//  ProjectJadeShared
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

    /// Load saved vault from preferences. Does **not** create a vault automatically — the user must choose storage in Vault settings.
    public func reloadFromPreferences() async {
        let config = await VaultSettingsStore.shared.activeConfiguration()
        await applyConfiguration(config)
        if config != nil {
            try? await runMigrationIfPossible()
        }
    }

    /// Deletes `Application Support/…/Vaults/<vaultId>/` if it exists (on-device mirrors for `.local` and `.googleDrive`).
    /// Does not remove a user-chosen external-folder vault path.
    public func removeLocalMirrorDirectoryIfPresent(vaultId: String) async {
        let root = VaultLocalFolderBackend.localRoot(forVaultId: vaultId)
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return }
        do {
            try fm.removeItem(at: root)
            logInfo("Vault: removed on-device mirror for \(vaultId)", category: "Vault")
        } catch {
            logError("Vault: failed to remove on-device mirror: \(error)", category: "Vault")
        }
        objectWillChange.send()
    }

    /// Clears the active vault when its owner email no longer matches any signed-in Google account (e.g. switched accounts without clearing prefs).
    public func detachActiveVaultIfOwnerNotAmongConnectedAccounts() async {
        let accounts = GmailAPIService.shared.getAllAccounts()
        guard !accounts.isEmpty else { return }
        guard let config = await VaultSettingsStore.shared.activeConfiguration() else { return }
        guard let owner = config.resolvedOwnerEmail else { return }
        let stillConnected = accounts.contains { $0.email.caseInsensitiveCompare(owner) == .orderedSame }
        guard !stillConnected else { return }
        let vaultId = config.vaultId
        await VaultSettingsStore.shared.clearActiveConfiguration()
        await reloadFromPreferences()
        await removeLocalMirrorDirectoryIfPresent(vaultId: vaultId)
        logInfo("Vault: detached active vault (owner \(owner) not among connected accounts)", category: "Vault")
        NotificationCenter.default.post(name: .vaultDidSync, object: nil)
    }

    /// Whether a vault is selected and the folder backend is ready (e.g. external-folder vault has a valid bookmark).
    public var isVaultReady: Bool {
        activeConfiguration != nil && folderBackend != nil
    }

    /// Removes all on-device vault mirrors under `Application Support/…/ProjectJade/Vaults/` (local + Google Drive mirrors), clears vault preferences, and resets in-memory state.
    ///
    /// Call when the last Google account signs out so task files, labels, and projects stored in those mirrors are removed from this device.
    /// Does **not** delete files inside a user-chosen external-folder vault (only disconnects by clearing preferences).
    public func purgeAllLocalVaultMirrorsAndReset() async {
        let fm = FileManager.default
        let vaultsRoot = VaultLocalFolderBackend.defaultVaultsDirectory()
        if fm.fileExists(atPath: vaultsRoot.path) {
            do {
                try fm.removeItem(at: vaultsRoot)
            } catch {
                logError("Vault: failed to remove vault mirrors directory: \(error)", category: "Vault")
            }
        }
        _ = VaultLocalFolderBackend.defaultVaultsDirectory()
        await VaultSettingsStore.shared.clearActiveConfiguration()
        activeConfiguration = nil
        folderBackend = nil
        lastSyncErrorMessage = nil
        lastSuccessfulSyncAt = nil
        objectWillChange.send()
        logInfo("Vault: purged local vault mirrors and reset preferences", category: "Vault")
        NotificationCenter.default.post(name: .vaultDidSync, object: nil)
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
        objectWillChange.send()
    }

    public func activeFolderBackend() -> (any VaultFolderBackend)? {
        folderBackend
    }

    // MARK: - Create / switch vault

    private func defaultVaultOwnerEmail() -> String? {
        GmailAPIService.shared.getAllAccounts().first?.email
    }

    public func createLocalVault(displayName: String?) async throws {
        let id = UUID().uuidString
        let config = VaultActiveConfiguration(
            vaultId: id,
            backend: .local,
            displayName: displayName,
            ownerAccountEmail: defaultVaultOwnerEmail()
        )
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
        var config = VaultActiveConfiguration(
            vaultId: UUID().uuidString,
            backend: .externalFolder,
            displayName: displayName,
            ownerAccountEmail: defaultVaultOwnerEmail()
        )
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
        let account = try resolveGoogleDriveAccount(preferredEmail: accountEmail)
        let token = try await GmailAPIService.shared.getValidAccessToken(for: account)
        let rootId = try await GoogleDriveVaultAPI.createFolder(
            name: displayName ?? AppearanceSettingsStore.shared.resolvedVaultDisplayName,
            parentId: "root",
            accessToken: token
        )

        let id = UUID().uuidString
        let config = VaultActiveConfiguration(
            vaultId: id,
            backend: .googleDrive,
            displayName: displayName,
            driveRootFolderId: rootId,
            driveAccountEmail: account.email,
            ownerAccountEmail: account.email
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

    public func discoverRemoteGoogleDriveVaults(accountEmail: String? = nil) async throws -> [DiscoveredRemoteGoogleDriveVaultSummary] {
        await GmailAPIService.shared.restoreGoogleSignInSessionIfNeeded()
        let account = try resolveGoogleDriveAccount(preferredEmail: accountEmail)
        let token = try await GmailAPIService.shared.getValidAccessToken(for: account)
        return try await GoogleDriveVaultAPI.discoverVaultsInRoot(
            accessToken: token,
            connectedAccountEmail: account.email
        )
    }

    public func switchToLocalVault(vaultId: String, displayName: String? = nil) async throws {
        let config = VaultActiveConfiguration(
            vaultId: vaultId,
            backend: .local,
            displayName: displayName,
            ownerAccountEmail: defaultVaultOwnerEmail()
        )
        let backend = VaultLocalFolderBackend(vaultRoot: VaultLocalFolderBackend.localRoot(forVaultId: vaultId))
        try await backend.ensureStructure()
        try await VaultBootstrap.ensureManifestIfMissing(folderBackend: backend, configuration: config)
        try await VaultBootstrap.mergeManifestMetadataFromConfiguration(folderBackend: backend, configuration: config)
        await VaultSettingsStore.shared.setActiveConfiguration(config)
        folderBackend = backend
        activeConfiguration = config
        try await runMigrationIfPossible()
    }

    /// Vaults stored under Application Support `Vaults/` (on-device local and Google Drive mirrors).
    public func discoverLocalMirrorVaults() -> [DiscoveredVaultSummary] {
        VaultDiscovery.discoverLocalMirrorVaults()
    }

    /// Activates a discovered mirror vault. Only `.local` and `.googleDrive` are supported; external folders must use the folder picker again.
    public func openDiscoveredVault(_ summary: DiscoveredVaultSummary) async throws {
        switch summary.backendKind {
        case .local:
            try await switchToLocalVault(vaultId: summary.vaultId, displayName: summary.displayName)
            await performLifecycleSync()
        case .googleDrive:
            try await switchToGoogleDriveVault(
                vaultId: summary.vaultId,
                displayName: summary.displayName,
                driveRootFolderId: summary.driveRootFolderId,
                driveAccountEmail: summary.driveAccountEmail
            )
            await performLifecycleSync()
        case .externalFolder:
            throw VaultError.cannotOpenDriveVault
        }
    }

    public func openRemoteGoogleDriveVault(_ summary: DiscoveredRemoteGoogleDriveVaultSummary) async throws {
        try await switchToGoogleDriveVault(
            vaultId: summary.vaultId,
            displayName: summary.displayName,
            driveRootFolderId: summary.driveRootFolderId,
            driveAccountEmail: summary.connectedAccountEmail
        )
        await performLifecycleSync()
    }

    private func switchToGoogleDriveVault(
        vaultId: String,
        displayName: String?,
        driveRootFolderId: String?,
        driveAccountEmail: String?
    ) async throws {
        guard let rootId = driveRootFolderId, let email = driveAccountEmail else {
            throw VaultError.cannotOpenDriveVault
        }
        guard GmailAPIService.shared.getAccount(byEmail: email) != nil else {
            throw VaultError.noGoogleAccount
        }
        let config = VaultActiveConfiguration(
            vaultId: vaultId,
            backend: .googleDrive,
            displayName: displayName,
            driveRootFolderId: rootId,
            driveAccountEmail: email,
            ownerAccountEmail: email
        )
        let backend = VaultLocalFolderBackend(vaultRoot: VaultLocalFolderBackend.localRoot(forVaultId: vaultId))
        try await backend.ensureStructure()
        try await VaultBootstrap.ensureManifestIfMissing(folderBackend: backend, configuration: config)
        try await VaultBootstrap.mergeManifestMetadataFromConfiguration(folderBackend: backend, configuration: config)
        await VaultSettingsStore.shared.setActiveConfiguration(config)
        folderBackend = backend
        activeConfiguration = config
        try await runMigrationIfPossible()
    }

    private func resolveGoogleDriveAccount(preferredEmail: String?) throws -> GmailAccount {
        if let email = preferredEmail, let account = GmailAPIService.shared.getAccount(byEmail: email) {
            return account
        }
        if let first = GmailAPIService.shared.getAllAccounts().first {
            return first
        }
        throw VaultError.noGoogleAccount
    }

    /// Removes a vault mirror under `Vaults/<vaultId>/`, or disconnects an external-folder vault from the app (does not delete the user’s files).
    /// - Parameter deleteRemoteDriveFolder: When true, attempts to trash the Drive root folder after the local mirror is removed (requires a signed-in Gmail account).
    public func deleteVault(vaultId: String, deleteRemoteDriveFolder: Bool = false) async throws {
        if activeConfiguration?.vaultId == vaultId, activeConfiguration?.backend == .externalFolder {
            await VaultSettingsStore.shared.clearActiveConfiguration()
            await reloadFromPreferences()
            return
        }

        let root = VaultLocalFolderBackend.localRoot(forVaultId: vaultId)
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else {
            throw VaultError.vaultNotFound
        }

        let manifestURL = root.appendingPathComponent(VaultLayout.manifestFileName)
        let manifestData = try? Data(contentsOf: manifestURL)
        let manifest = manifestData.flatMap { try? VaultJSON.decoder().decode(VaultManifest.self, from: $0) }

        let wasActive = activeConfiguration?.vaultId == vaultId
        try fm.removeItem(at: root)

        if wasActive {
            await VaultSettingsStore.shared.clearActiveConfiguration()
            await reloadFromPreferences()
        }

        if deleteRemoteDriveFolder,
           manifest?.backendKind == .googleDrive,
           let folderId = manifest?.driveRootFolderId,
           let email = manifest?.driveAccountEmail,
           let account = GmailAPIService.shared.getAccount(byEmail: email) {
            do {
                let token = try await GmailAPIService.shared.getValidAccessToken(for: account)
                try await GoogleDriveVaultAPI.deleteFile(fileId: folderId, accessToken: token)
            } catch {
                throw VaultError.ioFailed(
                    "Removed from this device, but Google Drive could not delete the folder: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Sync

    /// Google Drive vaults: pull remote changes then push local updates. Other backends: no network sync.
    /// - Parameter postNotification: When `false`, skips `vaultDidSync` so the caller can reload UI without duplicate work.
    public func performLifecycleSync(postNotification: Bool = true) async {
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
            if postNotification {
                NotificationCenter.default.post(name: .vaultDidSync, object: nil)
            }
        } catch {
            lastSyncErrorMessage = error.localizedDescription
            logError("Vault sync: \(error)", category: "Vault")
        }
    }


    // MARK: - Stories & Brief

    /// Reads the stories feed aggregate from the vault, if present.
    public func loadStoriesFeedFromVault() async throws -> VaultStoriesFeedPayload? {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = VaultLayout.storiesFeedAggregatePath
        guard let data = try? await backend.read(relativePath: path) else {
            return nil
        }
        guard let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultStoriesFeedPayload>.self, from: data) else {
            return nil
        }
        return env.payload
    }

    /// Writes the full stories feed snapshot (overwrites `Stories/stories_feed.json`).
    public func saveStoriesFeedToVault(_ payload: VaultStoriesFeedPayload) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        try await backend.ensureStructure()
        let path = VaultLayout.storiesFeedAggregatePath
        let existing = try? await backend.read(relativePath: path)
        let token = VaultLWWHelpers.nextWriteToken(existingData: existing)
        let envelope = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: payload)
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: path, data: data)
    }

    /// Writes bookmarked cards only (`Stories/bookmarked_stories.json`).
    public func saveBookmarkedStoriesMirrorToVault(_ payload: VaultStoriesBookmarkedPayload) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        try await backend.ensureStructure()
        let path = VaultLayout.storiesBookmarkedAggregatePath
        let existing = try? await backend.read(relativePath: path)
        let token = VaultLWWHelpers.nextWriteToken(existingData: existing)
        let envelope = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: payload)
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: path, data: data)
    }

    /// Reads the daily brief from the vault, if present.
    public func loadDailyBriefFromVault() async throws -> DailyBriefingPayload? {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = VaultLayout.briefDailyAggregatePath
        guard let data = try? await backend.read(relativePath: path) else {
            return nil
        }
        guard let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<DailyBriefingPayload>.self, from: data) else {
            return nil
        }
        return env.payload
    }

    /// Overwrites `Brief/daily_brief.json` with the latest briefing.
    public func saveDailyBriefToVault(_ payload: DailyBriefingPayload) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        try await backend.ensureStructure()
        let path = VaultLayout.briefDailyAggregatePath
        let existing = try? await backend.read(relativePath: path)
        let token = VaultLWWHelpers.nextWriteToken(existingData: existing)
        let envelope = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: payload)
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: path, data: data)
    }


    // MARK: - Migration

    private func runMigrationIfPossible() async throws {
        guard let backend = folderBackend else { return }
        try await VaultMigrationImporter.importInterestProfileOnce(folderBackend: backend)
    }
}
