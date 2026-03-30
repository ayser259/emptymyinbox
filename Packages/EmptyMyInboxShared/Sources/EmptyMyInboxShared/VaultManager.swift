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
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let activePath = actionItemActivePath(id: id)
        if let data = try? await backend.read(relativePath: activePath),
           let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemRecord>.self, from: data) {
            return env.payload
        }
        let completedPath = actionItemCompletedPath(id: id)
        if let data = try? await backend.read(relativePath: completedPath),
           let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemRecord>.self, from: data) {
            return env.payload
        }
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
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        var normalized = item
        if let p = normalized.priority {
            normalized.priority = min(3, max(0, p))
        }
        if normalized.numericId <= 0 {
            normalized.numericId = try await allocateNextNumericId()
        }
        let activePath = actionItemActivePath(id: normalized.id)
        let completedPath = actionItemCompletedPath(id: normalized.id)
        let activeData = try? await backend.read(relativePath: activePath)
        let completedData = try? await backend.read(relativePath: completedPath)
        let existingForToken = activeData ?? completedData
        if existingForToken == nil, normalized.createdAt == nil {
            normalized.createdAt = Date()
        }
        normalized.updatedAt = Date()
        let targetPath = normalized.isDone ? completedPath : activePath
        let token = VaultLWWHelpers.nextWriteToken(existingData: existingForToken)
        let envelope = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: normalized)
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: targetPath, data: data)
        if normalized.isDone, activeData != nil {
            try await backend.remove(relativePath: activePath)
        }
        if !normalized.isDone, completedData != nil {
            try await backend.remove(relativePath: completedPath)
        }
    }

    public func deleteActionItem(id: String) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let activePath = actionItemActivePath(id: id)
        let completedPath = actionItemCompletedPath(id: id)
        if (try? await backend.read(relativePath: activePath)) != nil {
            try await backend.remove(relativePath: activePath)
            return
        }
        if (try? await backend.read(relativePath: completedPath)) != nil {
            try await backend.remove(relativePath: completedPath)
        }
    }

    /// Deletes completed items whose `completedAt` is older than `days`.
    public func purgeCompletedActionItemsOlderThan(days: Int = 30, referenceDate: Date = Date()) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        let completed = try await loadCompletedActionItemsUnsorted()
        for item in completed {
            guard let completedAt = item.completedAt, completedAt < cutoff else { continue }
            try await backend.remove(relativePath: actionItemCompletedPath(id: item.id))
        }
    }

    // MARK: - Context & type definitions

    public func listContextDefinitions() async throws -> [VaultContextDefinition] {
        try await loadDefinitions(subfolder: VaultLayout.actionItemsContextsSubfolder) { data in
            try VaultJSON.decoder().decode(VaultFileEnvelope<VaultContextDefinition>.self, from: data).payload
        }
    }

    public func upsertContextDefinition(_ def: VaultContextDefinition) async throws {
        try await writeDefinition(
            def,
            subfolder: VaultLayout.actionItemsContextsSubfolder,
            id: def.id
        ) { d in
            var x = d
            let now = Date()
            if x.createdAt == nil { x.createdAt = now }
            x.updatedAt = now
            return x
        }
    }

    public func deleteContextDefinition(id: String) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        try await backend.remove(relativePath: contextDefinitionPath(id: id))
    }

    public func listActionTypeDefinitions() async throws -> [VaultActionTypeDefinition] {
        try await loadDefinitions(subfolder: VaultLayout.actionItemsTypesSubfolder) { data in
            try VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionTypeDefinition>.self, from: data).payload
        }
    }

    public func upsertActionTypeDefinition(_ def: VaultActionTypeDefinition) async throws {
        try await writeDefinition(
            def,
            subfolder: VaultLayout.actionItemsTypesSubfolder,
            id: def.id
        ) { d in
            var x = d
            let now = Date()
            if x.createdAt == nil { x.createdAt = now }
            x.updatedAt = now
            return x
        }
    }

    public func deleteActionTypeDefinition(id: String) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        try await backend.remove(relativePath: actionTypeDefinitionPath(id: id))
    }

    // MARK: - Action item paths & loading

    private func actionItemActivePath(id: String) -> String {
        "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsSubfolder)/\(id).json"
    }

    private func actionItemCompletedPath(id: String) -> String {
        "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsCompletedSubfolder)/\(id).json"
    }

    private func contextDefinitionPath(id: String) -> String {
        "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsContextsSubfolder)/\(id).json"
    }

    private func actionTypeDefinitionPath(id: String) -> String {
        "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsTypesSubfolder)/\(id).json"
    }

    private func loadActiveActionItemsUnsorted() async throws -> [VaultActionItemRecord] {
        try await loadActionItemsFromFolder(subfolder: VaultLayout.actionItemsSubfolder)
    }

    private func loadCompletedActionItemsUnsorted() async throws -> [VaultActionItemRecord] {
        try await loadActionItemsFromFolder(subfolder: VaultLayout.actionItemsCompletedSubfolder)
    }

    private func loadAllActionItemsFromBothFoldersUnsorted() async throws -> [VaultActionItemRecord] {
        let a = try await loadActiveActionItemsUnsorted()
        let b = try await loadCompletedActionItemsUnsorted()
        return a + b
    }

    private func loadActionItemsFromFolder(subfolder: String) async throws -> [VaultActionItemRecord] {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let prefix = "\(VaultLayout.actionItemsFolder)/\(subfolder)/"
        let paths = try await backend.listRelativeFilePaths()
            .filter { $0.hasPrefix(prefix) && $0.lowercased().hasSuffix(".json") }
        var out: [VaultActionItemRecord] = []
        for p in paths {
            guard let data = try? await backend.read(relativePath: p),
                  let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemRecord>.self, from: data)
            else { continue }
            out.append(env.payload)
        }
        return out
    }

    private func loadDefinitions<T>(
        subfolder: String,
        decode: (Data) throws -> T
    ) async throws -> [T] {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let prefix = "\(VaultLayout.actionItemsFolder)/\(subfolder)/"
        let paths = try await backend.listRelativeFilePaths()
            .filter { $0.hasPrefix(prefix) && $0.lowercased().hasSuffix(".json") }
        var out: [T] = []
        for p in paths {
            guard let data = try? await backend.read(relativePath: p),
                  let item = try? decode(data) else { continue }
            out.append(item)
        }
        return out
    }

    private func writeDefinition<T: Codable>(
        _ def: T,
        subfolder: String,
        id: String,
        touch: (T) -> T
    ) async throws {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path: String
        switch subfolder {
        case VaultLayout.actionItemsContextsSubfolder:
            path = contextDefinitionPath(id: id)
        case VaultLayout.actionItemsTypesSubfolder:
            path = actionTypeDefinitionPath(id: id)
        default:
            path = "\(VaultLayout.actionItemsFolder)/\(subfolder)/\(id).json"
        }
        let updated = touch(def)
        let existing = try? await backend.read(relativePath: path)
        let token = VaultLWWHelpers.nextWriteToken(existingData: existing)
        let envelope = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: updated)
        let data = try VaultJSON.encoder().encode(envelope)
        try await backend.write(relativePath: path, data: data)
    }

    private func allocateNextNumericId() async throws -> Int {
        guard let backend = folderBackend else { throw VaultError.notConfigured }
        let path = VaultLayout.actionItemSequenceRelativePath
        let existing = try? await backend.read(relativePath: path)
        var state: VaultActionItemSequenceState
        if let existing,
           let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemSequenceState>.self, from: existing) {
            state = env.payload
        } else {
            state = VaultActionItemSequenceState(nextNumericId: 1)
        }
        let assigned = state.nextNumericId
        state.nextNumericId += 1
        let token = VaultLWWHelpers.nextWriteToken(existingData: existing)
        let out = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: state)
        let data = try VaultJSON.encoder().encode(out)
        try await backend.write(relativePath: path, data: data)
        return assigned
    }

    /// Ensures sequence counter is at least `max(existing numeric ids) + 1`.
    private func reconcileNumericIdSequenceWithVault() async throws {
        guard let backend = folderBackend else { return }
        let all = try await loadAllActionItemsFromBothFoldersUnsorted()
        let maxId = all.map(\.numericId).max() ?? 0
        let path = VaultLayout.actionItemSequenceRelativePath
        let existing = try? await backend.read(relativePath: path)
        var state: VaultActionItemSequenceState
        if let existing,
           let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemSequenceState>.self, from: existing) {
            state = env.payload
        } else {
            state = VaultActionItemSequenceState(nextNumericId: max(1, maxId + 1))
        }
        if state.nextNumericId <= maxId {
            state.nextNumericId = maxId + 1
            let token = VaultLWWHelpers.nextWriteToken(existingData: existing)
            let out = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: state)
            let data = try VaultJSON.encoder().encode(out)
            try await backend.write(relativePath: path, data: data)
        }
    }

    private func migrateActionItemsLayoutIfNeeded() async throws {
        guard let backend = folderBackend else { return }
        try await backend.ensureStructure()
        let itemsPrefix = "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsSubfolder)/"
        let paths = try await backend.listRelativeFilePaths()
            .filter { $0.hasPrefix(itemsPrefix) && $0.lowercased().hasSuffix(".json") }
        for p in paths {
            guard let data = try? await backend.read(relativePath: p),
                  let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemRecord>.self, from: data)
            else { continue }
            guard env.payload.isDone else { continue }
            let id = env.payload.id
            let completedPath = actionItemCompletedPath(id: id)
            let completedExisting = try? await backend.read(relativePath: completedPath)
            let token = VaultLWWHelpers.nextWriteToken(existingData: completedExisting ?? data)
            let newEnv = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: env.payload)
            let out = try VaultJSON.encoder().encode(newEnv)
            try await backend.write(relativePath: completedPath, data: out)
            try await backend.remove(relativePath: p)
        }
        try await backfillMissingNumericIds()
        try await reconcileNumericIdSequenceWithVault()
    }

    private func backfillMissingNumericIds() async throws {
        guard let backend = folderBackend else { return }
        let prefixes = [
            "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsSubfolder)/",
            "\(VaultLayout.actionItemsFolder)/\(VaultLayout.actionItemsCompletedSubfolder)/"
        ]
        var paths: [String] = []
        for pre in prefixes {
            let found = try await backend.listRelativeFilePaths()
                .filter { $0.hasPrefix(pre) && $0.lowercased().hasSuffix(".json") }
            paths.append(contentsOf: found)
        }
        var maxId = 0
        var payloads: [(path: String, payload: VaultActionItemRecord, data: Data)] = []
        for p in paths {
            guard let data = try? await backend.read(relativePath: p),
                  let env = try? VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemRecord>.self, from: data)
            else { continue }
            if env.payload.numericId > maxId {
                maxId = env.payload.numericId
            }
            payloads.append((p, env.payload, data))
        }
        var next = maxId + 1
        for i in payloads.indices where payloads[i].payload.numericId <= 0 {
            var item = payloads[i].payload
            item.numericId = next
            next += 1
            let existingData = payloads[i].data
            let token = VaultLWWHelpers.nextWriteToken(existingData: existingData)
            let newEnv = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: item)
            let out = try VaultJSON.encoder().encode(newEnv)
            try await backend.write(relativePath: payloads[i].path, data: out)
        }
    }

    // MARK: - Migration

    private func runMigrationIfPossible() async throws {
        guard let backend = folderBackend else { return }
        try await VaultMigrationImporter.importInterestProfileOnce(folderBackend: backend)
        try await migrateActionItemsLayoutIfNeeded()
    }
}
