//
//  VaultModels.swift
//  EmptyMyInboxShared
//
//  Shared types for vault layout: Inbox/, Calendar/, ActionItems/ + manifest and envelopes.
//

import Foundation

// MARK: - Layout constants

/// Relative paths under the vault root (`vault_manifest.json` lives at the root next to `Inbox/`, `Calendar/`, `ActionItems/`).
///
/// **iOS and macOS** both use `EmptyMyInboxShared` only: there are no platform-specific filenames for vault data. The same `VaultLayout` strings are passed to `VaultFolderBackend` on every platform.
///
/// **Multiple devices** see the same logical files when they use the **same vault configuration**—for `.googleDrive`, the same Gmail account and `driveRootFolderId` so `VaultSyncCoordinator` pulls/pushes the same paths on Drive. Purely local vaults (`.local`) are per-machine unless you point both apps at the same folder via `.externalFolder` with a synced directory.
public enum VaultLayout {
    public static let manifestFileName = "vault_manifest.json"
    public static let syncLogFileName = "vault_sync_log.json"
    public static let inboxFolder = "Inbox"
    public static let calendarFolder = "Calendar"
    public static let actionItemsFolder = "ActionItems"
    public static let inboxThreadsSubfolder = "threads"
    public static let calendarEventsSubfolder = "events"

    /// Legacy per-item layout (migration only).
    public static let actionItemsLegacyItemsSubfolder = "items"
    public static let actionItemsLegacyCompletedSubfolder = "completed"
    public static let actionItemsLegacyContextsSubfolder = "contexts"
    public static let actionItemsLegacyTypesSubfolder = "types"

    public static let actionItemsActiveAggregateFileName = "active_items.json"
    public static let actionItemsCompletedAggregateFileName = "completed_items.json"
    public static let actionItemsContextsAggregateFileName = "context_definitions.json"
    public static let actionItemsTypesAggregateFileName = "type_definitions.json"
    public static let actionItemsProjectsAggregateFileName = "project_definitions.json"
    public static let actionItemsStarredChannelsAggregateFileName = "starred_channels.json"

    public static let currentSchemaVersion = 1

    public static func standardSubfolders() -> [String] {
        [
            "\(inboxFolder)/\(inboxThreadsSubfolder)",
            "\(calendarFolder)/\(calendarEventsSubfolder)",
            actionItemsFolder
        ]
    }

    public static var actionItemsActiveAggregatePath: String {
        "\(actionItemsFolder)/\(actionItemsActiveAggregateFileName)"
    }

    public static var actionItemsCompletedAggregatePath: String {
        "\(actionItemsFolder)/\(actionItemsCompletedAggregateFileName)"
    }

    public static var actionItemsContextsAggregatePath: String {
        "\(actionItemsFolder)/\(actionItemsContextsAggregateFileName)"
    }

    public static var actionItemsTypesAggregatePath: String {
        "\(actionItemsFolder)/\(actionItemsTypesAggregateFileName)"
    }

    public static var actionItemsProjectsAggregatePath: String {
        "\(actionItemsFolder)/\(actionItemsProjectsAggregateFileName)"
    }

    public static var actionItemsStarredChannelsAggregatePath: String {
        "\(actionItemsFolder)/\(actionItemsStarredChannelsAggregateFileName)"
    }

    /// All JSON blobs for action items, labels (context/type definitions), and their sync targets. Keep in sync with `VaultManager` read/write sites.
    public static var actionItemAggregateRelativePaths: [String] {
        [
            actionItemsActiveAggregatePath,
            actionItemsCompletedAggregatePath,
            actionItemsContextsAggregatePath,
            actionItemsTypesAggregatePath,
            actionItemsProjectsAggregatePath,
            actionItemsStarredChannelsAggregatePath
        ]
    }
}

// MARK: - Backend kind

public enum VaultBackendKind: String, Codable, Sendable, CaseIterable {
    case local
    case externalFolder
    case googleDrive

    /// Short label for settings / account rows.
    public var settingsDisplayName: String {
        switch self {
        case .local: return "On device"
        case .externalFolder: return "Folder"
        case .googleDrive: return "Google Drive"
        }
    }
}

// MARK: - Active configuration (persisted)

/// Describes the vault the user has selected. Secrets (tokens) are not stored here.
public struct VaultActiveConfiguration: Codable, Sendable, Equatable {
    public var vaultId: String
    public var backend: VaultBackendKind
    public var displayName: String?
    /// Security-scoped bookmark when `backend == .externalFolder`
    public var securityScopedBookmarkData: Data?
    /// Google Drive folder ID for vault root (contains Inbox, Calendar, ActionItems)
    public var driveRootFolderId: String?
    /// Gmail account email whose OAuth token is used for Drive API
    public var driveAccountEmail: String?
    /// Google account this vault is tied to (all backends). Used for settings / disconnect clarity. For Google Drive vaults, defaults to `driveAccountEmail` when unset.
    public var ownerAccountEmail: String?

    public init(
        vaultId: String = UUID().uuidString,
        backend: VaultBackendKind,
        displayName: String? = nil,
        securityScopedBookmarkData: Data? = nil,
        driveRootFolderId: String? = nil,
        driveAccountEmail: String? = nil,
        ownerAccountEmail: String? = nil
    ) {
        self.vaultId = vaultId
        self.backend = backend
        self.displayName = displayName
        self.securityScopedBookmarkData = securityScopedBookmarkData
        self.driveRootFolderId = driveRootFolderId
        self.driveAccountEmail = driveAccountEmail
        self.ownerAccountEmail = ownerAccountEmail
    }

    /// Owner for display and disconnect copy (`driveAccountEmail` for legacy Drive-only configs).
    public var resolvedOwnerEmail: String? {
        ownerAccountEmail ?? driveAccountEmail
    }

    /// Web URL for the vault root folder (Safari or Google Drive app on iOS).
    public var googleDriveRootWebURL: URL? {
        guard backend == .googleDrive else { return nil }
        guard let id = driveRootFolderId else { return nil }
        return GoogleDriveWebLinks.folderURL(folderId: id)
    }
}

// MARK: - Google Drive (web)

public enum GoogleDriveWebLinks {
    /// `https://drive.google.com/drive/folders/…` — opens in the browser or the Drive app when available.
    public static func folderURL(folderId: String) -> URL? {
        let trimmed = folderId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "https://drive.google.com/drive/folders/\(trimmed)")
    }
}

// MARK: - Manifest (lives at vault root)

public struct VaultManifest: Codable, Sendable, Equatable {
    public var vaultId: String
    public var schemaVersion: Int
    public var backendKind: VaultBackendKind
    public var createdAt: Date
    public var updatedAt: Date
    /// Google Drive `changes` API start page token (optional incremental sync)
    public var driveChangesPageToken: String?
    public var lastSuccessfulSyncAt: Date?
    /// Persisted so a Drive vault can be reopened from disk (tokens stay in Keychain).
    public var driveRootFolderId: String?
    public var driveAccountEmail: String?
    /// Optional label for discovery UI (not required for sync).
    public var displayName: String?

    public init(
        vaultId: String,
        schemaVersion: Int = VaultLayout.currentSchemaVersion,
        backendKind: VaultBackendKind,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        driveChangesPageToken: String? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        driveRootFolderId: String? = nil,
        driveAccountEmail: String? = nil,
        displayName: String? = nil
    ) {
        self.vaultId = vaultId
        self.schemaVersion = schemaVersion
        self.backendKind = backendKind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.driveChangesPageToken = driveChangesPageToken
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.driveRootFolderId = driveRootFolderId
        self.driveAccountEmail = driveAccountEmail
        self.displayName = displayName
    }
}

// MARK: - File envelope (LWW via updatedAt + writeToken)

public struct VaultFileEnvelope<T: Codable>: Codable {
    public var schemaVersion: Int
    public var updatedAt: Date
    public var writeToken: UInt64
    public var payload: T

    public init(schemaVersion: Int = VaultLayout.currentSchemaVersion, updatedAt: Date = Date(), writeToken: UInt64, payload: T) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.writeToken = writeToken
        self.payload = payload
    }
}

/// Payload stubs for feature folders (extend freely; stored as JSON files).
public struct VaultInboxThreadRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var threadId: String
    public var title: String?
    public var notes: String?
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, threadId: String, title: String? = nil, notes: String? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.threadId = threadId
        self.title = title
        self.notes = notes
        self.updatedAt = updatedAt
    }
}

public struct VaultCalendarEventRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var notes: String?
    public var startDate: Date?
    public var endDate: Date?

    public init(id: String = UUID().uuidString, title: String, notes: String? = nil, startDate: Date? = nil, endDate: Date? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
    }
}

// MARK: - Action items (tasks)

/// A single comment / note entry on an action item (timestamped).
public struct VaultActionItemCommentRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var createdAt: Date
    public var text: String

    public init(id: String = ULID.generate(), createdAt: Date = Date(), text: String) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
    }
}

public struct VaultActionItemRecord: Codable, Sendable, Identifiable, Equatable {
    /// Stable identifier (ULID string for new items; legacy vault rows may still use UUID strings).
    public var id: String
    public var title: String
    public var isDone: Bool
    public var notes: String?
    /// Optional priority on a 0...4 scale (`p0` = highest urgency, `p4` = lowest among set priorities).
    public var priority: Int?
    /// Optional urgency on a 0...4 scale (`u0` = most urgent, `u4` = least urgent among set urgencies).
    public var urgency: Int?
    /// Longer documentation for the task (JSON key `"description"`).
    public var taskDescription: String?
    /// Extra structured-ish context (tags, freeform).
    public var contextNotes: String?
    public var comments: [VaultActionItemCommentRecord]
    public var parentTaskId: String?
    /// Context / channel / subject grouping.
    public var subjectLabel: String?
    /// Optional link to a saved context definition.
    public var contextId: String?
    /// Work type: learning block, time block, action item, meeting, etc.
    public var typeLabel: String?
    /// Optional link to a saved type definition.
    public var typeId: String?
    /// Optional link to a project definition.
    public var projectId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var completedAt: Date?
    /// Calendar day the task is scheduled for (start-of-day semantics in the UI). `nil` means not scheduled.
    public var scheduledDate: Date?
    /// Pinned for the **Starred** hub (quick access across categories).
    public var isStarred: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, isDone, notes
        case priority, urgency
        case taskDescription = "description"
        case contextNotes, comments
        case parentTaskId, subjectLabel, contextId, typeLabel, typeId, projectId
        case createdAt, updatedAt, completedAt, scheduledDate
        case isStarred
    }

    public init(
        id: String = ULID.generate(),
        title: String,
        isDone: Bool = false,
        notes: String? = nil,
        priority: Int? = nil,
        urgency: Int? = nil,
        taskDescription: String? = nil,
        contextNotes: String? = nil,
        comments: [VaultActionItemCommentRecord] = [],
        parentTaskId: String? = nil,
        subjectLabel: String? = nil,
        contextId: String? = nil,
        typeLabel: String? = nil,
        typeId: String? = nil,
        projectId: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        completedAt: Date? = nil,
        scheduledDate: Date? = nil,
        isStarred: Bool = false
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.notes = notes
        self.priority = priority
        self.urgency = urgency
        self.taskDescription = taskDescription
        self.contextNotes = contextNotes
        self.comments = comments
        self.parentTaskId = parentTaskId
        self.subjectLabel = subjectLabel
        self.contextId = contextId
        self.typeLabel = typeLabel
        self.typeId = typeId
        self.projectId = projectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.scheduledDate = scheduledDate
        self.isStarred = isStarred
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        urgency = try c.decodeIfPresent(Int.self, forKey: .urgency)
        taskDescription = try c.decodeIfPresent(String.self, forKey: .taskDescription)
        contextNotes = try c.decodeIfPresent(String.self, forKey: .contextNotes)
        comments = try c.decodeIfPresent([VaultActionItemCommentRecord].self, forKey: .comments) ?? []
        parentTaskId = try c.decodeIfPresent(String.self, forKey: .parentTaskId)
        subjectLabel = try c.decodeIfPresent(String.self, forKey: .subjectLabel)
        contextId = try c.decodeIfPresent(String.self, forKey: .contextId)
        typeLabel = try c.decodeIfPresent(String.self, forKey: .typeLabel)
        typeId = try c.decodeIfPresent(String.self, forKey: .typeId)
        projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        scheduledDate = try c.decodeIfPresent(Date.self, forKey: .scheduledDate)
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(isDone, forKey: .isDone)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(priority, forKey: .priority)
        try c.encodeIfPresent(urgency, forKey: .urgency)
        try c.encodeIfPresent(taskDescription, forKey: .taskDescription)
        try c.encodeIfPresent(contextNotes, forKey: .contextNotes)
        try c.encode(comments, forKey: .comments)
        try c.encodeIfPresent(parentTaskId, forKey: .parentTaskId)
        try c.encodeIfPresent(subjectLabel, forKey: .subjectLabel)
        try c.encodeIfPresent(contextId, forKey: .contextId)
        try c.encodeIfPresent(typeLabel, forKey: .typeLabel)
        try c.encodeIfPresent(typeId, forKey: .typeId)
        try c.encodeIfPresent(projectId, forKey: .projectId)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(scheduledDate, forKey: .scheduledDate)
        try c.encode(isStarred, forKey: .isStarred)
    }
}

// MARK: - Action item aggregate files (one JSON per bucket)

public struct VaultActionItemsFilePayload: Codable, Sendable, Equatable {
    public var items: [VaultActionItemRecord]

    public init(items: [VaultActionItemRecord] = []) {
        self.items = items
    }
}

public struct VaultContextDefinitionsFilePayload: Codable, Sendable, Equatable {
    public var definitions: [VaultContextDefinition]

    public init(definitions: [VaultContextDefinition] = []) {
        self.definitions = definitions
    }
}

public struct VaultActionTypeDefinitionsFilePayload: Codable, Sendable, Equatable {
    public var definitions: [VaultActionTypeDefinition]

    public init(definitions: [VaultActionTypeDefinition] = []) {
        self.definitions = definitions
    }
}

public struct VaultProjectDefinitionsFilePayload: Codable, Sendable, Equatable {
    public var definitions: [VaultProjectDefinition]

    public init(definitions: [VaultProjectDefinition] = []) {
        self.definitions = definitions
    }
}

public struct VaultStarredSidebarChannelsPayload: Codable, Sendable, Equatable {
    public var pins: [ActionItemsSidebarPin]

    public init(pins: [ActionItemsSidebarPin] = []) {
        self.pins = pins
    }
}

// MARK: - Context & type definitions (rich tagging)

public struct VaultContextDefinition: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var notes: String?
    public var accentColorHex: String?
    public var symbolName: String?
    public var sortOrder: Int
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String = ULID.generate(),
        name: String,
        notes: String? = nil,
        accentColorHex: String? = nil,
        symbolName: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.accentColorHex = accentColorHex
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct VaultActionTypeDefinition: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var notes: String?
    public var accentColorHex: String?
    public var symbolName: String?
    public var sortOrder: Int
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String = ULID.generate(),
        name: String,
        notes: String? = nil,
        accentColorHex: String? = nil,
        symbolName: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.accentColorHex = accentColorHex
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct VaultProjectDefinition: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var notes: String?
    public var accentColorHex: String?
    public var symbolName: String?
    public var sortOrder: Int
    public var parentProjectId: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String = ULID.generate(),
        name: String,
        notes: String? = nil,
        accentColorHex: String? = nil,
        symbolName: String? = nil,
        sortOrder: Int = 0,
        parentProjectId: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.accentColorHex = accentColorHex
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.parentProjectId = parentProjectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Sector-relative paths

public enum VaultSector: String, Sendable, CaseIterable {
    case inbox
    case calendar
    case actionItems

    public var rootFolderName: String {
        switch self {
        case .inbox: return VaultLayout.inboxFolder
        case .calendar: return VaultLayout.calendarFolder
        case .actionItems: return VaultLayout.actionItemsFolder
        }
    }
}

// MARK: - JSON helpers

public enum VaultJSON {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
