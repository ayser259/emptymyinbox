//
//  LazyEmailLoader.swift
//  emptyMyInbox
//
//  Progressive email loader for Catch Up view.
//  Loads email content on-demand in batches to ensure smooth user experience.
//

import Foundation
import Combine
import SwiftUI

// Notification for when email metadata is loaded
public extension Notification.Name {
    public static let emailMetadataLoaded = Notification.Name("emailMetadataLoaded")
    public static let starredEmailsUpdated = Notification.Name("starredEmailsUpdated")
    /// Posted when an email's read status changes (marked as read or unread)
    public static let emailReadStatusChanged = Notification.Name("emailReadStatusChanged")
    /// Posted when an email's starred status changes
    public static let emailStarredStatusChanged = Notification.Name("emailStarredStatusChanged")
    /// Generic notification when any email status changes - dashboard should reload
    public static let dashboardNeedsUpdate = Notification.Name("dashboardNeedsUpdate")
}

/// State of a single email in the loading queue
public enum EmailLoadState: Equatable {
    case pending       // Not yet loaded
    case loading       // Currently being fetched
    case loaded        // Content available
    case failed        // Failed to load
}

/// Manages progressive loading of email content for Catch Up
@MainActor
public class LazyEmailLoader: ObservableObject {
    // MARK: - Published State
    
    /// Metadata for all emails (loaded upfront - lightweight)
    @Published public private(set) var emailMetadata: [EmailMetadata] = []
    
    /// Catch Up deck: one item per unread thread.
    @Published public private(set) var catchUpThreads: [CatchUpThreadItem] = []
    
    /// Loaded full-thread conversations keyed by thread stable id.
    @Published public private(set) var loadedConversations: [Int: EmailThreadConversation] = [:]
    
    /// Loading state per thread (stable list id).
    @Published public private(set) var threadLoadStates: [Int: EmailLoadState] = [:]
    
    /// Full email details (legacy per-message cache, still used during migration)
    @Published public private(set) var loadedEmails: [Int: EmailDetail] = [:]
    
    /// Loading state per email (legacy)
    @Published public private(set) var loadStates: [Int: EmailLoadState] = [:]
    
    /// Current index in the thread deck
    @Published public var currentIndex: Int = 0
    
    /// Whether initial metadata is loading
    @Published public private(set) var isLoadingMetadata: Bool = false
    
    /// Whether we're ready to show cards (first 2 emails loaded)
    @Published public private(set) var isReadyToShow: Bool = false
    
    /// Count of emails removed during this session
    @Published public private(set) var removedCount: Int = 0

    /// IDs of emails the user has already processed (kept unread or removed) this session.
    /// Used as a safety net to prevent a background metadata sort from re-surfacing them.
    @Published public private(set) var sessionSeenEmailIds: Set<Int> = []
    @Published public private(set) var sessionSeenThreadIds: Set<Int> = []
    
    /// Desired account order for grouped sorting (account emails in priority order).
    /// Set this before calling `loadMetadata()` or any time before the background sort completes.
    public var accountOrder: [String] = []

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
    
    /// Total number of threads in the deck
    public var totalEmailCount: Int {
        catchUpThreads.count
    }
    
    /// Number of threads left to review
    public var remainingCount: Int {
        max(0, catchUpThreads.count - currentIndex)
    }
    
    public var currentThread: CatchUpThreadItem? {
        guard currentIndex < catchUpThreads.count else { return nil }
        return catchUpThreads[currentIndex]
    }
    
    /// Current thread conversation (if loaded)
    public var currentConversation: EmailThreadConversation? {
        guard let thread = currentThread else { return nil }
        return loadedConversations[thread.id]
    }
    
    /// Selected action-target message in the current thread.
    public var currentEmail: EmailDetail? {
        currentConversation?.selectedMessage
    }
    
    /// Whether current thread conversation is loaded
    public var isCurrentLoaded: Bool {
        guard let thread = currentThread else { return false }
        return loadedConversations[thread.id] != nil
    }

    public var currentLoadState: EmailLoadState {
        guard let thread = currentThread else { return .failed }
        return threadLoadStates[thread.id] ?? .pending
    }
    
    /// Whether there are more threads to show
    public var hasMoreEmails: Bool {
        currentIndex < catchUpThreads.count
    }
    
    /// Get email at a specific index (if loaded)
    public func emailAt(index: Int) -> EmailDetail? {
        guard index < emailMetadata.count else { return nil }
        let metadata = emailMetadata[index]
        return loadedEmails[metadata.id]
    }
    
    /// Check if email at index is loaded
    public func isLoadedAt(index: Int) -> Bool {
        guard index < emailMetadata.count else { return false }
        let metadata = emailMetadata[index]
        return loadedEmails[metadata.id] != nil
    }
    
    // MARK: - Initialization
    
    public init(accountId: Int? = nil, accountEmail: String? = nil) {
        self.accountId = accountId
        self.accountEmail = accountEmail
    }
    
    deinit {
        prefetchTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Load metadata for all unread emails with priority loading for first email
    /// This uses a streaming approach: first email loads fast while metadata continues in background
    public func loadMetadata() async {
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
                        self.rebuildCatchUpThreads()
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
        
        // Mark as ready once first thread can load
        if firstEmailLoaded {
            rebuildCatchUpThreads()
            if !catchUpThreads.isEmpty {
                await loadThread(at: 0)
            }
            isLoadingMetadata = false
            isReadyToShow = true
            logInfo("LazyEmailLoader: Ready to show! (first thread loading)", category: "Email")
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
        
        // Sort by account order (if set) then by received_at descending within each account.
        // Only sort the *unseen* portion (from currentIndex onwards) so that already-processed
        // emails are never displaced back into the visible deck by a background sort.
        if currentIndex > 0 && currentIndex <= emailMetadata.count {
            let seen = Array(emailMetadata[0..<currentIndex])
            var unseen = Array(emailMetadata[currentIndex...])
            sortEmails(&unseen)
            emailMetadata = seen + unseen
        } else {
            sortEmails(&emailMetadata)
        }
        
        // Save to cache and notify dashboard
        await saveToCacheAndNotify(emailMetadata)
        
        rebuildCatchUpThreads()
        logInfo("LazyEmailLoader: Metadata load complete. \(emailMetadata.count) emails, \(catchUpThreads.count) threads", category: "Email")
    }
    
    private func rebuildCatchUpThreads() {
        var threads = EmailThreadGrouping.catchUpThreads(from: emailMetadata, accountOrder: accountOrder)
        if !sessionSeenThreadIds.isEmpty {
            threads = threads.filter { !sessionSeenThreadIds.contains($0.id) }
        }
        catchUpThreads = threads
        if currentIndex >= catchUpThreads.count {
            currentIndex = max(0, catchUpThreads.count - 1)
        }
        advancePastSeenThreads()
    }
    
    /// Sort emails: by accountOrder position first, then by received_at descending within each account.
    /// If accountOrder is empty, sort purely by received_at descending.
    private func sortEmails(_ emails: inout [EmailMetadata]) {
        if accountOrder.isEmpty {
            emails.sort { $0.received_at > $1.received_at }
        } else {
            emails.sort { a, b in
                let ai = accountOrder.firstIndex(of: a.account_email) ?? accountOrder.count
                let bi = accountOrder.firstIndex(of: b.account_email) ?? accountOrder.count
                if ai != bi { return ai < bi }
                return a.received_at > b.received_at
            }
        }
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
    
    /// Remove current thread from the deck (after all unread handled or explicit skip).
    public func removeCurrentEmail() {
        removeCurrentThread()
    }
    
    public func removeCurrentThread() {
        guard let thread = currentThread else { return }
        sessionSeenThreadIds.insert(thread.id)
        for meta in thread.unreadMetadata {
            sessionSeenEmailIds.insert(meta.id)
            emailMetadata.removeAll { $0.id == meta.id }
        }
        catchUpThreads.remove(at: currentIndex)
        loadedConversations.removeValue(forKey: thread.id)
        threadLoadStates.removeValue(forKey: thread.id)
        removedCount += 1

        if !catchUpThreads.isEmpty, currentIndex >= catchUpThreads.count {
            currentIndex = max(0, catchUpThreads.count - 1)
        }
        advancePastSeenThreads()
        triggerPrefetch()
    }
    
    /// Mark one message read inside the current thread; remove thread if no unread remain.
    public func markMessageReadInCurrentThread(emailId: Int) {
        guard var conversation = currentConversation else {
            removeCurrentThread()
            return
        }
        if let detail = conversation.messages.first(where: { $0.id == emailId }) {
            let updated = detail.updating(isRead: true)
            conversation.updateMessage(updated)
            loadedEmails[emailId] = updated
            emailMetadata.removeAll { $0.id == emailId }
        }
        let threadId = conversation.key.stableListId
        loadedConversations[threadId] = conversation
        if !conversation.hasUnread {
            removeCurrentThread()
        } else {
            conversation.selectMessage(id: EmailThreadConversation.defaultActionTargetId(in: conversation.messages))
            loadedConversations[threadId] = conversation
            rebuildCatchUpThreads()
        }
    }

    /// Move to the previous email in the deck (desktop feed navigation).
    public func moveToPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        triggerPrefetch()
    }

    /// Focus a specific row (desktop feed tap); keeps prefetch aligned with the focused card.
    public func selectIndex(_ index: Int) {
        guard index >= 0, index < catchUpThreads.count else { return }
        currentIndex = index
        triggerPrefetch()
    }
    
    /// Move to next thread (for "Keep Unread" — thread stays in Gmail unread).
    public func moveToNext() {
        if let thread = currentThread {
            sessionSeenThreadIds.insert(thread.id)
        }
        currentIndex += 1
        advancePastSeenThreads()
        triggerPrefetch()
    }

    private func advancePastSeenThreads() {
        while currentIndex < catchUpThreads.count,
              sessionSeenThreadIds.contains(catchUpThreads[currentIndex].id) {
            currentIndex += 1
        }
    }
    
    private func advancePastSeen() {
        advancePastSeenThreads()
    }
    
    /// Reset the loader for a fresh start
    public func reset() {
        prefetchTask?.cancel()
        emailMetadata = []
        catchUpThreads = []
        loadedConversations = [:]
        threadLoadStates = [:]
        loadedEmails = [:]
        loadStates = [:]
        currentIndex = 0
        isReadyToShow = false
        removedCount = 0
        sessionSeenEmailIds = []
        sessionSeenThreadIds = []
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
        let startIndex = currentIndex
        let endIndex = min(currentIndex + prefetchAhead, catchUpThreads.count)
        guard startIndex < endIndex else { return }
        
        for i in startIndex..<endIndex {
            let thread = catchUpThreads[i]
            let state = threadLoadStates[thread.id] ?? .pending
            if state == .pending || state == .failed {
                await loadThread(at: i)
            }
        }
    }
    
    // MARK: - Manual Loading
    
    /// Load full conversation for a thread deck index.
    public func loadThread(at index: Int) async {
        guard index < catchUpThreads.count else { return }
        let item = catchUpThreads[index]
        let state = threadLoadStates[item.id] ?? .pending
        guard state == .pending || state == .failed else { return }
        
        threadLoadStates[item.id] = .loading
        do {
            let conversation = try await ThreadConversationService.shared.loadConversation(
                key: item.key,
                summary: item.summary
            )
            loadedConversations[item.id] = conversation
            threadLoadStates[item.id] = .loaded
            for message in conversation.messages {
                loadedEmails[message.id] = message
                loadStates[message.id] = .loaded
            }
        } catch {
            logError("LazyEmailLoader: failed to load thread \(item.key.threadId): \(error)", category: "Email")
            threadLoadStates[item.id] = .failed
        }
    }
    
    public func loadEmail(at index: Int) async {
        await loadThread(at: index)
    }
    
    public func updateCurrentConversation(_ conversation: EmailThreadConversation) {
        loadedConversations[conversation.key.stableListId] = conversation
        for message in conversation.messages {
            loadedEmails[message.id] = message
        }
    }
    
    public func bindingForConversation(threadStableId: Int) -> Binding<EmailThreadConversation>? {
        guard let conversation = loadedConversations[threadStableId] else { return nil }
        return Binding(
            get: { self.loadedConversations[threadStableId] ?? conversation },
            set: { newValue in
                self.loadedConversations[threadStableId] = newValue
                for message in newValue.messages {
                    self.loadedEmails[message.id] = message
                }
            }
        )
    }
    
    public func conversation(at index: Int) -> EmailThreadConversation? {
        guard index < catchUpThreads.count else { return nil }
        return loadedConversations[catchUpThreads[index].id]
    }

    public func retryCurrentEmail() async {
        guard let thread = currentThread else { return }
        threadLoadStates[thread.id] = .pending
        await loadThread(at: currentIndex)
    }

    public func skipCurrentFailedEmail() {
        guard currentLoadState == .failed else { return }
        moveToNext()
    }
}

