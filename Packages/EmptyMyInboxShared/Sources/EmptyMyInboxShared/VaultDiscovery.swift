//
//  VaultDiscovery.swift
//  EmptyMyInboxShared
//
//  Lists local mirror vaults under Application Support (on-device `.local` and `.googleDrive` mirrors).
//

import Foundation

/// A vault whose data lives under `Vaults/<vaultId>/` (not external-folder bookmarks).
public struct DiscoveredVaultSummary: Identifiable, Sendable, Equatable {
    public var id: String { vaultId }
    public var vaultId: String
    public var backendKind: VaultBackendKind
    public var displayName: String?
    public var driveRootFolderId: String?
    public var driveAccountEmail: String?

    public init(
        vaultId: String,
        backendKind: VaultBackendKind,
        displayName: String? = nil,
        driveRootFolderId: String? = nil,
        driveAccountEmail: String? = nil
    ) {
        self.vaultId = vaultId
        self.backendKind = backendKind
        self.displayName = displayName
        self.driveRootFolderId = driveRootFolderId
        self.driveAccountEmail = driveAccountEmail
    }

    public var googleDriveRootWebURL: URL? {
        guard backendKind == .googleDrive else { return nil }
        guard let id = driveRootFolderId else { return nil }
        return GoogleDriveWebLinks.folderURL(folderId: id)
    }
}

/// A Google Drive vault discovered remotely via the Drive API, before this device has created a local mirror.
public struct DiscoveredRemoteGoogleDriveVaultSummary: Identifiable, Sendable, Equatable {
    public var id: String { driveRootFolderId }
    public var vaultId: String
    public var driveRootFolderId: String
    public var displayName: String?
    /// The signed-in Gmail account that successfully discovered and can sync this Drive vault on this device.
    public var connectedAccountEmail: String

    public init(
        vaultId: String,
        driveRootFolderId: String,
        displayName: String? = nil,
        connectedAccountEmail: String
    ) {
        self.vaultId = vaultId
        self.driveRootFolderId = driveRootFolderId
        self.displayName = displayName
        self.connectedAccountEmail = connectedAccountEmail
    }

    public var googleDriveRootWebURL: URL? {
        GoogleDriveWebLinks.folderURL(folderId: driveRootFolderId)
    }
}

public enum VaultDiscovery {
    /// Enumerates subfolders of `vaultsDirectory` that contain a readable `vault_manifest.json` for a local or Google Drive mirror.
    public static func discoverLocalMirrorVaults(
        vaultsDirectory: URL = VaultLocalFolderBackend.defaultVaultsDirectory()
    ) -> [DiscoveredVaultSummary] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: vaultsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var out: [DiscoveredVaultSummary] = []
        for dirURL in entries {
            guard let isDir = try? dirURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir == true else { continue }
            let manifestURL = dirURL.appendingPathComponent(VaultLayout.manifestFileName)
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? VaultJSON.decoder().decode(VaultManifest.self, from: data)
            else { continue }
            guard manifest.backendKind == .local || manifest.backendKind == .googleDrive else { continue }
            out.append(DiscoveredVaultSummary(
                vaultId: manifest.vaultId,
                backendKind: manifest.backendKind,
                displayName: manifest.displayName,
                driveRootFolderId: manifest.driveRootFolderId,
                driveAccountEmail: manifest.driveAccountEmail
            ))
        }
        return out.sorted {
            let a = $0.displayName ?? $0.vaultId
            let b = $1.displayName ?? $1.vaultId
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }
}
