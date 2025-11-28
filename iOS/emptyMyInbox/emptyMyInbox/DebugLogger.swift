//
//  DebugLogger.swift
//  emptyMyInbox
//
//  In-app debug logger for reviewing logs without Xcode
//

import Foundation
import SwiftUI

/// Log entry with timestamp and level
struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    let category: String?
    
    init(level: LogLevel, message: String, category: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.category = category
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    var fullTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

enum LogLevel: String, Codable, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    case success = "OK"
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .success: return "✅"
        }
    }
    
    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}

/// Singleton debug logger that stores logs in memory with persistence
@MainActor
class DebugLogger: ObservableObject {
    static let shared = DebugLogger()
    
    @Published private(set) var entries: [LogEntry] = []
    @Published var isEnabled: Bool = true
    
    private let maxEntries = 1000
    private let persistenceKey = "debug_logs"
    private let queue = DispatchQueue(label: "com.emptymyinbox.debuglogger", qos: .utility)
    
    private init() {
        loadPersistedLogs()
    }
    
    // MARK: - Logging Methods
    
    func log(_ message: String, level: LogLevel = .info, category: String? = nil) {
        guard isEnabled else { return }
        
        let entry = LogEntry(level: level, message: message, category: category)
        entries.append(entry)
        
        // Trim old entries if needed
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        
        // Also print to console for Xcode debugging
        let prefix = category.map { "[\($0)] " } ?? ""
        print("\(level.emoji) \(prefix)\(message)")
        
        // Persist asynchronously
        persistLogs()
    }
    
    func debug(_ message: String, category: String? = nil) {
        log(message, level: .debug, category: category)
    }
    
    func info(_ message: String, category: String? = nil) {
        log(message, level: .info, category: category)
    }
    
    func warning(_ message: String, category: String? = nil) {
        log(message, level: .warning, category: category)
    }
    
    func error(_ message: String, category: String? = nil) {
        log(message, level: .error, category: category)
    }
    
    func success(_ message: String, category: String? = nil) {
        log(message, level: .success, category: category)
    }
    
    // MARK: - Log Management
    
    func clear() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }
    
    func exportAsText() -> String {
        let header = """
        =====================================
        Empty My Inbox - Debug Log Export
        Exported: \(Date().formatted())
        Device: \(UIDevice.current.model)
        iOS: \(UIDevice.current.systemVersion)
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        =====================================
        
        """
        
        let logLines = entries.map { entry in
            let category = entry.category.map { "[\($0)] " } ?? ""
            return "[\(entry.fullTimestamp)] [\(entry.level.rawValue)] \(category)\(entry.message)"
        }.joined(separator: "\n")
        
        return header + logLines
    }
    
    // MARK: - Filtering
    
    func filteredEntries(level: LogLevel? = nil, category: String? = nil, searchText: String = "") -> [LogEntry] {
        entries.filter { entry in
            var matches = true
            
            if let level = level {
                matches = matches && entry.level == level
            }
            
            if let category = category {
                matches = matches && entry.category == category
            }
            
            if !searchText.isEmpty {
                matches = matches && entry.message.localizedCaseInsensitiveContains(searchText)
            }
            
            return matches
        }
    }
    
    var categories: [String] {
        Array(Set(entries.compactMap { $0.category })).sorted()
    }
    
    // MARK: - Persistence
    
    private func persistLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            Task { @MainActor in
                // Keep only last 500 entries for persistence
                let entriesToSave = Array(self.entries.suffix(500))
                
                if let data = try? JSONEncoder().encode(entriesToSave) {
                    UserDefaults.standard.set(data, forKey: self.persistenceKey)
                }
            }
        }
    }
    
    private func loadPersistedLogs() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let savedEntries = try? JSONDecoder().decode([LogEntry].self, from: data) {
            entries = savedEntries
            
            // Add startup log
            log("App launched - loaded \(savedEntries.count) persisted log entries", level: .info, category: "System")
        } else {
            log("App launched - fresh log session", level: .info, category: "System")
        }
    }
}

// MARK: - Global Logging Functions

/// Convenience function to log debug messages
func logDebug(_ message: String, category: String? = nil) {
    Task { @MainActor in
        DebugLogger.shared.debug(message, category: category)
    }
}

/// Convenience function to log info messages
func logInfo(_ message: String, category: String? = nil) {
    Task { @MainActor in
        DebugLogger.shared.info(message, category: category)
    }
}

/// Convenience function to log warnings
func logWarning(_ message: String, category: String? = nil) {
    Task { @MainActor in
        DebugLogger.shared.warning(message, category: category)
    }
}

/// Convenience function to log errors
func logError(_ message: String, category: String? = nil) {
    Task { @MainActor in
        DebugLogger.shared.error(message, category: category)
    }
}

/// Convenience function to log success
func logSuccess(_ message: String, category: String? = nil) {
    Task { @MainActor in
        DebugLogger.shared.success(message, category: category)
    }
}

