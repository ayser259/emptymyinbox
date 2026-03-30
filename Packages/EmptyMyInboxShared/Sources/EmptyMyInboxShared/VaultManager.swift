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
            try? await self.purgeCompletedActionItemsOlderThan(days: 30)
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
        let config = VaultActiveConfiguration(vaultId: vaultId, backend: .local, displayName: displayName)
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
            driveAccountEmail: email
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

    /// Scheduled for the given day (start/end overlap) plus unscheduled items (no start/end).
    public func listActionItemsForToday(
        referenceDay: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> (scheduled: [VaultActionItemRecord], unscheduled: [VaultActionItemRecord]) {
        let all = try await loadActiveActionItemsUnsorted()
        return ActionItemsFeatureModel.itemsForTodayList(all, referenceDay: referenceDay, calendar: calendar)
    }

    public func listActionItemsBySubject(_ subjectKey: String) async throws -> [VaultActionItemRecord] {
        let all = try await listActionItems()
        return all.filter { ActionItemsFeatureModel.normalizedSubjectKey($0.subjectLabel) == subjectKey }
    }

    public func listActionItemSubjectGroups() async throws -> [(key: String, items: [VaultActionItemRecord])] {
        let all = try await loadActiveActionItemsUnsorted()
        return ActionItemsFeatureModel.groupedBySubject(all)
    }

    public func listActionItemsForCalendarRange(
        start: Date,
        end: Date,
        calendar: Calendar = .current
    ) async throws -> [VaultActionItemRecord] {
        let all = try await loadActiveActionItemsUnsorted()
        return ActionItemsFeatureModel.itemsIntersectingRange(all, rangeStart: start, rangeEnd: end, calendar: calendar)
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
            startDate: nil,
            endDate: nil,
            priority: parent.priority,
            taskDescription: parent.taskDescription,
            contextNotes: parent.contextNotes,
            comments: [],
            parentTaskId: parentId,
            subjectLabel: parent.subjectLabel,
            contextId: parent.contextId,
            typeLabel: parent.typeLabel,
            typeId: parent.typeId,
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

    public func upsertActionItem(_ item: VaultActionItemRecord) async throws {
        guard folderBackend != nil else { throw VaultError.notConfigured }
        var normalized = item
        if let p = normalized.priority {
            normalized.priority = min(3, max(0, p))
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

    public func upsertContextDefinition(_ def: VaultContextDefinition) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        var (defs, existingData) = try await readContextDefinitionsAggregateRaw()
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
            payload: VaultContextDefinitionsFilePayload(definitions: defs)
        )
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: VaultLayout.actionItemsContextsAggregatePath, data: data)
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
    }
}
