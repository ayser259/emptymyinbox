//
//  VaultSyncCoordinator.swift
//  EmptyMyInboxShared
//
//  Pull-then-push sync between local vault mirror and Google Drive (LWW).
//

import Foundation

public enum VaultSyncCoordinator {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 120
        return URLSession(configuration: c)
    }()

    /// Sync local folder mirror with Google Drive when backend is `.googleDrive`.
    public static func syncGoogleDriveVault(
        configuration: VaultActiveConfiguration,
        folderBackend: any VaultFolderBackend,
        accessToken: String
    ) async throws {
        guard configuration.backend == .googleDrive,
              let rootId = configuration.driveRootFolderId
        else {
            return
        }

        try await folderBackend.ensureStructure()

        let remote = try await GoogleDriveVaultAPI.buildRelativePathIndex(
            accessToken: accessToken,
            rootFolderId: rootId,
            session: session
        )
        var remoteByPath = Dictionary(uniqueKeysWithValues: remote.map { ($0.relativePath, $0) })

        let localPaths = try await folderBackend.listRelativeFilePaths()
        var localSet = Set(localPaths)

        // Pull: for each remote file, merge into local if remote wins or missing locally
        for entry in remote {
            let path = entry.relativePath
            let remoteData = try await GoogleDriveVaultAPI.downloadMedia(fileId: entry.id, accessToken: accessToken, session: session)
            let remoteMeta = VaultLWWHelpers.parseEnvelopeMeta(from: remoteData) ?? .init(updatedAt: entry.modifiedTime, writeToken: nil)

            if localSet.contains(path) {
                let localData = try await folderBackend.read(relativePath: path)
                let localMeta = VaultLWWHelpers.parseEnvelopeMeta(from: localData)
                let localMod = try? localFileModificationDate(folderBackend: folderBackend, relativePath: path)
                let preferLocal: Bool
                if let localMeta {
                    preferLocal = VaultLWWHelpers.shouldPreferLocal(
                        localMeta: localMeta,
                        localFileModDate: localMod,
                        remoteMeta: remoteMeta,
                        remoteDriveModified: entry.modifiedTime
                    )
                } else {
                    preferLocal = false
                }
                if !preferLocal {
                    try await folderBackend.write(relativePath: path, data: remoteData)
                }
            } else {
                try await folderBackend.write(relativePath: path, data: remoteData)
                localSet.insert(path)
            }
        }

        // Push: local files that are newer than remote or absent on remote
        for path in localPaths.sorted() {
            let localData = try await folderBackend.read(relativePath: path)
            let localMeta = VaultLWWHelpers.parseEnvelopeMeta(from: localData)
            let localMod = try? localFileModificationDate(folderBackend: folderBackend, relativePath: path)

            if let remoteEntry = remoteByPath[path] {
                let remoteData = try await GoogleDriveVaultAPI.downloadMedia(fileId: remoteEntry.id, accessToken: accessToken, session: session)
                let remoteMeta = VaultLWWHelpers.parseEnvelopeMeta(from: remoteData) ?? .init(updatedAt: remoteEntry.modifiedTime, writeToken: nil)
                let preferLocal: Bool
                if let localMeta {
                    preferLocal = VaultLWWHelpers.shouldPreferLocal(
                        localMeta: localMeta,
                        localFileModDate: localMod,
                        remoteMeta: remoteMeta,
                        remoteDriveModified: remoteEntry.modifiedTime
                    )
                } else {
                    preferLocal = true
                }
                if preferLocal {
                    try await GoogleDriveVaultAPI.updateFileMedia(
                        fileId: remoteEntry.id,
                        data: localData,
                        accessToken: accessToken,
                        session: session
                    )
                }
            } else {
                let parentRel = (path as NSString).deletingLastPathComponent
                let fileName = (path as NSString).lastPathComponent
                let parentFolderId: String
                if parentRel.isEmpty {
                    parentFolderId = rootId
                } else {
                    parentFolderId = try await GoogleDriveVaultAPI.ensureDriveFolderPath(
                        relativeDir: parentRel.replacingOccurrences(of: "\\", with: "/"),
                        rootFolderId: rootId,
                        accessToken: accessToken,
                        session: session
                    )
                }
                let newId = try await GoogleDriveVaultAPI.uploadNewFile(
                    name: fileName,
                    parentFolderId: parentFolderId,
                    data: localData,
                    accessToken: accessToken,
                    session: session
                )
                let mod = try await GoogleDriveVaultAPI.fetchModifiedTime(fileId: newId, accessToken: accessToken, session: session)
                remoteByPath[path] = DriveVaultFileEntry(
                    id: newId,
                    relativePath: path,
                    modifiedTime: mod,
                    mimeType: "application/json",
                    md5Checksum: nil
                )
            }
        }

        // Update manifest timestamps on disk
        try await updateManifestAfterSync(folderBackend: folderBackend)
    }

    private static func localFileModificationDate(folderBackend: any VaultFolderBackend, relativePath: String) throws -> Date? {
        let url = try VaultLocalFolderBackend.resolveVaultURL(vaultRoot: folderBackend.vaultRoot, relativePath: relativePath)
        let vals = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return vals.contentModificationDate
    }

    private static func updateManifestAfterSync(folderBackend: any VaultFolderBackend) async throws {
        let data = try await folderBackend.read(relativePath: VaultLayout.manifestFileName)
        var manifest = try VaultJSON.decoder().decode(VaultManifest.self, from: data)
        manifest.lastSuccessfulSyncAt = Date()
        manifest.updatedAt = Date()
        let out = try VaultJSON.encoder().encode(manifest)
        try await folderBackend.write(relativePath: VaultLayout.manifestFileName, data: out)
    }
}
