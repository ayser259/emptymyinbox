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
            updatedAt: Date()
        )
        let data = try VaultJSON.encoder().encode(manifest)
        try await folderBackend.write(relativePath: manifestPath, data: data)
    }
}
