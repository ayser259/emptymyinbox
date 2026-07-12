//
//  VaultModels.swift
//  ProjectJadeShared
//
//  Shared types for vault layout: Inbox/ + manifest and envelopes.
//

import Foundation

// MARK: - Layout constants

/// Relative paths under the vault root (`vault_manifest.json` lives at the root next to `Inbox/`).
///
/// **iOS and macOS** both use `ProjectJadeShared` only: there are no platform-specific filenames for vault data. The same `VaultLayout` strings are passed to `VaultFolderBackend` on every platform.
///
/// **Multiple devices** see the same logical files when they use the **same vault configuration**—for `.googleDrive`, the same Gmail account and `driveRootFolderId` so `VaultSyncCoordinator` pulls/pushes the same paths on Drive. Purely local vaults (`.local`) are per-machine unless you point both apps at the same folder via `.externalFolder` with a synced directory.
public enum VaultLayout {
    public static let manifestFileName = "vault_manifest.json"
    public static let syncLogFileName = "vault_sync_log.json"
    public static let inboxFolder = "Inbox"
    public static let storiesFolder = "Stories"
    public static let briefFolder = "Brief"
    public static let inboxThreadsSubfolder = "threads"
    public static let storiesFeedFileName = "stories_feed.json"
    public static let storiesBookmarkedFileName = "bookmarked_stories.json"
    public static let briefDailyFileName = "daily_brief.json"

    public static let currentSchemaVersion = 1

    public static func standardSubfolders() -> [String] {
        [
            "\(inboxFolder)/\(inboxThreadsSubfolder)",
            storiesFolder,
            briefFolder
        ]
    }

    public static var storiesFeedAggregatePath: String {
        "\(storiesFolder)/\(storiesFeedFileName)"
    }

    public static var storiesBookmarkedAggregatePath: String {
        "\(storiesFolder)/\(storiesBookmarkedFileName)"
    }

    public static var briefDailyAggregatePath: String {
        "\(briefFolder)/\(briefDailyFileName)"
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
    /// Google Drive folder ID for vault root (contains Inbox)
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

// MARK: - Stories & Brief (vault mirrors)

/// Full stories feed snapshot for vault sync (matches `StoriesFeedStore` logical state).
public struct VaultStoriesFeedPayload: Codable, Sendable {
    public var stories: [InsightCard]
    public var bookmarkedStoryIds: [Int]
    public var reviewedStoryIds: [Int]
    public var lastGeneratedAt: Date?
    public var promptStates: [Int: StoryPromptState]

    public init(
        stories: [InsightCard] = [],
        bookmarkedStoryIds: [Int] = [],
        reviewedStoryIds: [Int] = [],
        lastGeneratedAt: Date? = nil,
        promptStates: [Int: StoryPromptState] = [:]
    ) {
        self.stories = stories
        self.bookmarkedStoryIds = bookmarkedStoryIds
        self.reviewedStoryIds = reviewedStoryIds
        self.lastGeneratedAt = lastGeneratedAt
        self.promptStates = promptStates
    }
}

/// Bookmarked-only mirror for easy browsing in the vault folder.
public struct VaultStoriesBookmarkedPayload: Codable, Sendable {
    public var stories: [InsightCard]

    public init(stories: [InsightCard] = []) {
        self.stories = stories
    }
}

// MARK: - Sector-relative paths

public enum VaultSector: String, Sendable, CaseIterable {
    case inbox

    public var rootFolderName: String {
        switch self {
        case .inbox: return VaultLayout.inboxFolder
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
