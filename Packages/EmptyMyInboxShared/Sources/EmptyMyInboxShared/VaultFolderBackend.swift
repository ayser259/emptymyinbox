//
//  VaultFolderBackend.swift
//  EmptyMyInboxShared
//
//  Filesystem access under a vault root (local app folder or security-scoped external folder).
//

import Foundation

#if os(macOS)
private let vaultBookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
private let vaultBookmarkCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
#else
private let vaultBookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
private let vaultBookmarkCreationOptions: URL.BookmarkCreationOptions = []
#endif

public protocol VaultFolderBackend: AnyObject, Sendable {
    nonisolated var vaultRoot: URL { get }
    func ensureStructure() async throws
    func read(relativePath: String) async throws -> Data
    func write(relativePath: String, data: Data) async throws
    func remove(relativePath: String) async throws
    /// All files under vault root, paths like `Inbox/threads/foo.json` (forward slashes).
    func listRelativeFilePaths() async throws -> [String]
}

// MARK: - Local

public final class VaultLocalFolderBackend: VaultFolderBackend, @unchecked Sendable {
    public let vaultRoot: URL

    public init(vaultRoot: URL) {
        self.vaultRoot = vaultRoot
    }

    public static func defaultVaultsDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("emptyMyInbox/Vaults", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static func localRoot(forVaultId id: String) -> URL {
        defaultVaultsDirectory().appendingPathComponent(id, isDirectory: true)
    }

    public func ensureStructure() async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: vaultRoot.path) {
            try fm.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        }
        for sub in VaultLayout.standardSubfolders() {
            let url = vaultRoot.appendingPathComponent(sub, isDirectory: true)
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    public func read(relativePath: String) async throws -> Data {
        let url = try Self.resolveVaultURL(vaultRoot: vaultRoot, relativePath: relativePath)
        return try Data(contentsOf: url)
    }

    public func write(relativePath: String, data: Data) async throws {
        let url = try Self.resolveVaultURL(vaultRoot: vaultRoot, relativePath: relativePath)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func remove(relativePath: String) async throws {
        let url = try Self.resolveVaultURL(vaultRoot: vaultRoot, relativePath: relativePath)
        try FileManager.default.removeItem(at: url)
    }

    public func listRelativeFilePaths() async throws -> [String] {
        let fm = FileManager.default
        let rootURL = vaultRoot.standardizedFileURL
        guard fm.fileExists(atPath: rootURL.path) else { return [] }
        let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var out: [String] = []
        let rootPath = rootURL.path
        while let item = enumerator?.nextObject() as? URL {
            let isFile = (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isFile else { continue }
            let itemPath = item.standardizedFileURL.path
            guard itemPath.hasPrefix(rootPath) else { continue }
            var rel = String(itemPath.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            if rel.hasSuffix(".DS_Store") { continue }
            out.append(rel.replacingOccurrences(of: "\\", with: "/"))
        }
        return out.sorted()
    }

    public static func resolveVaultURL(vaultRoot: URL, relativePath: String) throws -> URL {
        let norm = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard !norm.contains("..") else { throw VaultError.invalidPath(relativePath) }
        return vaultRoot.appendingPathComponent(norm)
    }

}

// MARK: - External (security-scoped bookmark)

public final class VaultExternalFolderBackend: VaultFolderBackend, @unchecked Sendable {
    public let vaultRoot: URL
    private let bookmarkData: Data

    public init(bookmarkData: Data) throws {
        self.bookmarkData = bookmarkData
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: vaultBookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            throw VaultError.bookmarkResolveFailed
        }
        self.vaultRoot = url
    }

    /// Re-resolve if stale; caller should persist new bookmark via `refreshedBookmarkData()`.
    public func refreshedBookmarkData() throws -> Data {
        var stale = false
        _ = try URL(
            resolvingBookmarkData: bookmarkData,
            options: vaultBookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return try vaultRoot.bookmarkData(options: vaultBookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func withSecurityScope<T>(_ work: () throws -> T) throws -> T {
        guard vaultRoot.startAccessingSecurityScopedResource() else {
            throw VaultError.securityScopeDenied
        }
        defer { vaultRoot.stopAccessingSecurityScopedResource() }
        return try work()
    }

    public func ensureStructure() async throws {
        try await Task {
            try self.withSecurityScope {
                let fm = FileManager.default
                if !fm.fileExists(atPath: self.vaultRoot.path) {
                    try fm.createDirectory(at: self.vaultRoot, withIntermediateDirectories: true)
                }
                for sub in VaultLayout.standardSubfolders() {
                    let url = self.vaultRoot.appendingPathComponent(sub, isDirectory: true)
                    if !fm.fileExists(atPath: url.path) {
                        try fm.createDirectory(at: url, withIntermediateDirectories: true)
                    }
                }
            }
        }.value
    }

    public func read(relativePath: String) async throws -> Data {
        try await Task {
            try self.withSecurityScope {
                let url = try VaultLocalFolderBackend.resolveVaultURL(vaultRoot: self.vaultRoot, relativePath: relativePath)
                return try Data(contentsOf: url)
            }
        }.value
    }

    public func write(relativePath: String, data: Data) async throws {
        try await Task {
            try self.withSecurityScope {
                let url = try VaultLocalFolderBackend.resolveVaultURL(vaultRoot: self.vaultRoot, relativePath: relativePath)
                let parent = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
        }.value
    }

    public func remove(relativePath: String) async throws {
        try await Task {
            try self.withSecurityScope {
                let url = try VaultLocalFolderBackend.resolveVaultURL(vaultRoot: self.vaultRoot, relativePath: relativePath)
                try FileManager.default.removeItem(at: url)
            }
        }.value
    }

    public func listRelativeFilePaths() async throws -> [String] {
        try await Task {
            try self.withSecurityScope {
                let fm = FileManager.default
                let rootURL = self.vaultRoot.standardizedFileURL
                guard fm.fileExists(atPath: rootURL.path) else { return [] as [String] }
                let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                var out: [String] = []
                let rootPath = rootURL.path
                while let item = enumerator?.nextObject() as? URL {
                    let isFile = (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                    guard isFile else { continue }
                    let itemPath = item.standardizedFileURL.path
                    guard itemPath.hasPrefix(rootPath) else { continue }
                    var rel = String(itemPath.dropFirst(rootPath.count))
                    if rel.hasPrefix("/") { rel.removeFirst() }
                    if rel.hasSuffix(".DS_Store") { continue }
                    out.append(rel.replacingOccurrences(of: "\\", with: "/"))
                }
                return out.sorted()
            }
        }.value
    }
}
