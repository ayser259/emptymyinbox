//
//  VaultModels.swift
//  EmptyMyInboxShared
//
//  Shared types for vault layout: Inbox/, Calendar/, ActionItems/ + manifest and envelopes.
//

import Foundation

// MARK: - Layout constants

public enum VaultLayout {
    public static let manifestFileName = "vault_manifest.json"
    public static let syncLogFileName = "vault_sync_log.json"
    public static let inboxFolder = "Inbox"
    public static let calendarFolder = "Calendar"
    public static let actionItemsFolder = "ActionItems"
    public static let inboxThreadsSubfolder = "threads"
    public static let calendarEventsSubfolder = "events"
    public static let actionItemsSubfolder = "items"
    public static let actionItemsCompletedSubfolder = "completed"
    public static let actionItemsMetaSubfolder = "meta"
    public static let actionItemSequenceFileName = "action_item_sequence.json"
    public static let actionItemsContextsSubfolder = "contexts"
    public static let actionItemsTypesSubfolder = "types"

    public static let currentSchemaVersion = 1

    public static func standardSubfolders() -> [String] {
        [
            "\(inboxFolder)/\(inboxThreadsSubfolder)",
            "\(calendarFolder)/\(calendarEventsSubfolder)",
            "\(actionItemsFolder)/\(actionItemsSubfolder)",
            "\(actionItemsFolder)/\(actionItemsCompletedSubfolder)",
            "\(actionItemsFolder)/\(actionItemsMetaSubfolder)",
            "\(actionItemsFolder)/\(actionItemsContextsSubfolder)",
            "\(actionItemsFolder)/\(actionItemsTypesSubfolder)"
        ]
    }

    public static var actionItemSequenceRelativePath: String {
        "\(actionItemsFolder)/\(actionItemsMetaSubfolder)/\(actionItemSequenceFileName)"
    }
}

// MARK: - Backend kind

public enum VaultBackendKind: String, Codable, Sendable, CaseIterable {
    case local
    case externalFolder
    case googleDrive
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

    public init(
        vaultId: String = UUID().uuidString,
        backend: VaultBackendKind,
        displayName: String? = nil,
        securityScopedBookmarkData: Data? = nil,
        driveRootFolderId: String? = nil,
        driveAccountEmail: String? = nil
    ) {
        self.vaultId = vaultId
        self.backend = backend
        self.displayName = displayName
        self.securityScopedBookmarkData = securityScopedBookmarkData
        self.driveRootFolderId = driveRootFolderId
        self.driveAccountEmail = driveAccountEmail
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

    public init(
        vaultId: String,
        schemaVersion: Int = VaultLayout.currentSchemaVersion,
        backendKind: VaultBackendKind,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        driveChangesPageToken: String? = nil,
        lastSuccessfulSyncAt: Date? = nil
    ) {
        self.vaultId = vaultId
        self.schemaVersion = schemaVersion
        self.backendKind = backendKind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.driveChangesPageToken = driveChangesPageToken
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
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

    public init(id: String = UUID().uuidString, createdAt: Date = Date(), text: String) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
    }
}

public struct VaultActionItemRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    /// Monotonic human-visible id (e.g. "#42"); persisted and unique across active + completed.
    public var numericId: Int
    public var title: String
    public var isDone: Bool
    public var notes: String?
    /// Optional scheduled / tracked start (used for Today and Calendar views).
    public var startDate: Date?
    /// Optional scheduled / tracked end.
    public var endDate: Date?
    /// Optional priority on a 0...3 scale (3 = highest).
    public var priority: Int?
    /// Longer documentation for the task (JSON key `"description"`).
    public var taskDescription: String?
    /// Extra structured-ish context (tags, freeform).
    public var contextNotes: String?
    public var comments: [VaultActionItemCommentRecord]
    public var parentTaskId: String?
    /// Context / channel / subject grouping.
    public var subjectLabel: String?
    /// Optional link to a saved context definition (`ActionItems/contexts/*.json`).
    public var contextId: String?
    /// Work type: learning block, time block, action item, meeting, etc.
    public var typeLabel: String?
    /// Optional link to a saved type definition (`ActionItems/types/*.json`).
    public var typeId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, numericId, title, isDone, notes
        case startDate, endDate, priority
        case taskDescription = "description"
        case contextNotes, comments
        case parentTaskId, subjectLabel, contextId, typeLabel, typeId
        case createdAt, updatedAt, completedAt
    }

    public init(
        id: String = UUID().uuidString,
        numericId: Int = 0,
        title: String,
        isDone: Bool = false,
        notes: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        priority: Int? = nil,
        taskDescription: String? = nil,
        contextNotes: String? = nil,
        comments: [VaultActionItemCommentRecord] = [],
        parentTaskId: String? = nil,
        subjectLabel: String? = nil,
        contextId: String? = nil,
        typeLabel: String? = nil,
        typeId: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.numericId = numericId
        self.title = title
        self.isDone = isDone
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.priority = priority
        self.taskDescription = taskDescription
        self.contextNotes = contextNotes
        self.comments = comments
        self.parentTaskId = parentTaskId
        self.subjectLabel = subjectLabel
        self.contextId = contextId
        self.typeLabel = typeLabel
        self.typeId = typeId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        numericId = try c.decodeIfPresent(Int.self, forKey: .numericId) ?? 0
        title = try c.decode(String.self, forKey: .title)
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        taskDescription = try c.decodeIfPresent(String.self, forKey: .taskDescription)
        contextNotes = try c.decodeIfPresent(String.self, forKey: .contextNotes)
        comments = try c.decodeIfPresent([VaultActionItemCommentRecord].self, forKey: .comments) ?? []
        parentTaskId = try c.decodeIfPresent(String.self, forKey: .parentTaskId)
        subjectLabel = try c.decodeIfPresent(String.self, forKey: .subjectLabel)
        contextId = try c.decodeIfPresent(String.self, forKey: .contextId)
        typeLabel = try c.decodeIfPresent(String.self, forKey: .typeLabel)
        typeId = try c.decodeIfPresent(String.self, forKey: .typeId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(numericId, forKey: .numericId)
        try c.encode(title, forKey: .title)
        try c.encode(isDone, forKey: .isDone)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encodeIfPresent(endDate, forKey: .endDate)
        try c.encodeIfPresent(priority, forKey: .priority)
        try c.encodeIfPresent(taskDescription, forKey: .taskDescription)
        try c.encodeIfPresent(contextNotes, forKey: .contextNotes)
        try c.encode(comments, forKey: .comments)
        try c.encodeIfPresent(parentTaskId, forKey: .parentTaskId)
        try c.encodeIfPresent(subjectLabel, forKey: .subjectLabel)
        try c.encodeIfPresent(contextId, forKey: .contextId)
        try c.encodeIfPresent(typeLabel, forKey: .typeLabel)
        try c.encodeIfPresent(typeId, forKey: .typeId)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
    }
}

// MARK: - Action item sequence (numeric IDs)

public struct VaultActionItemSequenceState: Codable, Sendable, Equatable {
    /// Next value to assign when creating a new action item (`numericId`).
    public var nextNumericId: Int

    public init(nextNumericId: Int = 1) {
        self.nextNumericId = nextNumericId
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
        id: String = UUID().uuidString,
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
        id: String = UUID().uuidString,
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
