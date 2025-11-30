//
//  MockFileManager.swift
//  emptyMyInboxTests
//
//  Mock FileManager for testing file operations
//

import Foundation

class MockFileManager {
    // In-memory file storage
    private var files: [String: Data] = [:]
    private var directories: Set<String> = []
    
    // Behavior control
    var shouldFailWrite = false
    var shouldFailRead = false
    var writeError: Error?
    var readError: Error?
    
    // Call tracking
    var writeCallCount = 0
    var readCallCount = 0
    var deleteCallCount = 0
    var createDirectoryCallCount = 0
    
    init() {
        // Initialize with some default directories
        directories.insert("/")
        directories.insert("/tmp")
    }
    
    // MARK: - File Operations
    
    func fileExists(atPath path: String) -> Bool {
        return files[path] != nil || directories.contains(path)
    }
    
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        createDirectoryCallCount += 1
        let path = url.path
        directories.insert(path)
        
        if withIntermediateDirectories {
            // Create parent directories too
            var currentPath = (path as NSString).deletingLastPathComponent
            while !currentPath.isEmpty && currentPath != "/" {
                directories.insert(currentPath)
                currentPath = (currentPath as NSString).deletingLastPathComponent
            }
        }
    }
    
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?) throws -> [URL] {
        let path = url.path
        guard directories.contains(path) else {
            throw NSError(domain: "MockFileManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Directory does not exist"])
        }
        
        var urls: [URL] = []
        for (filePath, _) in files {
            if (filePath as NSString).deletingLastPathComponent == path {
                urls.append(URL(fileURLWithPath: filePath))
            }
        }
        
        return urls
    }
    
    func removeItem(at url: URL) throws {
        deleteCallCount += 1
        let path = url.path
        
        if files[path] != nil {
            files.removeValue(forKey: path)
        } else if directories.contains(path) {
            directories.remove(path)
            // Remove all files in this directory
            let keysToRemove = files.keys.filter { $0.hasPrefix(path) }
            for key in keysToRemove {
                files.removeValue(forKey: key)
            }
        }
    }
    
    // MARK: - Data Operations
    
    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        writeCallCount += 1
        
        if shouldFailWrite {
            throw writeError ?? NSError(domain: "MockFileManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Write failed"])
        }
        
        let path = url.path
        files[path] = data
        
        // Ensure parent directory exists
        let parentPath = (path as NSString).deletingLastPathComponent
        if !parentPath.isEmpty {
            directories.insert(parentPath)
        }
    }
    
    func contents(atPath path: String) -> Data? {
        readCallCount += 1
        
        if shouldFailRead {
            return nil
        }
        
        return files[path]
    }
    
    // MARK: - Test Helpers
    
    func setFile(_ data: Data, atPath path: String) {
        files[path] = data
    }
    
    func getFile(atPath path: String) -> Data? {
        return files[path]
    }
    
    func clearAll() {
        files.removeAll()
        directories.removeAll()
        directories.insert("/")
        directories.insert("/tmp")
    }
    
    func getAllFilePaths() -> [String] {
        return Array(files.keys)
    }
    
    func getAllDirectories() -> [String] {
        return Array(directories)
    }
}
