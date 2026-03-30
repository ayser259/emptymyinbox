//
//  EmailCache.swift
//  emptyMyInbox
//
//  Persistent caching layer for email metadata and full email details.
//  - Metadata: Lightweight email list data for fast loading
//  - Full Details: Complete email content stored on disk for offline access
//

import Foundation

public actor EmailCache {
    public static let shared = EmailCache()
    private nonisolated static let stableIdMigrationKey = "EmailCacheStableIdMigrationV1"
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private let baseDirectoryURL: URL
    private let defaultMetadataURL: URL
    private let emailDetailsDirectoryURL: URL
    private let emailIndexURL: URL
    
    // In-memory cache for quick access (LRU-style)
    private var memoryCache: [Int: EmailDetail] = [:]
    private var memoryCacheAccessOrder: [Int] = []
    private let maxMemoryCacheSize = 50
    
    // Index of all cached email IDs for quick lookup
    private var cachedEmailIndex: Set<Int> = []
    private var gmailToEmailIndex: [String: Int] = [:]
    
    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        baseDirectoryURL = directory.appendingPathComponent("EmailCache", isDirectory: true)
        defaultMetadataURL = baseDirectoryURL.appendingPathComponent("metadata.json")
        emailDetailsDirectoryURL = baseDirectoryURL.appendingPathComponent("details", isDirectory: true)
        emailIndexURL = baseDirectoryURL.appendingPathComponent("email_index.json")
        
        // Create directories if needed
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseDirectoryURL.path) {
            try? fm.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: emailDetailsDirectoryURL.path) {
            try? fm.createDirectory(at: emailDetailsDirectoryURL, withIntermediateDirectories: true)
        }
        Self.performStableIdMigrationIfNeeded(
            baseDirectoryURL: baseDirectoryURL,
            defaultMetadataURL: defaultMetadataURL,
            emailDetailsDirectoryURL: emailDetailsDirectoryURL,
            emailIndexURL: emailIndexURL
        )
        
        // Load email index
        cachedEmailIndex = Self.readEmailIndex(from: emailIndexURL)
        Task {
            await rebuildGmailIndexIfNeeded()
        }
        logInfo("EmailCache: Loaded index with \(cachedEmailIndex.count) cached emails", category: "Cache")
    }
    
    // MARK: - Email Index Management
    
    private nonisolated static func readEmailIndex(from url: URL) -> Set<Int> {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([Int].self, from: data) else {
            return []
        }
        return Set(ids)
    }
    
    private func saveEmailIndex() {
        do {
            let data = try JSONEncoder().encode(Array(cachedEmailIndex))
            try data.write(to: emailIndexURL, options: .atomic)
        } catch {
            logError("EmailCache saveEmailIndex error: \(error)", category: "Cache")
        }
    }
    
    /// Check if an email detail is cached on disk
    public func isEmailCached(emailId: Int) -> Bool {
        return cachedEmailIndex.contains(emailId)
    }
    
    /// Check if an email detail is cached (by Gmail ID)
    public func isEmailCached(gmailId: String) async -> Bool {
        let deterministicId = StableID.emailId(gmailId: gmailId)
        if cachedEmailIndex.contains(deterministicId) {
            return true
        }
        
        if let indexedId = gmailToEmailIndex[gmailId], cachedEmailIndex.contains(indexedId) {
            return true
        }
        
        // Need to check all cached files - this is slower but accurate
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: emailDetailsDirectoryURL, includingPropertiesForKeys: nil) else {
            return false
        }
        
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let detail = try? decoder.decode(EmailDetail.self, from: data),
               detail.gmail_id == gmailId {
                gmailToEmailIndex[gmailId] = detail.id
                return true
            }
        }
        return false
    }
    
    /// Get count of cached emails
    public func cachedEmailCount() -> Int {
        return cachedEmailIndex.count
    }
    
    // MARK: - Clear All
    
    public func clearAll() {
        let fm = FileManager.default
        
        // Clear base directory files
        if let files = try? fm.contentsOfDirectory(at: baseDirectoryURL, includingPropertiesForKeys: nil, options: []) {
            for file in files {
                try? fm.removeItem(at: file)
            }
        }
        
        // Recreate details directory
        try? fm.createDirectory(at: emailDetailsDirectoryURL, withIntermediateDirectories: true)
        
        // Clear in-memory state
        memoryCache.removeAll()
        memoryCacheAccessOrder.removeAll()
        cachedEmailIndex.removeAll()
        gmailToEmailIndex.removeAll()
    }
    
    // MARK: - Metadata Cache (Lightweight)
    
    /// Load cached email metadata for an account
    public func loadEmailMetadata(accountId: Int? = nil) async -> [EmailMetadata] {
        let url = metadataURL(for: accountId)
        return await Task.detached(priority: .utility) { [baseDirectoryURL] in
            guard FileManager.default.fileExists(atPath: url.path) else {
                if let accountId {
                    return Self.loadLegacyMetadataForDeterministicAccount(
                        accountId: accountId,
                        baseDirectoryURL: baseDirectoryURL
                    )
                }
                return []
            }
            
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([EmailMetadata].self, from: data)
            } catch {
                logError("EmailCache loadEmailMetadata error: \(error)", category: "Cache")
                return []
            }
        }.value
    }
    
    /// Save email metadata for an account
    public func saveEmailMetadata(_ metadata: [EmailMetadata], accountId: Int? = nil) async {
        let url = metadataURL(for: accountId)
        await Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(metadata)
                try data.write(to: url, options: .atomic)
            } catch {
                logError("EmailCache saveEmailMetadata error: \(error)", category: "Cache")
            }
        }.value
    }
    
    
    // MARK: - Email Detail Cache (Persistent)
    
    /// Load email detail from persistent storage
    /// First checks memory cache, then disk
    public func loadEmailDetail(emailId: Int) async -> EmailDetail? {
        let loadStart = Date()
        // Check memory cache first
        if let cached = memoryCache[emailId] {
            updateMemoryCacheAccess(emailId)
            Telemetry.event("email_cache.load", metadata: ["result": "memory_hit", "elapsed_ms": "\(Int(Date().timeIntervalSince(loadStart) * 1000))"])
            return cached
        }
        
        // Check if in index. If not, fallback to legacy file scan during migration window.
        if !cachedEmailIndex.contains(emailId) {
            if let legacyDetail = await loadLegacyEmailDetail(emailId: emailId) {
                addToMemoryCache(legacyDetail)
                cachedEmailIndex.insert(emailId)
                saveEmailIndex()
                await saveEmailDetail(legacyDetail)
                Telemetry.event("email_cache.load", metadata: ["result": "legacy_hit", "elapsed_ms": "\(Int(Date().timeIntervalSince(loadStart) * 1000))"])
                return legacyDetail
            }
            Telemetry.event("email_cache.load", metadata: ["result": "miss", "elapsed_ms": "\(Int(Date().timeIntervalSince(loadStart) * 1000))"])
            return nil
        }
        
        // Load from disk
        let fileURL = emailDetailURL(for: emailId)
        if let directLoad = await Task.detached(priority: .utility) { [decoder] () -> EmailDetail? in
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }
            
            do {
                let data = try Data(contentsOf: fileURL)
                return try decoder.decode(EmailDetail.self, from: data)
            } catch {
                logError("EmailCache loadEmailDetail error for \(emailId): \(error)", category: "Cache")
                return nil
            }
        }.value {
            addToMemoryCache(directLoad)
            Telemetry.event("email_cache.load", metadata: ["result": "disk_hit", "elapsed_ms": "\(Int(Date().timeIntervalSince(loadStart) * 1000))"])
            return directLoad
        }
        
        // File missing or stale index: fallback scan for legacy filenames/content.
        if let legacyDetail = await loadLegacyEmailDetail(emailId: emailId) {
            addToMemoryCache(legacyDetail)
            cachedEmailIndex.insert(emailId)
            saveEmailIndex()
            await saveEmailDetail(legacyDetail)
            Telemetry.event("email_cache.load", metadata: ["result": "legacy_hit", "elapsed_ms": "\(Int(Date().timeIntervalSince(loadStart) * 1000))"])
            return legacyDetail
        }
        
        Telemetry.event("email_cache.load", metadata: ["result": "miss", "elapsed_ms": "\(Int(Date().timeIntervalSince(loadStart) * 1000))"])
        return nil
    }
    
    /// Load email detail by Gmail ID
    public func loadEmailDetail(gmailId: String) async -> EmailDetail? {
        // Deterministic ID fast path.
        let deterministicId = StableID.emailId(gmailId: gmailId)
        if let detail = await loadEmailDetail(emailId: deterministicId) {
            gmailToEmailIndex[gmailId] = detail.id
            Telemetry.counter("email_cache.gmail_fast_path_hit")
            return detail
        }
        
        if let indexedId = gmailToEmailIndex[gmailId], let detail = await loadEmailDetail(emailId: indexedId) {
            return detail
        }
        
        // First check memory cache
        for (_, detail) in memoryCache {
            if detail.gmail_id == gmailId {
                gmailToEmailIndex[gmailId] = detail.id
                return detail
            }
        }
        
        // Scan disk cache (slower but comprehensive)
        return await Task.detached(priority: .utility) { [emailDetailsDirectoryURL, decoder] in
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: emailDetailsDirectoryURL, includingPropertiesForKeys: nil) else {
                return nil
            }
            
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let detail = try? decoder.decode(EmailDetail.self, from: data),
                   detail.gmail_id == gmailId {
                    return detail
                }
            }
            return nil
        }.value
    }
    
    private func rebuildGmailIndexIfNeeded() async {
        guard !cachedEmailIndex.isEmpty else { return }
        if !gmailToEmailIndex.isEmpty { return }
        
        let allEmails = await loadAllCachedEmails()
        for detail in allEmails {
            gmailToEmailIndex[detail.gmail_id] = detail.id
        }
    }
    
    /// Save email detail to persistent storage
    public func saveEmailDetail(_ detail: EmailDetail) async {
        // Add to memory cache
        addToMemoryCache(detail)
        gmailToEmailIndex[detail.gmail_id] = detail.id
        
        // Add to index
        cachedEmailIndex.insert(detail.id)
        
        // Save to disk in background
        let fileURL = emailDetailURL(for: detail.id)
        await Task.detached(priority: .utility) { [encoder, emailIndexURL, cachedEmailIndex] in
            do {
                let data = try encoder.encode(detail)
                try data.write(to: fileURL, options: .atomic)
                
                // Also save updated index
                let indexData = try encoder.encode(Array(cachedEmailIndex))
                try indexData.write(to: emailIndexURL, options: .atomic)
            } catch {
                logError("EmailCache saveEmailDetail error for \(detail.id): \(error)", category: "Cache")
            }
        }.value
    }
    
    /// Save multiple email details at once (batch operation)
    public func saveEmailDetails(_ details: [EmailDetail]) async {
        guard !details.isEmpty else { return }
        
        // Add all to memory cache and index
        for detail in details {
            addToMemoryCache(detail)
            cachedEmailIndex.insert(detail.id)
            gmailToEmailIndex[detail.gmail_id] = detail.id
        }
        
        // Save all to disk in background
        await Task.detached(priority: .utility) { [encoder, emailDetailsDirectoryURL, emailIndexURL, cachedEmailIndex] in
            for detail in details {
                let fileURL = emailDetailsDirectoryURL.appendingPathComponent("email_\(detail.id).json")
                do {
                    let data = try encoder.encode(detail)
                    try data.write(to: fileURL, options: .atomic)
                } catch {
                    logError("EmailCache saveEmailDetail batch error for \(detail.id): \(error)", category: "Cache")
                }
            }
            
            // Save updated index
            do {
                let indexData = try encoder.encode(Array(cachedEmailIndex))
                try indexData.write(to: emailIndexURL, options: .atomic)
            } catch {
                logError("EmailCache saveEmailIndex error: \(error)", category: "Cache")
            }
        }.value
        
        logInfo("EmailCache: Saved \(details.count) emails to disk. Total cached: \(cachedEmailIndex.count)", category: "Cache")
    }
    
    /// Delete email detail from persistent storage
    public func deleteEmailDetail(emailId: Int) async {
        // Remove from memory cache
        memoryCache.removeValue(forKey: emailId)
        memoryCacheAccessOrder.removeAll { $0 == emailId }
        gmailToEmailIndex = gmailToEmailIndex.filter { $0.value != emailId }
        
        // Remove from index
        cachedEmailIndex.remove(emailId)
        
        // Delete from disk
        let fileURL = emailDetailURL(for: emailId)
        await Task.detached(priority: .utility) { [emailIndexURL, cachedEmailIndex, encoder] in
            try? FileManager.default.removeItem(at: fileURL)
            
            // Save updated index
            do {
                let indexData = try encoder.encode(Array(cachedEmailIndex))
                try indexData.write(to: emailIndexURL, options: .atomic)
            } catch {
                logError("EmailCache saveEmailIndex error: \(error)", category: "Cache")
            }
        }.value
    }
    
    /// Delete multiple email details at once
    public func deleteEmailDetails(emailIds: [Int]) async {
        guard !emailIds.isEmpty else { return }
        
        for emailId in emailIds {
            memoryCache.removeValue(forKey: emailId)
            memoryCacheAccessOrder.removeAll { $0 == emailId }
            cachedEmailIndex.remove(emailId)
        }
        let deleteSet = Set(emailIds)
        gmailToEmailIndex = gmailToEmailIndex.filter { !deleteSet.contains($0.value) }
        
        await Task.detached(priority: .utility) { [emailDetailsDirectoryURL, emailIndexURL, cachedEmailIndex, encoder] in
            let fm = FileManager.default
            for emailId in emailIds {
                let fileURL = emailDetailsDirectoryURL.appendingPathComponent("email_\(emailId).json")
                try? fm.removeItem(at: fileURL)
            }
            
            // Save updated index
            do {
                let indexData = try encoder.encode(Array(cachedEmailIndex))
                try indexData.write(to: emailIndexURL, options: .atomic)
            } catch {
                logError("EmailCache saveEmailIndex error: \(error)", category: "Cache")
            }
        }.value
    }
    
    // MARK: - Load All Cached Emails
    
    /// Load all cached email details from disk
    /// Use sparingly - can be memory intensive with many emails
    public func loadAllCachedEmails() async -> [EmailDetail] {
        return await Task.detached(priority: .utility) { [emailDetailsDirectoryURL, decoder] in
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: emailDetailsDirectoryURL, includingPropertiesForKeys: nil) else {
                return []
            }
            
            var emails: [EmailDetail] = []
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let detail = try? decoder.decode(EmailDetail.self, from: data) {
                    emails.append(detail)
                }
            }
            
            // Sort by received_at descending
            emails.sort { $0.received_at > $1.received_at }
            return emails
        }.value
    }
    
    /// Load cached emails for a specific account
    public func loadCachedEmails(accountEmail: String) async -> [EmailDetail] {
        let allEmails = await loadAllCachedEmails()
        return allEmails.filter { $0.account_email == accountEmail }
    }
    
    /// Get all cached email IDs
    public func getAllCachedEmailIds() -> [Int] {
        return Array(cachedEmailIndex)
    }
    
    // MARK: - Cleanup
    
    /// Remove emails that have been marked as read for more than the specified days
    /// Call this periodically to clean up old cached emails
    public func cleanupOldEmails(olderThanDays days: Int = 10) async {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let allEmails = await loadAllCachedEmails()
        var emailsToDelete: [Int] = []
        
        for email in allEmails {
            // Check if email is read
            if email.is_read {
                // Parse received_at date and check if it's old enough to delete
                if let receivedDate = formatter.date(from: email.received_at),
                   receivedDate < cutoffDate {
                    emailsToDelete.append(email.id)
                }
            }
        }
        
        if !emailsToDelete.isEmpty {
            await deleteEmailDetails(emailIds: emailsToDelete)
            logInfo("EmailCache: Cleaned up \(emailsToDelete.count) old emails", category: "Cache")
        }
    }
    
    // MARK: - Memory Cache Management
    
    private func addToMemoryCache(_ detail: EmailDetail) {
        // Remove if already exists (to update access order)
        if memoryCache[detail.id] != nil {
            memoryCacheAccessOrder.removeAll { $0 == detail.id }
        }
        
        memoryCache[detail.id] = detail
        memoryCacheAccessOrder.append(detail.id)
        
        // Evict oldest if over capacity
        while memoryCacheAccessOrder.count > maxMemoryCacheSize {
            if let oldestId = memoryCacheAccessOrder.first {
                memoryCacheAccessOrder.removeFirst()
                memoryCache.removeValue(forKey: oldestId)
            }
        }
    }
    
    private func updateMemoryCacheAccess(_ emailId: Int) {
        memoryCacheAccessOrder.removeAll { $0 == emailId }
        memoryCacheAccessOrder.append(emailId)
    }
    
    // MARK: - Helpers
    
    private func metadataURL(for accountId: Int?) -> URL {
        guard let accountId = accountId else {
            return defaultMetadataURL
        }
        return baseDirectoryURL.appendingPathComponent("metadata_account_\(accountId).json")
    }
    
    private func emailDetailURL(for emailId: Int) -> URL {
        return emailDetailsDirectoryURL.appendingPathComponent("email_\(emailId).json")
    }
    
    private func loadLegacyEmailDetail(emailId: Int) async -> EmailDetail? {
        await Task.detached(priority: .utility) { [emailDetailsDirectoryURL, decoder] in
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: emailDetailsDirectoryURL, includingPropertiesForKeys: nil) else {
                return nil
            }
            
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let detail = try? decoder.decode(EmailDetail.self, from: data) else {
                    continue
                }
                
                let deterministicId = StableID.emailId(gmailId: detail.gmail_id)
                if detail.id == emailId || deterministicId == emailId {
                    return EmailDetail(
                        id: deterministicId,
                        gmail_id: detail.gmail_id,
                        thread_id: detail.thread_id,
                        subject: detail.subject,
                        sender: detail.sender,
                        sender_name: detail.sender_name,
                        recipients_to: detail.recipients_to,
                        recipients_cc: detail.recipients_cc,
                        recipients_bcc: detail.recipients_bcc,
                        body_text: detail.body_text,
                        body_html: detail.body_html,
                        snippet: detail.snippet,
                        is_read: detail.is_read,
                        is_starred: detail.is_starred,
                        labels: detail.labels,
                        received_at: detail.received_at,
                        account_email: detail.account_email,
                        created_at: detail.created_at
                    )
                }
            }
            
            return nil
        }.value
    }
    
    private nonisolated static func performStableIdMigrationIfNeeded(
        baseDirectoryURL: URL,
        defaultMetadataURL: URL,
        emailDetailsDirectoryURL: URL,
        emailIndexURL: URL
    ) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: stableIdMigrationKey) else { return }
        
        do {
            try migrateMetadataFiles(baseDirectoryURL: baseDirectoryURL, defaultMetadataURL: defaultMetadataURL)
            try migrateDetailFiles(emailDetailsDirectoryURL: emailDetailsDirectoryURL, emailIndexURL: emailIndexURL)
            defaults.set(true, forKey: stableIdMigrationKey)
            logSuccess("EmailCache: Stable ID migration completed", category: "Cache")
        } catch {
            logError("EmailCache: Stable ID migration failed: \(error)", category: "Cache")
        }
    }
    
    private nonisolated static func migrateMetadataFiles(baseDirectoryURL: URL, defaultMetadataURL: URL) throws {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        
        let files = (try? fm.contentsOfDirectory(at: baseDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        let metadataFiles = files.filter { file in
            file.lastPathComponent == "metadata.json" ||
            (file.lastPathComponent.hasPrefix("metadata_account_") && file.pathExtension == "json")
        }
        
        var metadataByAccountId: [Int: [EmailMetadata]] = [:]
        var allMetadata: [EmailMetadata] = []
        
        for file in metadataFiles {
            guard let data = try? Data(contentsOf: file),
                  let metadata = try? decoder.decode([EmailMetadata].self, from: data) else {
                continue
            }
            
            for item in metadata {
                let migrated = EmailMetadata(
                    id: StableID.emailId(gmailId: item.gmail_id),
                    gmail_id: item.gmail_id,
                    thread_id: item.thread_id,
                    subject: item.subject,
                    sender: item.sender,
                    sender_name: item.sender_name,
                    snippet: item.snippet,
                    is_read: item.is_read,
                    is_starred: item.is_starred,
                    labels: item.labels,
                    received_at: item.received_at,
                    account_email: item.account_email
                )
                
                let accountId = StableID.accountId(email: migrated.account_email)
                metadataByAccountId[accountId, default: []].append(migrated)
                allMetadata.append(migrated)
            }
        }
        
        // Remove old metadata files before writing deterministic versions.
        for file in metadataFiles {
            try? fm.removeItem(at: file)
        }
        
        // Write account-scoped metadata.
        for (accountId, metadata) in metadataByAccountId {
            let deduped = dedupeMetadataByGmailId(metadata)
            let target = baseDirectoryURL.appendingPathComponent("metadata_account_\(accountId).json")
            let data = try encoder.encode(deduped)
            try data.write(to: target, options: .atomic)
        }
        
        // Write combined metadata file.
        let dedupedAll = dedupeMetadataByGmailId(allMetadata)
        let allData = try encoder.encode(dedupedAll)
        try allData.write(to: defaultMetadataURL, options: .atomic)
    }
    
    private nonisolated static func migrateDetailFiles(emailDetailsDirectoryURL: URL, emailIndexURL: URL) throws {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        
        let detailFiles = (try? fm.contentsOfDirectory(at: emailDetailsDirectoryURL, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
        
        var detailsById: [Int: EmailDetail] = [:]
        
        for file in detailFiles {
            guard let data = try? Data(contentsOf: file),
                  let detail = try? decoder.decode(EmailDetail.self, from: data) else {
                continue
            }
            
            let deterministicId = StableID.emailId(gmailId: detail.gmail_id)
            detailsById[deterministicId] = EmailDetail(
                id: deterministicId,
                gmail_id: detail.gmail_id,
                thread_id: detail.thread_id,
                subject: detail.subject,
                sender: detail.sender,
                sender_name: detail.sender_name,
                recipients_to: detail.recipients_to,
                recipients_cc: detail.recipients_cc,
                recipients_bcc: detail.recipients_bcc,
                body_text: detail.body_text,
                body_html: detail.body_html,
                snippet: detail.snippet,
                is_read: detail.is_read,
                is_starred: detail.is_starred,
                labels: detail.labels,
                received_at: detail.received_at,
                account_email: detail.account_email,
                created_at: detail.created_at
            )
        }
        
        // Clear legacy detail files.
        for file in detailFiles {
            try? fm.removeItem(at: file)
        }
        
        // Write deterministic detail files and index.
        let sortedIds = detailsById.keys.sorted()
        for id in sortedIds {
            guard let detail = detailsById[id] else { continue }
            let target = emailDetailsDirectoryURL.appendingPathComponent("email_\(id).json")
            let data = try encoder.encode(detail)
            try data.write(to: target, options: .atomic)
        }
        
        let indexData = try encoder.encode(sortedIds)
        try indexData.write(to: emailIndexURL, options: .atomic)
    }
    
    private nonisolated static func dedupeMetadataByGmailId(_ items: [EmailMetadata]) -> [EmailMetadata] {
        var byGmailId: [String: EmailMetadata] = [:]
        for item in items {
            byGmailId[item.gmail_id] = item
        }
        return byGmailId.values.sorted { $0.received_at > $1.received_at }
    }
    
    private nonisolated static func loadLegacyMetadataForDeterministicAccount(accountId: Int, baseDirectoryURL: URL) -> [EmailMetadata] {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        guard let files = try? fm.contentsOfDirectory(at: baseDirectoryURL, includingPropertiesForKeys: nil) else {
            return []
        }
        
        let metadataFiles = files.filter { $0.lastPathComponent.hasPrefix("metadata_account_") && $0.pathExtension == "json" }
        
        for file in metadataFiles {
            guard let data = try? Data(contentsOf: file),
                  let metadata = try? decoder.decode([EmailMetadata].self, from: data),
                  let accountEmail = metadata.first?.account_email else {
                continue
            }
            
            if StableID.accountId(email: accountEmail) == accountId {
                return metadata.map { item in
                    EmailMetadata(
                        id: StableID.emailId(gmailId: item.gmail_id),
                        gmail_id: item.gmail_id,
                        thread_id: item.thread_id,
                        subject: item.subject,
                        sender: item.sender,
                        sender_name: item.sender_name,
                        snippet: item.snippet,
                        is_read: item.is_read,
                        is_starred: item.is_starred,
                        labels: item.labels,
                        received_at: item.received_at,
                        account_email: item.account_email
                    )
                }
            }
        }
        
        return []
    }
}

