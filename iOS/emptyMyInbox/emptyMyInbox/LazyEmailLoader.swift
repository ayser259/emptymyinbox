//
//  LazyEmailLoader.swift
//  emptyMyInbox
//
//  Progressive email loader for Catch Up view.
//  Loads email content on-demand in batches to ensure smooth user experience.
//

import Foundation
import Combine

// Notification for when email metadata is loaded
extension Notification.Name {
    static let emailMetadataLoaded = Notification.Name("emailMetadataLoaded")
    static let starredEmailsUpdated = Notification.Name("starredEmailsUpdated")
    /// Posted when an email's read status changes (marked as read or unread)
    static let emailReadStatusChanged = Notification.Name("emailReadStatusChanged")
    /// Posted when an email's starred status changes
    static let emailStarredStatusChanged = Notification.Name("emailStarredStatusChanged")
    /// Generic notification when any email status changes - dashboard should reload
    static let dashboardNeedsUpdate = Notification.Name("dashboardNeedsUpdate")
}

/// State of a single email in the loading queue
enum EmailLoadState: Equatable {
    case pending       // Not yet loaded
    case loading       // Currently being fetched
    case loaded        // Content available
    case failed        // Failed to load
}

/// Manages progressive loading of email content for Catch Up
@MainActor
class LazyEmailLoader: ObservableObject {
    // MARK: - Published State
    
    /// Metadata for all emails (loaded upfront - lightweight)
    @Published private(set) var emailMetadata: [EmailMetadata] = []
    
    /// Full email details (loaded progressively)
    @Published private(set) var loadedEmails: [Int: EmailDetail] = [:] // keyed by email id
    
    /// Loading state per email
    @Published private(set) var loadStates: [Int: EmailLoadState] = [:] // keyed by email id
    
    /// Current index in the email deck
    @Published var currentIndex: Int = 0
    
    /// Whether initial metadata is loading
    @Published private(set) var isLoadingMetadata: Bool = false
    
    /// Whether we're ready to show cards (first 2 emails loaded)
    @Published private(set) var isReadyToShow: Bool = false
    
    /// Count of emails removed during this session
    @Published private(set) var removedCount: Int = 0
    
    // MARK: - Private State
    
    private let gmailService = GmailAPIService.shared
    private var accountId: Int?
    private var accountEmail: String?
    private var prefetchTask: Task<Void, Never>?
    
    // Progressive loading batch sizes
    private let initialBatchSize = 2     // Load first 2 immediately
    private let secondBatchSize = 3      // Then 3 more
    private let standardBatchSize = 5    // Then batches of 5
    private let largeBatchSize = 10      // Eventually batches of 10
    
    // How far ahead to prefetch
    private let prefetchAhead = 5
    
    // MARK: - Computed Properties
    
    /// Total number of emails in the deck
    var totalEmailCount: Int {
        emailMetadata.count
    }
    
    /// Number of emails left to review
    var remainingCount: Int {
        emailMetadata.count - currentIndex
    }
    
    /// Current email (if loaded)
    var currentEmail: EmailDetail? {
        guard currentIndex < emailMetadata.count else { return nil }
        let metadata = emailMetadata[currentIndex]
        return loadedEmails[metadata.id]
    }
    
    /// Whether current email is loaded
    var isCurrentLoaded: Bool {
        guard currentIndex < emailMetadata.count else { return false }
        let metadata = emailMetadata[currentIndex]
        return loadedEmails[metadata.id] != nil
    }

    var currentLoadState: EmailLoadState {
        guard currentIndex < emailMetadata.count else { return .failed }
        let metadata = emailMetadata[currentIndex]
        return loadStates[metadata.id] ?? .pending
    }
    
    /// Whether there are more emails to show
    var hasMoreEmails: Bool {
        currentIndex < emailMetadata.count
    }
    
    /// Get email at a specific index (if loaded)
    func emailAt(index: Int) -> EmailDetail? {
        guard index < emailMetadata.count else { return nil }
        let metadata = emailMetadata[index]
        return loadedEmails[metadata.id]
    }
    
    /// Check if email at index is loaded
    func isLoadedAt(index: Int) -> Bool {
        guard index < emailMetadata.count else { return false }
        let metadata = emailMetadata[index]
        return loadedEmails[metadata.id] != nil
    }
    
    // MARK: - Initialization
    
    init(accountId: Int? = nil, accountEmail: String? = nil) {
        self.accountId = accountId
        self.accountEmail = accountEmail
    }
    
    deinit {
        prefetchTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Load metadata for all unread emails with priority loading for first email
    /// This uses a streaming approach: first email loads fast while metadata continues in background
    func loadMetadata() async {
        isLoadingMetadata = true
        
        logInfo("LazyEmailLoader: Starting optimized load (priority first email)", category: "Email")
        
        let accounts = gmailService.getAllAccounts()
        let targetAccounts: [GmailAccount]
        
        if let email = accountEmail {
            targetAccounts = accounts.filter { $0.email == email }
        } else {
            targetAccounts = accounts
        }
        
        guard !targetAccounts.isEmpty else {
            isLoadingMetadata = false
            isReadyToShow = true
            return
        }
        
        // PHASE 1: Get message IDs quickly (just IDs, very fast)
        var allMessageRefs: [(account: GmailAccount, id: String, threadId: String)] = []
        
        for account in targetAccounts {
            do {
                logInfo("LazyEmailLoader: Getting message IDs for \(account.email)", category: "Email")
                let (messageRefs, _) = try await gmailService.listMessages(
                    for: account,
                    query: "is:unread in:inbox -is:starred",
                    maxResults: 500,
                    pageToken: nil,
                    fields: "messages(id,threadId),nextPageToken"
                )
                
                for ref in messageRefs {
                    allMessageRefs.append((account: account, id: ref.id, threadId: ref.threadId))
                }
                logInfo("LazyEmailLoader: Got \(messageRefs.count) message IDs for \(account.email)", category: "Email")
            } catch {
                logError("LazyEmailLoader: Error getting message IDs for \(account.email): \(error)", category: "Email")
            }
        }
        
        guard !allMessageRefs.isEmpty else {
            logInfo("LazyEmailLoader: No unread emails found", category: "Email")
            isLoadingMetadata = false
            isReadyToShow = true
            return
        }
        
        // PHASE 2: Load first email's FULL content immediately (priority)
        // Don't wait for metadata - load full email right away for fastest display
        logInfo("LazyEmailLoader: Priority loading first email", category: "Email")
        
        let firstRef = allMessageRefs[0]
        var firstEmailLoaded = false
        
        // Start loading first email's full content
        let firstEmailTask = Task {
            do {
                let details = try await gmailService.batchGetFullEmailDetails(
                    for: firstRef.account,
                    gmailIds: [firstRef.id]
                )
                
                if let firstEmail = details.first {
                    // Skip if email is starred (safety check)
                    guard !firstEmail.is_starred else {
                        logInfo("LazyEmailLoader: Skipping starred first email", category: "Email")
                        return
                    }
                    
                    await MainActor.run {
                        // Create temporary metadata for this email
                        let tempMetadata = EmailMetadata(
                            id: firstEmail.id,
                            gmail_id: firstEmail.gmail_id,
                            thread_id: firstEmail.thread_id,
                            subject: firstEmail.subject,
                            sender: firstEmail.sender,
                            sender_name: firstEmail.sender_name,
                            snippet: firstEmail.snippet,
                            is_read: firstEmail.is_read,
                            is_starred: firstEmail.is_starred,
                            labels: firstEmail.labels,
                            received_at: firstEmail.received_at,
                            account_email: firstEmail.account_email
                        )
                        
                        // Add to our state
                        if self.emailMetadata.isEmpty {
                            self.emailMetadata = [tempMetadata]
                        } else if !self.emailMetadata.contains(where: { $0.gmail_id == tempMetadata.gmail_id }) {
                            self.emailMetadata.insert(tempMetadata, at: 0)
                        }
                        
                        self.loadedEmails[firstEmail.id] = firstEmail
                        self.loadStates[firstEmail.id] = .loaded
                        firstEmailLoaded = true
                        
                        logSuccess("LazyEmailLoader: First email loaded and ready!", category: "Email")
                    }
                }
            } catch {
                logError("LazyEmailLoader: Error loading first email: \(error)", category: "Email")
            }
        }
        
        // PHASE 3: In parallel, load metadata for all unread emails.
        // Dedupe by Gmail ID to avoid duplicates with the priority-loaded first email.
        let metadataTask = Task {
            await self.loadRemainingMetadata(messageRefs: allMessageRefs)
        }
        
        // Wait for first email to load (fast path - just 1 API call)
        await firstEmailTask.value
        
        // Mark as ready once first email is available
        if firstEmailLoaded {
            isLoadingMetadata = false
            isReadyToShow = true
            logInfo("LazyEmailLoader: Ready to show! (first email loaded)", category: "Email")
        }
        
        // Wait for metadata to finish loading
        await metadataTask.value
        
        // If first email didn't load, mark as ready anyway (will show skeleton)
        if !isReadyToShow {
            isLoadingMetadata = false
            isReadyToShow = true
        }
        
        // Load next few emails in background
        await loadNextBatchInBackground()
        
        logInfo("LazyEmailLoader: Full initialization complete. \(emailMetadata.count) emails available", category: "Email")
    }
    
    /// Load metadata for remaining emails (runs in background)
    private func loadRemainingMetadata(messageRefs: [(account: GmailAccount, id: String, threadId: String)]) async {
        // Group by account
        let groupedByAccount = Dictionary(grouping: messageRefs) { $0.account.email }
        
        for (_, refs) in groupedByAccount {
            guard let account = refs.first?.account else { continue }
            let messageIds = refs.map { $0.id }
            
            // Load metadata in smaller batches with rate limiting
            let batchSize = 10 // Smaller batches to avoid 429
            let batches = stride(from: 0, to: messageIds.count, by: batchSize).map { start in
                let end = min(start + batchSize, messageIds.count)
                return Array(messageIds[start..<end])
            }
            
            for batch in batches {
                do {
                    // Small delay between batches to avoid rate limiting
                    if batch != batches.first {
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                    }
                    
                    let messages = try await gmailService.batchGetMessagesMetadata(for: account, messageIds: batch)
                    
                    for gmailMessage in messages {
                        // Only include emails that actually have UNREAD label and are not starred
                        guard gmailMessage.labelIds.contains("UNREAD") && 
                              gmailMessage.labelIds.contains("INBOX") &&
                              !gmailMessage.labelIds.contains("STARRED") else {
                            continue
                        }
                        
                        let emailId = gmailService.getEmailId(for: gmailMessage.id)
                        let metadata = gmailService.parseEmailMetadata(from: gmailMessage, accountEmail: account.email, emailId: emailId)
                        
                        // Add to metadata if not already present
                        if !emailMetadata.contains(where: { $0.gmail_id == metadata.gmail_id }) {
                            emailMetadata.append(metadata)
                            loadStates[metadata.id] = .pending
                        }
                    }
                } catch {
                    logError("LazyEmailLoader: Error loading metadata batch: \(error)", category: "Email")
                }
            }
        }
        
        // Sort by received_at descending (newest first)
        emailMetadata.sort { $0.received_at > $1.received_at }
        
        // Save to cache and notify dashboard
        await saveToCacheAndNotify(emailMetadata)
        
        logInfo("LazyEmailLoader: Metadata load complete. \(emailMetadata.count) emails", category: "Email")
    }
    
    /// Load next batch of full emails in background
    private func loadNextBatchInBackground() async {
        // Load emails 2-5 in background
        let startIdx = 1
        let endIdx = min(5, emailMetadata.count)
        
        guard startIdx < endIdx else { return }
        
        let toLoad = Array(emailMetadata[startIdx..<endIdx])
        await loadBatch(toLoad)
        
        // Continue prefetching
        triggerPrefetch()
    }
    
    /// Save metadata to cache and notify dashboard to update
    private func saveToCacheAndNotify(_ metadata: [EmailMetadata]) async {
        // Save metadata directly to cache
        await EmailCache.shared.saveEmailMetadata(metadata, accountId: accountId)
        
        // Convert to EmailListItem for dashboard snapshot
        let emailItems = metadata.map { $0.toEmailListItem() }
        await DashboardDataManager.shared.replaceUnreadEmails(emailItems, forAccountEmail: accountEmail)
        
        // Post notification so Dashboard can refresh its UI
        await MainActor.run {
            NotificationCenter.default.post(name: .emailMetadataLoaded, object: nil, userInfo: ["count": metadata.count])
        }
    }
    
    /// Remove current email from the deck (after star/mark as read)
    func removeCurrentEmail() {
        guard currentIndex < emailMetadata.count else { return }
        
        let metadata = emailMetadata[currentIndex]
        emailMetadata.remove(at: currentIndex)
        loadedEmails.removeValue(forKey: metadata.id)
        loadStates.removeValue(forKey: metadata.id)
        removedCount += 1
        
        // Don't increment currentIndex since we removed the item
        // Just trigger prefetch for next batch
        triggerPrefetch()
    }
    
    /// Move to next email (for "Keep Unread" action - email stays in Gmail)
    func moveToNext() {
        currentIndex += 1
        triggerPrefetch()
    }
    
    /// Reset the loader for a fresh start
    func reset() {
        prefetchTask?.cancel()
        emailMetadata = []
        loadedEmails = [:]
        loadStates = [:]
        currentIndex = 0
        isReadyToShow = false
        removedCount = 0
    }
    
    // MARK: - Progressive Loading
    
    /// Load a batch of emails by their metadata
    private func loadBatch(_ batch: [EmailMetadata]) async {
        // Mark all as loading
        for metadata in batch {
            loadStates[metadata.id] = .loading
        }
        
        // Group by account for efficient batching
        let groupedByAccount = Dictionary(grouping: batch) { $0.account_email }
        
        for (accountEmail, metadataList) in groupedByAccount {
            guard let account = gmailService.getAllAccounts().first(where: { $0.email == accountEmail }) else {
                for metadata in metadataList {
                    loadStates[metadata.id] = .failed
                }
                continue
            }
            
            let gmailIds = metadataList.map { $0.gmail_id }
            
            do {
                let details = try await gmailService.batchGetFullEmailDetails(for: account, gmailIds: gmailIds)
                
                for detail in details {
                    loadedEmails[detail.id] = detail
                    loadStates[detail.id] = .loaded
                }
                
                // Mark any that weren't returned as failed
                let loadedIds = Set(details.map { $0.id })
                for metadata in metadataList where !loadedIds.contains(metadata.id) {
                    loadStates[metadata.id] = .failed
                }
            } catch {
                logError("Error loading batch for \(accountEmail): \(error)", category: "Email")
                for metadata in metadataList {
                    loadStates[metadata.id] = .failed
                }
            }
        }
    }
    
    /// Trigger prefetch of upcoming emails
    private func triggerPrefetch() {
        prefetchTask?.cancel()
        
        prefetchTask = Task {
            await prefetchUpcoming()
        }
    }
    
    /// Prefetch emails ahead of current position
    private func prefetchUpcoming() async {
        // Determine what needs to be loaded
        let startIndex = currentIndex
        let endIndex = min(currentIndex + prefetchAhead, emailMetadata.count)
        
        guard startIndex < endIndex else { return }
        
        var toLoad: [EmailMetadata] = []
        
        for i in startIndex..<endIndex {
            let metadata = emailMetadata[i]
            let state = loadStates[metadata.id] ?? .pending
            
            if state == .pending {
                toLoad.append(metadata)
            }
        }
        
        guard !toLoad.isEmpty else { return }
        
        // Determine batch size based on position
        let batchSize: Int
        if currentIndex < initialBatchSize + secondBatchSize {
            batchSize = standardBatchSize
        } else {
            batchSize = largeBatchSize
        }
        
        // Load in batches
        let batches = stride(from: 0, to: toLoad.count, by: batchSize).map { start in
            let end = min(start + batchSize, toLoad.count)
            return Array(toLoad[start..<end])
        }
        
        for batch in batches {
            // Check if task was cancelled
            if Task.isCancelled { return }
            
            await loadBatch(batch)
        }
    }
    
    // MARK: - Manual Loading
    
    /// Manually request loading of a specific email
    func loadEmail(at index: Int) async {
        guard index < emailMetadata.count else { return }
        
        let metadata = emailMetadata[index]
        let state = loadStates[metadata.id] ?? .pending
        
        // Don't reload if already loaded or loading
        guard state == .pending || state == .failed else { return }
        
        await loadBatch([metadata])
    }

    func retryCurrentEmail() async {
        await loadEmail(at: currentIndex)
    }

    func skipCurrentFailedEmail() {
        guard currentLoadState == .failed else { return }
        moveToNext()
    }
}

