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

    public static let currentSchemaVersion = 1

    public static func standardSubfolders() -> [String] {
        [
            "\(inboxFolder)/\(inboxThreadsSubfolder)",
            "\(calendarFolder)/\(calendarEventsSubfolder)",
            "\(actionItemsFolder)/\(actionItemsSubfolder)"
        ]
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

public struct VaultActionItemRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var isDone: Bool
    public var notes: String?

    public init(id: String = UUID().uuidString, title: String, isDone: Bool = false, notes: String? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.notes = notes
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
