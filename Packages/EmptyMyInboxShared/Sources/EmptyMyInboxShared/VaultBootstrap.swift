//
//  VaultBootstrap.swift
//  EmptyMyInboxShared
//

import Foundation

public enum VaultBootstrap {
    public static func ensureManifestIfMissing(
        folderBackend: any VaultFolderBackend,
        configuration: VaultActiveConfiguration
    ) async throws {
        let manifestPath = VaultLayout.manifestFileName
        if (try? await folderBackend.read(relativePath: manifestPath)) != nil {
            return
        }
        let manifest = VaultManifest(
            vaultId: configuration.vaultId,
            schemaVersion: VaultLayout.currentSchemaVersion,
            backendKind: configuration.backend,
            createdAt: Date(),
            updatedAt: Date(),
            driveRootFolderId: configuration.driveRootFolderId,
            driveAccountEmail: configuration.driveAccountEmail,
            displayName: configuration.displayName
        )
        let data = try VaultJSON.encoder().encode(manifest)
        try await folderBackend.write(relativePath: manifestPath, data: data)
    }

    /// Fills Drive metadata (and display name) on disk from prefs so older vaults can be reopened after sync.
    public static func mergeManifestMetadataFromConfiguration(
        folderBackend: any VaultFolderBackend,
        configuration: VaultActiveConfiguration
    ) async throws {
        let manifestPath = VaultLayout.manifestFileName
        guard let data = try? await folderBackend.read(relativePath: manifestPath) else { return }
        var manifest = try VaultJSON.decoder().decode(VaultManifest.self, from: data)
        if configuration.backend == .googleDrive {
            if manifest.driveRootFolderId == nil { manifest.driveRootFolderId = configuration.driveRootFolderId }
            if manifest.driveAccountEmail == nil { manifest.driveAccountEmail = configuration.driveAccountEmail }
        }
        if manifest.displayName == nil, let name = configuration.displayName, !name.isEmpty {
            manifest.displayName = name
        }
        manifest.updatedAt = Date()
        let out = try VaultJSON.encoder().encode(manifest)
        try await folderBackend.write(relativePath: manifestPath, data: out)
    }
}
