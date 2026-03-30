//
//  GoogleDriveVaultAPI.swift
//  EmptyMyInboxShared
//
//  Minimal Google Drive v3 client for vault folder sync (files + folders).
//

import Foundation

public struct DriveVaultFileEntry: Sendable, Equatable {
    public var id: String
    public var relativePath: String
    public var modifiedTime: Date?
    public var mimeType: String
    public var md5Checksum: String?

    public init(id: String, relativePath: String, modifiedTime: Date?, mimeType: String, md5Checksum: String?) {
        self.id = id
        self.relativePath = relativePath
        self.modifiedTime = modifiedTime
        self.mimeType = mimeType
        self.md5Checksum = md5Checksum
    }
}

public enum GoogleDriveVaultAPI {
    private static let filesBase = "https://www.googleapis.com/drive/v3/files"
    private static let uploadBase = "https://www.googleapis.com/upload/drive/v3/files"

    private static let rfc3339: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let rfc3339NoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDriveDate(_ s: String) -> Date? {
        rfc3339.date(from: s) ?? rfc3339NoFrac.date(from: s)
    }

    // MARK: - Tree listing

    public static func buildRelativePathIndex(
        accessToken: String,
        rootFolderId: String,
        session: URLSession = .shared
    ) async throws -> [DriveVaultFileEntry] {
        var folderPathById: [String: String] = [rootFolderId: ""]
        var stack: [String] = [rootFolderId]
        var filesOut: [DriveVaultFileEntry] = []

        while let folderId = stack.popLast() {
            let children = try await listChildren(folderId: folderId, accessToken: accessToken, session: session)
            let parentPrefix = folderPathById[folderId] ?? ""
            for child in children {
                let name = child.name
                let rel: String
                if parentPrefix.isEmpty { rel = name }
                else { rel = "\(parentPrefix)/\(name)" }

                if child.mimeType == "application/vnd.google-apps.folder" {
                    folderPathById[child.id] = rel
                    stack.append(child.id)
                } else {
                    let mod = child.modifiedTime.flatMap { parseDriveDate($0) }
                    filesOut.append(DriveVaultFileEntry(
                        id: child.id,
                        relativePath: rel.replacingOccurrences(of: "\\", with: "/"),
                        modifiedTime: mod,
                        mimeType: child.mimeType,
                        md5Checksum: child.md5Checksum
                    ))
                }
            }
        }

        return filesOut
    }

    private struct DriveListItem: Decodable {
        let id: String
        let name: String
        let mimeType: String
        let modifiedTime: String?
        let md5Checksum: String?
    }

    private struct DriveListResponse: Decodable {
        let files: [DriveListItem]
        let nextPageToken: String?
    }

    private struct RemoteManifestCandidate {
        let folderId: String
        let folderName: String
        let manifestFileId: String
    }

    private static func listChildren(folderId: String, accessToken: String, session: URLSession) async throws -> [DriveListItem] {
        var all: [DriveListItem] = []
        var pageToken: String?
        repeat {
            var comp = URLComponents(string: filesBase)!
            let q = "'\(folderId)' in parents and trashed=false"
            comp.queryItems = [
                URLQueryItem(name: "q", value: q),
                URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType,modifiedTime,md5Checksum)"),
                URLQueryItem(name: "pageSize", value: "100")
            ]
            if let pageToken {
                comp.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            var req = URLRequest(url: comp.url!)
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw VaultError.driveAPIFailed(code, body)
            }
            let decoded = try JSONDecoder().decode(DriveListResponse.self, from: data)
            all.append(contentsOf: decoded.files)
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        return all
    }

    public static func discoverVaultsInRoot(
        accessToken: String,
        connectedAccountEmail: String,
        session: URLSession = .shared
    ) async throws -> [DiscoveredRemoteGoogleDriveVaultSummary] {
        let rootFolders = try await listChildren(folderId: "root", accessToken: accessToken, session: session)
            .filter { $0.mimeType == "application/vnd.google-apps.folder" }

        var candidates: [RemoteManifestCandidate] = []
        for folder in rootFolders {
            let children = try await listChildren(folderId: folder.id, accessToken: accessToken, session: session)
            if let manifest = children.first(where: {
                $0.name == VaultLayout.manifestFileName && $0.mimeType != "application/vnd.google-apps.folder"
            }) {
                candidates.append(RemoteManifestCandidate(
                    folderId: folder.id,
                    folderName: folder.name,
                    manifestFileId: manifest.id
                ))
            }
        }

        var discovered: [DiscoveredRemoteGoogleDriveVaultSummary] = []
        for candidate in candidates {
            guard let manifest = try await loadRemoteVaultManifest(
                manifestFileId: candidate.manifestFileId,
                accessToken: accessToken,
                session: session
            ) else { continue }
            guard manifest.backendKind == .googleDrive else { continue }
            discovered.append(DiscoveredRemoteGoogleDriveVaultSummary(
                vaultId: manifest.vaultId,
                driveRootFolderId: candidate.folderId,
                displayName: manifest.displayName ?? candidate.folderName,
                connectedAccountEmail: connectedAccountEmail
            ))
        }

        return discovered.sorted {
            let a = $0.displayName ?? $0.vaultId
            let b = $1.displayName ?? $1.vaultId
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    private static func loadRemoteVaultManifest(
        manifestFileId: String,
        accessToken: String,
        session: URLSession
    ) async throws -> VaultManifest? {
        let data = try await downloadMedia(fileId: manifestFileId, accessToken: accessToken, session: session)
        return try? VaultJSON.decoder().decode(VaultManifest.self, from: data)
    }

    // MARK: - Download / upload / update / delete

    public static func downloadMedia(fileId: String, accessToken: String, session: URLSession = .shared) async throws -> Data {
        var comp = URLComponents(string: "\(filesBase)/\(fileId)")!
        comp.queryItems = [URLQueryItem(name: "alt", value: "media")]
        var req = URLRequest(url: comp.url!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw VaultError.driveAPIFailed(code, body)
        }
        return data
    }

    public static func createFolder(name: String, parentId: String?, accessToken: String, session: URLSession = .shared) async throws -> String {
        var body: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder"
        ]
        if let parentId {
            body["parents"] = [parentId]
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        var comp = URLComponents(string: filesBase)!
        comp.queryItems = [
            URLQueryItem(name: "fields", value: "id")
        ]
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (respData, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            let bodyStr = String(data: respData, encoding: .utf8) ?? ""
            throw VaultError.driveAPIFailed(code, bodyStr)
        }
        let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any]
        guard let id = json?["id"] as? String else {
            throw VaultError.decodingFailed
        }
        return id
    }

    /// Multipart upload: create new file with JSON content under parent folder.
    public static func uploadNewFile(
        name: String,
        parentFolderId: String,
        data: Data,
        mimeType: String = "application/json",
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var comp = URLComponents(string: uploadBase)!
        comp.queryItems = [
            URLQueryItem(name: "uploadType", value: "multipart"),
            URLQueryItem(name: "fields", value: "id")
        ]
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let metadata: [String: Any] = [
            "name": name,
            "parents": [parentFolderId]
        ]
        let metaData = try JSONSerialization.data(withJSONObject: metadata)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metaData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (respData, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            let bodyStr = String(data: respData, encoding: .utf8) ?? ""
            throw VaultError.driveAPIFailed(code, bodyStr)
        }
        let json = try JSONSerialization.jsonObject(with: respData) as? [String: Any]
        guard let id = json?["id"] as? String else {
            throw VaultError.decodingFailed
        }
        return id
    }

    public static func updateFileMedia(
        fileId: String,
        data: Data,
        mimeType: String = "application/json",
        accessToken: String,
        session: URLSession = .shared
    ) async throws {
        var comp = URLComponents(string: "\(uploadBase)/\(fileId)")!
        comp.queryItems = [
            URLQueryItem(name: "uploadType", value: "media")
        ]
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (respData, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            let bodyStr = String(data: respData, encoding: .utf8) ?? ""
            throw VaultError.driveAPIFailed(code, bodyStr)
        }
    }

    public static func deleteFile(fileId: String, accessToken: String, session: URLSession = .shared) async throws {
        let url = URL(string: "\(filesBase)/\(fileId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 204 || code == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw VaultError.driveAPIFailed(code, bodyStr)
        }
    }

    /// Ensure folder `name` exists under parent; returns its ID.
    public static func ensureChildFolder(name: String, parentId: String, accessToken: String, session: URLSession = .shared) async throws -> String {
        let children = try await listChildren(folderId: parentId, accessToken: accessToken, session: session)
        if let existing = children.first(where: { $0.name == name && $0.mimeType == "application/vnd.google-apps.folder" }) {
            return existing.id
        }
        return try await createFolder(name: name, parentId: parentId, accessToken: accessToken, session: session)
    }

    /// Creates each path segment under `rootFolderId`; returns folder ID for the leaf directory.
    public static func ensureDriveFolderPath(
        relativeDir: String,
        rootFolderId: String,
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> String {
        let parts = relativeDir.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        var current = rootFolderId
        for part in parts {
            current = try await ensureChildFolder(name: part, parentId: current, accessToken: accessToken, session: session)
        }
        return current
    }

    public static func fetchModifiedTime(fileId: String, accessToken: String, session: URLSession = .shared) async throws -> Date? {
        var comp = URLComponents(string: "\(filesBase)/\(fileId)")!
        comp.queryItems = [URLQueryItem(name: "fields", value: "modifiedTime")]
        var req = URLRequest(url: comp.url!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else { return nil }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let s = json?["modifiedTime"] as? String else { return nil }
        return parseDriveDate(s)
    }
}
