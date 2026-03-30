//
//  SenderCache.swift
//  emptyMyInbox
//
//  Persistent cache for sender data and unsubscribe availability
//

import Foundation

public struct CachedSenderData: Codable {
    public let senderEmail: String
    public let senderName: String
    public let totalCount30Days: Int
    public let unreadCount30Days: Int
    public let starredCount30Days: Int
    public let recentSubjects: [String]
    public let hasUnsubscribe: Bool
    public let lastUpdated: Date
    public let accountEmail: String
    
    public init(
        senderEmail: String,
        senderName: String,
        totalCount30Days: Int,
        unreadCount30Days: Int,
        starredCount30Days: Int,
        recentSubjects: [String],
        hasUnsubscribe: Bool,
        lastUpdated: Date,
        accountEmail: String
    ) {
        self.senderEmail = senderEmail
        self.senderName = senderName
        self.totalCount30Days = totalCount30Days
        self.unreadCount30Days = unreadCount30Days
        self.starredCount30Days = starredCount30Days
        self.recentSubjects = recentSubjects
        self.hasUnsubscribe = hasUnsubscribe
        self.lastUpdated = lastUpdated
        self.accountEmail = accountEmail
    }
}

public struct SenderCacheSnapshot: Codable {
    public let timestamp: Date
    public let senders: [CachedSenderData]
    public let accountEmail: String
    
    public init(timestamp: Date, senders: [CachedSenderData], accountEmail: String) {
        self.timestamp = timestamp
        self.senders = senders
        self.accountEmail = accountEmail
    }
}

public actor SenderCache {
    public static let shared = SenderCache()
    
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    
    private init() {
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        
        // Use application support directory for persistence
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        fileURL = directory.appendingPathComponent("sender_cache.json")
        
        // Configure date encoding/decoding
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    /// Load cached sender data
    public func loadSenders(accountEmail: String) -> [CachedSenderData] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try decoder.decode(SenderCacheSnapshot.self, from: data)
            
            // Filter by account email and return senders
            return snapshot.senders.filter { $0.accountEmail == accountEmail }
        } catch {
            logError("SenderCache load error: \(error)", category: "Cache")
            return []
        }
    }
    
    /// Save sender data
    public func saveSenders(_ senders: [CachedSenderData], accountEmail: String) {
        // Load existing cache
        var allSenders: [CachedSenderData] = []
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let existingSnapshot = try? decoder.decode(SenderCacheSnapshot.self, from: data) {
            // Keep senders from other accounts
            allSenders = existingSnapshot.senders.filter { $0.accountEmail != accountEmail }
        }
        
        // Add new senders for this account
        allSenders.append(contentsOf: senders)
        
        // Create new snapshot
        let snapshot = SenderCacheSnapshot(
            timestamp: Date(),
            senders: allSenders,
            accountEmail: accountEmail
        )
        
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            logSuccess("SenderCache: Saved \(senders.count) senders for account \(accountEmail)", category: "Cache")
        } catch {
            logError("SenderCache save error: \(error)", category: "Cache")
        }
    }
    
    /// Update unsubscribe availability for a sender
    public func updateUnsubscribeAvailability(senderEmail: String, accountEmail: String, hasUnsubscribe: Bool) {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              var snapshot = try? decoder.decode(SenderCacheSnapshot.self, from: data) else {
            return
        }
        
        // Find and update the sender
        if let index = snapshot.senders.firstIndex(where: { 
            $0.senderEmail == senderEmail && $0.accountEmail == accountEmail 
        }) {
            let updatedSender = snapshot.senders[index]
            // Create updated version
            let updated = CachedSenderData(
                senderEmail: updatedSender.senderEmail,
                senderName: updatedSender.senderName,
                totalCount30Days: updatedSender.totalCount30Days,
                unreadCount30Days: updatedSender.unreadCount30Days,
                starredCount30Days: updatedSender.starredCount30Days,
                recentSubjects: updatedSender.recentSubjects,
                hasUnsubscribe: hasUnsubscribe,
                lastUpdated: Date(),
                accountEmail: updatedSender.accountEmail
            )
            // Create new array with updated sender using map
            let updatedSenders = snapshot.senders.enumerated().map { idx, sender in
                idx == index ? updated : sender
            }
            // Create new snapshot with updated senders
            snapshot = SenderCacheSnapshot(
                timestamp: snapshot.timestamp,
                senders: updatedSenders,
                accountEmail: snapshot.accountEmail
            )
        }
        
        // Save updated snapshot
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logError("SenderCache update error: \(error)", category: "Cache")
        }
    }
    
    /// Clear cache for a specific account
    public func clear(accountEmail: String) {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              var snapshot = try? decoder.decode(SenderCacheSnapshot.self, from: data) else {
            return
        }
        
        // Remove senders for this account
        let filteredSenders = snapshot.senders.filter { $0.accountEmail != accountEmail }
        // Create new snapshot with filtered senders
        snapshot = SenderCacheSnapshot(
            timestamp: snapshot.timestamp,
            senders: filteredSenders,
            accountEmail: snapshot.accountEmail
        )
        
        // Save updated snapshot
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logError("SenderCache clear error: \(error)", category: "Cache")
        }
    }
    
    /// Clear all cached sender data
    public func clearAll() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            logError("SenderCache clearAll error: \(error)", category: "Cache")
        }
    }
}

