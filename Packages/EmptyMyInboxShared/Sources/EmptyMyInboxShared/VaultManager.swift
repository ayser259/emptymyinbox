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

    /// Load saved vault from preferences. Does **not** create a vault automatically — the user must choose storage in Vault settings.
    public func reloadFromPreferences() async {
        let config = await VaultSettingsStore.shared.activeConfiguration()
        await applyConfiguration(config)
        if config != nil {
            try? await runMigrationIfPossible()
            try? await self.purgeCompletedActionItemsOlderThan(days: 30)
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

    /// Removes all on-device vault mirrors under `Application Support/…/emptyMyInbox/Vaults/` (local + Google Drive mirrors), clears vault preferences, and resets in-memory state.
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
            try? await self.purgeCompletedActionItemsOlderThan(days: 30)
            if postNotification {
                NotificationCenter.default.post(name: .vaultDidSync, object: nil)
            }
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

    // MARK: - Action items

    /// Active (incomplete) items only — primary UI lists.
    public func listActionItems() async throws -> [VaultActionItemRecord] {
        let raw = try await loadActiveActionItemsUnsorted()
        return ActionItemsFeatureModel.defaultSorted(raw)
    }

    public func listCompletedActionItems() async throws -> [VaultActionItemRecord] {
        let raw = try await loadCompletedActionItemsUnsorted()
        return raw.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Active items scheduled for `referenceDay` vs. everything else (still active).
    public func listActionItemsForToday(
        referenceDay: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> (scheduled: [VaultActionItemRecord], unscheduled: [VaultActionItemRecord]) {
        let all = try await listActionItems()
        let forDay = ActionItemsFeatureModel.itemsScheduledForCalendarDay(
            referenceDay: referenceDay,
            calendar: calendar,
            items: all
        )
        let ids = Set(forDay.map(\.id))
        let rest = all.filter { !ids.contains($0.id) }
        return (forDay, rest)
    }

    public func listActionItemsBySubject(_ subjectKey: String) async throws -> [VaultActionItemRecord] {
        let all = try await listActionItems()
        let defs = try await listContextDefinitions()
        return all.filter { ActionItemsFeatureModel.contextBucketKey(for: $0, definitions: defs) == subjectKey }
    }

    public func listActionItemSubjectGroups() async throws -> [(key: String, items: [VaultActionItemRecord])] {
        let all = try await loadActiveActionItemsUnsorted()
        let defs = try await listContextDefinitions()
        return ActionItemsFeatureModel.groupedBySubject(all, definitions: defs)
    }

    public func listActionItemsForCalendarRange(
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) async throws -> [VaultActionItemRecord] {
        let all = try await listActionItems()
        return ActionItemsFeatureModel.itemsScheduledInDateRange(
            start: start,
            end: end,
            calendar: calendar,
            items: all
        )
    }

    public func loadActionItem(id: String) async throws -> VaultActionItemRecord {
        let active = try await loadActiveActionItemsUnsorted()
        if let found = active.first(where: { $0.id == id }) { return found }
        let completed = try await loadCompletedActionItemsUnsorted()
        if let found = completed.first(where: { $0.id == id }) { return found }
        throw VaultError.actionItemNotFound(id)
    }

    /// Creates a child task with subject/type/priority and documentation fields copied from the parent (snapshot).
    public func createChildTask(fromParentId parentId: String, title: String) async throws -> VaultActionItemRecord {
        let all = try await loadAllActionItemsFromBothFoldersUnsorted()
        guard let parent = all.first(where: { $0.id == parentId }) else {
            throw VaultError.actionItemNotFound(parentId)
        }
        let now = Date()
        let child = VaultActionItemRecord(
            title: title,
            notes: nil,
            priority: parent.priority,
            urgency: parent.urgency,
            taskDescription: parent.taskDescription,
            contextNotes: parent.contextNotes,
            comments: [],
            parentTaskId: parentId,
            subjectLabel: parent.subjectLabel,
            contextId: parent.contextId,
            typeLabel: parent.typeLabel,
            typeId: parent.typeId,
            projectId: parent.projectId,
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
        try await upsertActionItem(child)
        return child
    }

    public func updateActionItemCompletion(id: String, isDone: Bool) async throws {
        var item = try await loadActionItem(id: id)
        item.isDone = isDone
        item.completedAt = isDone ? (item.completedAt ?? Date()) : nil
        try await upsertActionItem(item)
    }

    public func updateActionItemStarred(id: String, isStarred: Bool) async throws {
        var item = try await loadActionItem(id: id)
        item.isStarred = isStarred
        try await upsertActionItem(item)
    }

    public func upsertActionItem(_ item: VaultActionItemRecord) async throws {
        guard folderBackend != nil else { throw VaultError.notConfigured }
        var normalized = item
        if let p = normalized.priority {
            normalized.priority = min(4, max(0, p))
        }
        if let u = normalized.urgency {
            normalized.urgency = min(4, max(0, u))
        }
        if normalized.projectId == nil {
            let general = try await ensureGeneralProjectDefinition()
            normalized.projectId = general.id
        }
        if normalized.id.isEmpty {
            normalized.id = ULID.generate()
        }
        let (activeItems, activeData) = try await readActiveAggregateRaw()
        let (completedItems, completedData) = try await readCompletedAggregateRaw()
        let hadExisting = activeItems.contains(where: { $0.id == normalized.id })
            || completedItems.contains(where: { $0.id == normalized.id })
        if !hadExisting, normalized.createdAt == nil {
            normalized.createdAt = Date()
        }
        normalized.updatedAt = Date()
        var active = activeItems.filter { $0.id != normalized.id }
        var completed = completedItems.filter { $0.id != normalized.id }
        if normalized.isDone {
            completed.append(normalized)
        } else {
            active.append(normalized)
        }
        try await writeActiveAggregate(active, previousData: activeData)
        try await writeCompletedAggregate(completed, previousData: completedData)
    }

    public func deleteActionItem(id: String) async throws {
        let (activeItems, activeData) = try await readActiveAggregateRaw()
        let (completedItems, completedData) = try await readCompletedAggregateRaw()
        let active = activeItems.filter { $0.id != id }
        let completed = completedItems.filter { $0.id != id }
        try await writeActiveAggregate(active, previousData: activeData)
        try await writeCompletedAggregate(completed, previousData: completedData)
    }

    /// Deletes completed items whose `completedAt` is older than `days`.
    public func purgeCompletedActionItemsOlderThan(days: Int = 30, referenceDate: Date = Date()) async throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        let (completedItems, completedData) = try await readCompletedAggregateRaw()
        let kept = completedItems.filter { item in
            guard let completedAt = item.completedAt else { return true }
            return completedAt >= cutoff
        }
        try await writeCompletedAggregate(kept, previousData: completedData)
    }

    // MARK: - Context & type definitions (aggregate files)

    public func listContextDefinitions() async throws -> [VaultContextDefinition] {
        let (defs, _) = try await readContextDefinitionsAggregateRaw()
        return defs.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    /// Ensures a default `#Unspecified` context exists (grey accent) for new vaults.
    public func ensureDefaultContextDefinitions() async throws {
        let defs = try await listContextDefinitions()
        let has = defs.contains {
            ActionItemsFeatureModel.normalizedSubjectKey($0.name).lowercased()
                == ActionItemsFeatureModel.unspecifiedSubjectKey.lowercased()
        }
        guard !has else { return }
        try await upsertContextDefinition(
            VaultContextDefinition(
                name: ActionItemsFeatureModel.unspecifiedSubjectKey,
                accentColorHex: ContextAccentPalette.defaultGreyHex,
                sortOrder: -10_000
            )
        )
    }

    public func upsertContextDefinition(_ def: VaultContextDefinition) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        var (defs, existingData) = try await readContextDefinitionsAggregateRaw()
        var updated = def
        let now = Date()
        if updated.createdAt == nil { updated.createdAt = now }
        updated.updatedAt = now
        let normalizedName = ActionItemsFeatureModel.normalizedSubjectKey(updated.name).lowercased()
        if let i = defs.firstIndex(where: { $0.id == updated.id }) {
            defs[i] = updated
        } else if let i = defs.firstIndex(where: {
            ActionItemsFeatureModel.normalizedSubjectKey($0.name).lowercased() == normalizedName
        }) {
            updated.id = defs[i].id
            if updated.createdAt == nil {
                updated.createdAt = defs[i].createdAt
            }
            defs[i] = updated
        } else {
            defs.append(updated)
        }
        let token = VaultLWWHelpers.nextWriteToken(existingData: existingData)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: VaultContextDefinitionsFilePayload(definitions: defs)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsContextsAggregatePath, data: data)
    }

    public func listProjectDefinitions() async throws -> [VaultProjectDefinition] {
        let (defs, _) = try await readProjectDefinitionsAggregateRaw()
        return defs.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    @discardableResult
    public func ensureGeneralProjectDefinition() async throws -> VaultProjectDefinition {
        let defs = try await listProjectDefinitions()
        if let existing = defs.first(where: {
            ActionItemsFeatureModel.normalizedProjectKey($0.name).lowercased()
                == ActionItemsFeatureModel.generalProjectName.lowercased()
        }) {
            return existing
        }
        let general = VaultProjectDefinition(
            name: ActionItemsFeatureModel.generalProjectName,
            accentColorHex: ContextAccentPalette.defaultGreyHex,
            sortOrder: -10_000
        )
        try await upsertProjectDefinition(general)
        return general
    }

    public func upsertProjectDefinition(_ def: VaultProjectDefinition) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        var (defs, existingData) = try await readProjectDefinitionsAggregateRaw()
        var updated = def
        let now = Date()
        if updated.createdAt == nil { updated.createdAt = now }
        updated.updatedAt = now
        let normalizedName = ActionItemsFeatureModel.normalizedProjectKey(updated.name).lowercased()
        if let i = defs.firstIndex(where: { $0.id == updated.id }) {
            defs[i] = updated
        } else if let i = defs.firstIndex(where: {
            ActionItemsFeatureModel.normalizedProjectKey($0.name).lowercased() == normalizedName
        }) {
            updated.id = defs[i].id
            if updated.createdAt == nil {
                updated.createdAt = defs[i].createdAt
            }
            defs[i] = updated
        } else {
            defs.append(updated)
        }
        let token = VaultLWWHelpers.nextWriteToken(existingData: existingData)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: VaultProjectDefinitionsFilePayload(definitions: defs)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsProjectsAggregatePath, data: data)
    }

    public func deleteProjectDefinition(id: String) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let (defs, existingData) = try await readProjectDefinitionsAggregateRaw()
        let filtered = defs.filter { $0.id != id }
        let token = VaultLWWHelpers.nextWriteToken(existingData: existingData)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: VaultProjectDefinitionsFilePayload(definitions: filtered)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsProjectsAggregatePath, data: data)
    }

    public func deleteContextDefinition(id: String) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let (defs, existingData) = try await readContextDefinitionsAggregateRaw()
        let filtered = defs.filter { $0.id != id }
        let token = VaultLWWHelpers.nextWriteToken(existingData: existingData)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: VaultContextDefinitionsFilePayload(definitions: filtered)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsContextsAggregatePath, data: data)
    }

    /// Updates the saved project name. Tasks reference `projectId`, so they stay on the same project.
    public func renameProjectDefinition(id: String, newDisplayName: String) async throws {
        let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var defs = try await listProjectDefinitions()
        guard let idx = defs.firstIndex(where: { $0.id == id }) else { return }
        var def = defs[idx]
        def.name = trimmed
        def.updatedAt = Date()
        try await upsertProjectDefinition(def)
    }

    /// Moves every active and completed task off `projectId` onto `toProjectId`, then removes the project definition.
    public func deleteProjectMovingTasksToGeneral(projectId: String) async throws {
        let general = try await ensureGeneralProjectDefinition()
        guard projectId != general.id else { throw VaultError.cannotDeleteReservedDefinition }
        let active = try await loadActiveActionItemsUnsorted()
        let completed = try await loadCompletedActionItemsUnsorted()
        for item in active + completed where item.projectId == projectId {
            var m = item
            m.projectId = general.id
            try await upsertActionItem(m)
        }
        try await deleteProjectDefinition(id: projectId)
    }

    /// Renames a saved label (context) and updates `subjectLabel` on tasks that only matched the old name.
    public func renameContextDefinition(id: String, newDisplayName: String) async throws {
        let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let defs = try await listContextDefinitions()
        guard let def = defs.first(where: { $0.id == id }) else { return }
        let oldKey = ActionItemsFeatureModel.normalizedSubjectKey(def.name)
        var updated = def
        updated.name = trimmed
        updated.updatedAt = Date()
        try await upsertContextDefinition(updated)
        let active = try await loadActiveActionItemsUnsorted()
        let completed = try await loadCompletedActionItemsUnsorted()
        for item in active + completed {
            var m = item
            if m.contextId == id {
                m.subjectLabel = trimmed
                try await upsertActionItem(m)
            } else if m.contextId == nil && ActionItemsFeatureModel.normalizedSubjectKey(m.subjectLabel) == oldKey {
                m.subjectLabel = trimmed
                try await upsertActionItem(m)
            }
        }
    }

    /// Renames a label bucket that has **no** saved `VaultContextDefinition` (items only carry `subjectLabel`).
    public func renameLabelBucketItemOnly(oldSubjectKey: String, newDisplayName: String) async throws {
        let defs = try await listContextDefinitions()
        let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if defs.contains(where: { ActionItemsFeatureModel.normalizedSubjectKey($0.name) == oldSubjectKey }) {
            return
        }
        let active = try await loadActiveActionItemsUnsorted()
        let completed = try await loadCompletedActionItemsUnsorted()
        for item in active + completed {
            guard item.contextId == nil else { continue }
            guard ActionItemsFeatureModel.normalizedSubjectKey(item.subjectLabel) == oldSubjectKey else { continue }
            var m = item
            m.subjectLabel = trimmed
            try await upsertActionItem(m)
        }
    }

    /// Clears label/context for every task in `subjectKey`, then deletes the context definition when present.
    public func deleteLabelBucket(subjectKey: String) async throws {
        let defs = try await listContextDefinitions()
        let key = ActionItemsFeatureModel.normalizedSubjectKey(subjectKey)
        guard key != ActionItemsFeatureModel.unspecifiedSubjectKey else { throw VaultError.cannotDeleteReservedDefinition }
        let active = try await loadActiveActionItemsUnsorted()
        let completed = try await loadCompletedActionItemsUnsorted()
        for item in active + completed {
            guard ActionItemsFeatureModel.contextBucketKey(for: item, definitions: defs) == key else { continue }
            var m = item
            m.contextId = nil
            m.subjectLabel = nil
            try await upsertActionItem(m)
        }
        if let def = defs.first(where: { ActionItemsFeatureModel.normalizedSubjectKey($0.name) == key }) {
            try await deleteContextDefinition(id: def.id)
        }
    }

    // MARK: - Starred sidebar channels (Action Items)

    private func readStarredSidebarChannelsAggregateRaw() async throws -> (pins: [ActionItemsSidebarPin], data: Data?) {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = VaultLayout.actionItemsStarredChannelsAggregatePath
        guard let data = try? await backend.read(relativePath: path) else {
            return ([], nil)
        }
        guard let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultStarredSidebarChannelsPayload>.self, from: data) else {
            return ([], data)
        }
        return (env.payload.pins, data)
    }

    public func loadStarredSidebarChannels() async throws -> [ActionItemsSidebarPin] {
        let (pins, _) = try await readStarredSidebarChannelsAggregateRaw()
        return Self.uniqueSortedSidebarPins(pins)
    }

    public func saveStarredSidebarChannels(_ pins: [ActionItemsSidebarPin]) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let unique = Self.uniqueSortedSidebarPins(pins)
        let (_, existingData) = try await readStarredSidebarChannelsAggregateRaw()
        let token = VaultLWWHelpers.nextWriteToken(existingData: existingData)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: VaultStarredSidebarChannelsPayload(pins: unique)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsStarredChannelsAggregatePath, data: data)
    }

    private static func uniqueSortedSidebarPins(_ pins: [ActionItemsSidebarPin]) -> [ActionItemsSidebarPin] {
        var seen = Set<String>()
        var unique: [ActionItemsSidebarPin] = []
        for p in pins where seen.insert(p.sortKey).inserted {
            unique.append(p)
        }
        unique.sort { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
        return unique
    }

    public func listActionTypeDefinitions() async throws -> [VaultActionTypeDefinition] {
        let (defs, _) = try await readActionTypeDefinitionsAggregateRaw()
        return defs.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    public func upsertActionTypeDefinition(_ def: VaultActionTypeDefinition) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        var (defs, existingData) = try await readActionTypeDefinitionsAggregateRaw()
        var updated = def
        let now = Date()
        if updated.createdAt == nil { updated.createdAt = now }
        updated.updatedAt = now
        if let i = defs.firstIndex(where: { $0.id == updated.id }) {
            defs[i] = updated
        } else {
            defs.append(updated)
        }
        let token = VaultLWWHelpers.nextWriteToken(existingData: existingData)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: VaultActionTypeDefinitionsFilePayload(definitions: defs)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsTypesAggregatePath, data: data)
    }

    public func deleteActionTypeDefinition(id: String) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let (defs, existingData) = try await readActionTypeDefinitionsAggregateRaw()
        let filtered = defs.filter { $0.id != id }
        let token = VaultLWWHelpers.nextWriteToken(existingData: existingData)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: VaultActionTypeDefinitionsFilePayload(definitions: filtered)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsTypesAggregatePath, data: data)
    }

    // MARK: - Action item aggregate I/O

    private func readActiveAggregateRaw() async throws -> (items: [VaultActionItemRecord], data: Data?) {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = VaultLayout.actionItemsActiveAggregatePath
        guard let data = try? await backend.read(relativePath: path) else {
            return ([], nil)
        }
        guard let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemsFilePayload>.self, from: data) else {
            return ([], data)
        }
        return (env.payload.items, data)
    }

    private func readCompletedAggregateRaw() async throws -> (items: [VaultActionItemRecord], data: Data?) {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = VaultLayout.actionItemsCompletedAggregatePath
        guard let data = try? await backend.read(relativePath: path) else {
            return ([], nil)
        }
        guard let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemsFilePayload>.self, from: data) else {
            return ([], data)
        }
        return (env.payload.items, data)
    }

    private func writeActiveAggregate(_ items: [VaultActionItemRecord], previousData: Data?) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let token = VaultLWWHelpers.nextWriteToken(existingData: previousData)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: VaultActionItemsFilePayload(items: items)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsActiveAggregatePath, data: data)
    }

    private func writeCompletedAggregate(_ items: [VaultActionItemRecord], previousData: Data?) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let token = VaultLWWHelpers.nextWriteToken(existingData: previousData)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: VaultActionItemsFilePayload(items: items)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsCompletedAggregatePath, data: data)
    }

    private func loadActiveActionItemsUnsorted() async throws -> [VaultActionItemRecord] {
        let (items, _) = try await readActiveAggregateRaw()
        return items
    }

    private func loadCompletedActionItemsUnsorted() async throws -> [VaultActionItemRecord] {
        let (items, _) = try await readCompletedAggregateRaw()
        return items
    }

    private func loadAllActionItemsFromBothFoldersUnsorted() async throws -> [VaultActionItemRecord] {
        let a = try await loadActiveActionItemsUnsorted()
        let b = try await loadCompletedActionItemsUnsorted()
        return a + b
    }

    private func readContextDefinitionsAggregateRaw() async throws -> ([VaultContextDefinition], Data?) {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = VaultLayout.actionItemsContextsAggregatePath
        guard let data = try? await backend.read(relativePath: path) else {
            return ([], nil)
        }
        guard let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultContextDefinitionsFilePayload>.self, from: data) else {
            return ([], data)
        }
        return (env.payload.definitions, data)
    }

    private func readActionTypeDefinitionsAggregateRaw() async throws -> ([VaultActionTypeDefinition], Data?) {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = VaultLayout.actionItemsTypesAggregatePath
        guard let data = try? await backend.read(relativePath: path) else {
            return ([], nil)
        }
        guard let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionTypeDefinitionsFilePayload>.self, from: data) else {
            return ([], data)
        }
        return (env.payload.definitions, data)
    }

    private func readProjectDefinitionsAggregateRaw() async throws -> ([VaultProjectDefinition], Data?) {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = VaultLayout.actionItemsProjectsAggregatePath
        guard let data = try? await backend.read(relativePath: path) else {
            return ([], nil)
        }
        guard let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultProjectDefinitionsFilePayload>.self, from: data) else {
            return ([], data)
        }
        return (env.payload.definitions, data)
    }

    // MARK: - Migration (legacy per-item / per-definition files → aggregates)

    private func migrateActionItemsLayoutIfNeeded() async throws {
        guard let backend = folderBackend else { return }
        try await backend.ensureStructure()

        let activeAggregatePath = VaultLayout.actionItemsActiveAggregatePath
        let completedAggregatePath = VaultLayout.actionItemsCompletedAggregatePath
        let hasActiveFile = (try? await backend.read(relativePath: activeAggregatePath)) != nil
        let hasCompletedFile = (try? await backend.read(relativePath: completedAggregatePath)) != nil
        let hasAggregates = hasActiveFile || hasCompletedFile

        if !hasAggregates {
            var active: [VaultActionItemRecord] = []
            var completed: [VaultActionItemRecord] = []
            let legacyItemsPrefix = "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsLegacyItemsSubfolder)/"
            let legacyCompletedPrefix = "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsLegacyCompletedSubfolder)/"
            for p in try await backend.listRelativeFilePaths()
                .filter({ $0.hasPrefix(legacyItemsPrefix) && $0.lowercased().hasSuffix(".json") }) {
                guard let data = try? await backend.read(relativePath: p),
                      let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemRecord>.self, from: data)
                else { continue }
                if env.payload.isDone {
                    completed.append(env.payload)
                } else {
                    active.append(env.payload)
                }
            }
            for p in try await backend.listRelativeFilePaths()
                .filter({ $0.hasPrefix(legacyCompletedPrefix) && $0.lowercased().hasSuffix(".json") }) {
                guard let data = try? await backend.read(relativePath: p),
                      let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemRecord>.self, from: data)
                else { continue }
                completed.append(env.payload)
            }
            active = dedupeActionItemsById(active)
            completed = dedupeActionItemsById(completed)
            try await writeActiveAggregate(active, previousData: nil)
            try await writeCompletedAggregate(completed, previousData: nil)
            try await deleteLegacyActionItemPerItemFiles()
        }

        try await deleteLegacySequenceFileIfPresent()

        let typesAggregateMissing = (try? await backend.read(relativePath: VaultLayout.actionItemsTypesAggregatePath)) == nil
        let contextsAggregateMissing = (try? await backend.read(relativePath: VaultLayout.actionItemsContextsAggregatePath)) == nil
        let projectsAggregateMissing = (try? await backend.read(relativePath: VaultLayout.actionItemsProjectsAggregatePath)) == nil

        if contextsAggregateMissing {
            var defs: [VaultContextDefinition] = []
            let legacyPrefix = "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsLegacyContextsSubfolder)/"
            for p in try await backend.listRelativeFilePaths()
                .filter({ $0.hasPrefix(legacyPrefix) && $0.lowercased().hasSuffix(".json") }) {
                guard let data = try? await backend.read(relativePath: p),
                      let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultContextDefinition>.self, from: data)
                else { continue }
                defs.append(env.payload)
            }
            defs = dedupeById(defs)
            try await writeContextDefinitionsAggregate(defs, previousData: nil)
            try await deleteLegacyContextDefinitionFiles()
        }

        if typesAggregateMissing {
            var defs: [VaultActionTypeDefinition] = []
            let legacyPrefix = "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsLegacyTypesSubfolder)/"
            for p in try await backend.listRelativeFilePaths()
                .filter({ $0.hasPrefix(legacyPrefix) && $0.lowercased().hasSuffix(".json") }) {
                guard let data = try? await backend.read(relativePath: p),
                      let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionTypeDefinition>.self, from: data)
                else { continue }
                defs.append(env.payload)
            }
            defs = dedupeById(defs)
            try await writeActionTypeDefinitionsAggregate(defs, previousData: nil)
            try await deleteLegacyTypeDefinitionFiles()
        }

        if projectsAggregateMissing {
            let defs: [VaultProjectDefinition] = [
                VaultProjectDefinition(
                    name: ActionItemsFeatureModel.generalProjectName,
                    accentColorHex: ContextAccentPalette.defaultGreyHex,
                    sortOrder: -10_000
                )
            ]
            try await writeProjectDefinitionsAggregate(defs, previousData: nil)
        }
    }

    private func writeContextDefinitionsAggregate(_ defs: [VaultContextDefinition], previousData: Data?) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let token = VaultLWWHelpers.nextWriteToken(existingData: previousData)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: VaultContextDefinitionsFilePayload(definitions: defs)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsContextsAggregatePath, data: data)
    }

    private func writeActionTypeDefinitionsAggregate(_ defs: [VaultActionTypeDefinition], previousData: Data?) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let token = VaultLWWHelpers.nextWriteToken(existingData: previousData)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: VaultActionTypeDefinitionsFilePayload(definitions: defs)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsTypesAggregatePath, data: data)
    }

    private func writeProjectDefinitionsAggregate(_ defs: [VaultProjectDefinition], previousData: Data?) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let token = VaultLWWHelpers.nextWriteToken(existingData: previousData)
        let envelope = VaultFileEnvelope(
            updatedAt: Date(),
            writeToken: token,
            payload: VaultProjectDefinitionsFilePayload(definitions: defs)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsProjectsAggregatePath, data: data)
    }

    private func dedupeActionItemsById(_ items: [VaultActionItemRecord]) -> [VaultActionItemRecord] {
        var seen = Set<String>()
        var out: [VaultActionItemRecord] = []
        for item in items {
            if seen.contains(item.id) { continue }
            seen.insert(item.id)
            out.append(item)
        }
        return out
    }

    private func dedupeById<T: Identifiable>(_ items: [T]) -> [T] where T.ID: Hashable {
        var seen = Set<T.ID>()
        var out: [T] = []
        for item in items {
            if seen.contains(item.id) { continue }
            seen.insert(item.id)
            out.append(item)
        }
        return out
    }

    private func dedupeContextDefinitionsByNormalizedName() async throws {
        let (defs, defsData) = try await readContextDefinitionsAggregateRaw()
        guard !defs.isEmpty else { return }
        var canonicalByKey: [String: VaultContextDefinition] = [:]
        var idRemap: [String: String] = [:]
        for def in defs.sorted(by: { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }) {
            let key = ActionItemsFeatureModel.normalizedSubjectKey(def.name).lowercased()
            if let canonical = canonicalByKey[key] {
                idRemap[def.id] = canonical.id
            } else {
                canonicalByKey[key] = def
                idRemap[def.id] = def.id
            }
        }
        let deduped = Array(canonicalByKey.values).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        if deduped.count != defs.count {
            try await writeContextDefinitionsAggregate(deduped, previousData: defsData)
            let (activeItems, activeData) = try await readActiveAggregateRaw()
            let (completedItems, completedData) = try await readCompletedAggregateRaw()
            let rewrittenActive = activeItems.map { item in
                var out = item
                if let cid = item.contextId, let mapped = idRemap[cid], mapped != cid {
                    out.contextId = mapped
                }
                return out
            }
            let rewrittenCompleted = completedItems.map { item in
                var out = item
                if let cid = item.contextId, let mapped = idRemap[cid], mapped != cid {
                    out.contextId = mapped
                }
                return out
            }
            try await writeActiveAggregate(rewrittenActive, previousData: activeData)
            try await writeCompletedAggregate(rewrittenCompleted, previousData: completedData)
        }
    }

    private func migrateActionItemsToGeneralProjectIfNeeded() async throws {
        let general = try await ensureGeneralProjectDefinition()
        let (activeItems, activeData) = try await readActiveAggregateRaw()
        let (completedItems, completedData) = try await readCompletedAggregateRaw()
        let activeNeedsMigration = activeItems.contains(where: { $0.projectId == nil })
        let completedNeedsMigration = completedItems.contains(where: { $0.projectId == nil })
        guard activeNeedsMigration || completedNeedsMigration else { return }
        let migratedActive = activeItems.map { item -> VaultActionItemRecord in
            var out = item
            if out.projectId == nil {
                out.projectId = general.id
            }
            return out
        }
        let migratedCompleted = completedItems.map { item -> VaultActionItemRecord in
            var out = item
            if out.projectId == nil {
                out.projectId = general.id
            }
            return out
        }
        try await writeActiveAggregate(migratedActive, previousData: activeData)
        try await writeCompletedAggregate(migratedCompleted, previousData: completedData)
    }

    private func deleteLegacyActionItemPerItemFiles() async throws {
        guard let backend = folderBackend else { return }
        let legacyItemsPrefix = "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsLegacyItemsSubfolder)/"
        let legacyCompletedPrefix = "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsLegacyCompletedSubfolder)/"
        for p in try await backend.listRelativeFilePaths()
            .filter({ ($0.hasPrefix(legacyItemsPrefix) || $0.hasPrefix(legacyCompletedPrefix)) && $0.lowercased().hasSuffix(".json") }) {
            try? await backend.remove(relativePath: p)
        }
    }

    private func deleteLegacySequenceFileIfPresent() async throws {
        guard let backend = folderBackend else { return }
        let legacy = "\(VaultLayout.actionItemsFolder)/meta/action_item_sequence.json"
        if (try? await backend.read(relativePath: legacy)) != nil {
            try? await backend.remove(relativePath: legacy)
        }
    }

    private func deleteLegacyContextDefinitionFiles() async throws {
        guard let backend = folderBackend else { return }
        let prefix = "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsLegacyContextsSubfolder)/"
        for p in try await backend.listRelativeFilePaths()
            .filter({ $0.hasPrefix(prefix) && $0.lowercased().hasSuffix(".json") }) {
            try? await backend.remove(relativePath: p)
        }
    }

    private func deleteLegacyTypeDefinitionFiles() async throws {
        guard let backend = folderBackend else { return }
        let prefix = "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsLegacyTypesSubfolder)/"
        for p in try await backend.listRelativeFilePaths()
            .filter({ $0.hasPrefix(prefix) && $0.lowercased().hasSuffix(".json") }) {
            try? await backend.remove(relativePath: p)
        }
    }

    // MARK: - Migration

    private func runMigrationIfPossible() async throws {
        guard let backend = folderBackend else { return }
        try await VaultMigrationImporter.importInterestProfileOnce(folderBackend: backend)
        try await migrateActionItemsLayoutIfNeeded()
        try await dedupeContextDefinitionsByNormalizedName()
        try await migrateActionItemsToGeneralProjectIfNeeded()
    }
}
