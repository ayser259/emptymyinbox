//
//  EmailCache.swift
//  emptyMyInbox
//
//  Persistent caching layer for email metadata and full email details.
//  - Metadata: Lightweight email list data for fast loading
//  - Full Details: Complete email content stored on disk for offline access
//

import Foundation

actor EmailCache {
    static let shared = EmailCache()
    
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
        
        // Load email index
        loadEmailIndex()
    }
    
    // MARK: - Email Index Management
    
    private func loadEmailIndex() {
        guard FileManager.default.fileExists(atPath: emailIndexURL.path),
              let data = try? Data(contentsOf: emailIndexURL),
              let ids = try? JSONDecoder().decode([Int].self, from: data) else {
            cachedEmailIndex = []
            return
        }
        cachedEmailIndex = Set(ids)
        print("📧 EmailCache: Loaded index with \(cachedEmailIndex.count) cached emails")
    }
    
    private func saveEmailIndex() {
        do {
            let data = try JSONEncoder().encode(Array(cachedEmailIndex))
            try data.write(to: emailIndexURL, options: .atomic)
        } catch {
            print("EmailCache saveEmailIndex error: \(error)")
        }
    }
    
    /// Check if an email detail is cached on disk
    func isEmailCached(emailId: Int) -> Bool {
        return cachedEmailIndex.contains(emailId)
    }
    
    /// Check if an email detail is cached (by Gmail ID)
    func isEmailCached(gmailId: String) async -> Bool {
        // Need to check all cached files - this is slower but accurate
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: emailDetailsDirectoryURL, includingPropertiesForKeys: nil) else {
            return false
        }
        
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let detail = try? decoder.decode(EmailDetail.self, from: data),
               detail.gmail_id == gmailId {
                return true
            }
        }
        return false
    }
    
    /// Get count of cached emails
    func cachedEmailCount() -> Int {
        return cachedEmailIndex.count
    }
    
    // MARK: - Clear All
    
    func clearAll() {
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
    }
    
    // MARK: - Metadata Cache (Lightweight)
    
    /// Load cached email metadata for an account
    func loadEmailMetadata(accountId: Int? = nil) async -> [EmailMetadata] {
        let url = metadataURL(for: accountId)
        return await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return []
            }
            
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([EmailMetadata].self, from: data)
            } catch {
                print("EmailCache loadEmailMetadata error: \(error)")
                return []
            }
        }.value
    }
    
    /// Save email metadata for an account
    func saveEmailMetadata(_ metadata: [EmailMetadata], accountId: Int? = nil) async {
        let url = metadataURL(for: accountId)
        await Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(metadata)
                try data.write(to: url, options: .atomic)
            } catch {
                print("EmailCache saveEmailMetadata error: \(error)")
            }
        }.value
    }
    
    // MARK: - Legacy Compatibility (for old code that still uses these)
    
    /// Load unread emails - legacy compatibility
    func loadUnreadEmails(accountId: Int? = nil) async -> [EmailListItem] {
        let metadata = await loadEmailMetadata(accountId: accountId)
        return metadata.map { $0.toEmailListItem() }
    }
    
    /// Save unread emails - legacy compatibility
    func saveUnreadEmails(_ emails: [EmailListItem], accountId: Int? = nil) async {
        // Convert to metadata and save
        let metadata = emails.map { email in
            EmailMetadata(
                id: email.id,
                gmail_id: email.gmail_id,
                thread_id: "",
                subject: email.subject,
                sender: email.sender,
                sender_name: email.sender_name,
                snippet: email.snippet,
                is_read: email.is_read,
                is_starred: email.is_starred,
                labels: email.labels,
                received_at: email.received_at,
                account_email: email.account_email
            )
        }
        await saveEmailMetadata(metadata, accountId: accountId)
    }
    
    /// Remove an email from the unread cache - legacy compatibility
    func removeUnreadEmail(emailId: Int, accountId: Int? = nil) async {
        var metadata = await loadEmailMetadata(accountId: accountId)
        if let index = metadata.firstIndex(where: { $0.id == emailId }) {
            metadata.remove(at: index)
            await saveEmailMetadata(metadata, accountId: accountId)
        }
    }
    
    /// Upsert an email in the unread cache - legacy compatibility
    func upsertUnreadEmail(_ email: EmailListItem, accountId: Int? = nil) async {
        var metadata = await loadEmailMetadata(accountId: accountId)
        
        let newMetadata = EmailMetadata(
            id: email.id,
            gmail_id: email.gmail_id,
            thread_id: "",
            subject: email.subject,
            sender: email.sender,
            sender_name: email.sender_name,
            snippet: email.snippet,
            is_read: email.is_read,
            is_starred: email.is_starred,
            labels: email.labels,
            received_at: email.received_at,
            account_email: email.account_email
        )
        
        if let index = metadata.firstIndex(where: { $0.id == email.id }) {
            metadata[index] = newMetadata
        } else {
            metadata.append(newMetadata)
            metadata.sort { $0.received_at > $1.received_at }
        }
        
        await saveEmailMetadata(metadata, accountId: accountId)
    }
    
    // MARK: - Email Detail Cache (Persistent)
    
    /// Load email detail from persistent storage
    /// First checks memory cache, then disk
    func loadEmailDetail(emailId: Int) async -> EmailDetail? {
        // Check memory cache first
        if let cached = memoryCache[emailId] {
            updateMemoryCacheAccess(emailId)
            return cached
        }
        
        // Check if in index
        guard cachedEmailIndex.contains(emailId) else {
            return nil
        }
        
        // Load from disk
        let fileURL = emailDetailURL(for: emailId)
        return await Task.detached(priority: .utility) { [decoder] in
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }
            
            do {
                let data = try Data(contentsOf: fileURL)
                return try decoder.decode(EmailDetail.self, from: data)
            } catch {
                print("EmailCache loadEmailDetail error for \(emailId): \(error)")
                return nil
            }
        }.value
    }
    
    /// Load email detail by Gmail ID
    func loadEmailDetail(gmailId: String) async -> EmailDetail? {
        // First check memory cache
        for (_, detail) in memoryCache {
            if detail.gmail_id == gmailId {
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
    
    /// Save email detail to persistent storage
    func saveEmailDetail(_ detail: EmailDetail) async {
        // Add to memory cache
        addToMemoryCache(detail)
        
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
                print("EmailCache saveEmailDetail error for \(detail.id): \(error)")
            }
        }.value
    }
    
    /// Save multiple email details at once (batch operation)
    func saveEmailDetails(_ details: [EmailDetail]) async {
        guard !details.isEmpty else { return }
        
        // Add all to memory cache and index
        for detail in details {
            addToMemoryCache(detail)
            cachedEmailIndex.insert(detail.id)
        }
        
        // Save all to disk in background
        await Task.detached(priority: .utility) { [encoder, emailDetailsDirectoryURL, emailIndexURL, cachedEmailIndex] in
            for detail in details {
                let fileURL = emailDetailsDirectoryURL.appendingPathComponent("email_\(detail.id).json")
                do {
                    let data = try encoder.encode(detail)
                    try data.write(to: fileURL, options: .atomic)
                } catch {
                    print("EmailCache saveEmailDetail batch error for \(detail.id): \(error)")
                }
            }
            
            // Save updated index
            do {
                let indexData = try encoder.encode(Array(cachedEmailIndex))
                try indexData.write(to: emailIndexURL, options: .atomic)
            } catch {
                print("EmailCache saveEmailIndex error: \(error)")
            }
        }.value
        
        print("📧 EmailCache: Saved \(details.count) emails to disk. Total cached: \(cachedEmailIndex.count)")
    }
    
    /// Delete email detail from persistent storage
    func deleteEmailDetail(emailId: Int) async {
        // Remove from memory cache
        memoryCache.removeValue(forKey: emailId)
        memoryCacheAccessOrder.removeAll { $0 == emailId }
        
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
                print("EmailCache saveEmailIndex error: \(error)")
            }
        }.value
    }
    
    /// Delete multiple email details at once
    func deleteEmailDetails(emailIds: [Int]) async {
        guard !emailIds.isEmpty else { return }
        
        for emailId in emailIds {
            memoryCache.removeValue(forKey: emailId)
            memoryCacheAccessOrder.removeAll { $0 == emailId }
            cachedEmailIndex.remove(emailId)
        }
        
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
                print("EmailCache saveEmailIndex error: \(error)")
            }
        }.value
    }
    
    // MARK: - Load All Cached Emails
    
    /// Load all cached email details from disk
    /// Use sparingly - can be memory intensive with many emails
    func loadAllCachedEmails() async -> [EmailDetail] {
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
    func loadCachedEmails(accountEmail: String) async -> [EmailDetail] {
        let allEmails = await loadAllCachedEmails()
        return allEmails.filter { $0.account_email == accountEmail }
    }
    
    /// Get all cached email IDs
    func getAllCachedEmailIds() -> [Int] {
        return Array(cachedEmailIndex)
    }
    
    // MARK: - Search
    
    /// Search through cached emails
    /// Searches subject, sender, body_text, and snippet
    func searchCachedEmails(query: String) async -> [EmailDetail] {
        let lowercasedQuery = query.lowercased()
        let allEmails = await loadAllCachedEmails()
        
        return allEmails.filter { email in
            email.subject.lowercased().contains(lowercasedQuery) ||
            email.sender.lowercased().contains(lowercasedQuery) ||
            (email.sender_name?.lowercased().contains(lowercasedQuery) ?? false) ||
            email.body_text.lowercased().contains(lowercasedQuery) ||
            email.snippet.lowercased().contains(lowercasedQuery)
        }
    }
    
    /// Search cached emails with multiple terms (AND logic)
    func searchCachedEmails(terms: [String]) async -> [EmailDetail] {
        let allEmails = await loadAllCachedEmails()
        let lowercasedTerms = terms.map { $0.lowercased() }
        
        return allEmails.filter { email in
            let searchableText = [
                email.subject,
                email.sender,
                email.sender_name ?? "",
                email.body_text,
                email.snippet
            ].joined(separator: " ").lowercased()
            
            return lowercasedTerms.allSatisfy { searchableText.contains($0) }
        }
    }
    
    // MARK: - Cleanup
    
    /// Remove emails that have been marked as read for more than the specified days
    /// Call this periodically to clean up old cached emails
    func cleanupOldEmails(olderThanDays days: Int = 10) async {
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
            print("📧 EmailCache: Cleaned up \(emailsToDelete.count) old emails")
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
}

