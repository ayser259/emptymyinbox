//
//  DashboardDataManager.swift
//  emptyMyInbox
//
//  Centralized loader for dashboard data and caches.
//  Now uses lightweight metadata sync for fast counts.
//

import Foundation

/// Health status for an account connection
public enum AccountHealthStatus: Codable {
    case healthy
    case warning(String)
    case error(String)
    case unknown
    
    public var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }
}

/// Account health information
public struct AccountHealth: Identifiable, Codable {
    public let id: String // email
    public let email: String
    public var status: AccountHealthStatus
    public var lastSuccessfulSync: Date?
    public var lastError: String?
    public var lastChecked: Date
    
    public init(email: String, status: AccountHealthStatus = .unknown, lastSuccessfulSync: Date? = nil, lastError: String? = nil) {
        self.id = email
        self.email = email
        self.status = status
        self.lastSuccessfulSync = lastSuccessfulSync
        self.lastError = lastError
        self.lastChecked = Date()
    }
}

public actor DashboardDataManager {
    public static let shared = DashboardDataManager()
    
    private let gmailService: GmailServiceProtocol
    private let dashboardCache: DashboardCacheProtocol
    
    // Account health tracking
    private var accountHealthMap: [String: AccountHealth] = [:]
    
    // Progress callback type
    public typealias ProgressCallback = (RefreshStage, ProgressStatus, String?, String?, Int?, Int?) async -> Void
    
    public init(
        gmailService: GmailServiceProtocol = GmailAPIService.shared,
        dashboardCache: DashboardCacheProtocol = DashboardCache.shared
    ) {
        self.gmailService = gmailService
        self.dashboardCache = dashboardCache
    }
    
    public func loadCachedSnapshot() async -> DashboardDataSnapshot? {
        await dashboardCache.loadSnapshot()
    }
    
    /// Get health status for all accounts
    public func getAccountHealth() -> [AccountHealth] {
        return Array(accountHealthMap.values)
    }
    
    /// Get health status for a specific account
    public func getAccountHealth(email: String) -> AccountHealth? {
        return accountHealthMap[email]
    }
    
    @discardableResult
    public func refreshData(shouldSync: Bool, progressCallback: ProgressCallback? = nil) async -> DashboardDataSnapshot? {
        let refreshStart = Date()
        logDebug("refreshData called - shouldSync: \(shouldSync), hasCallback: \(progressCallback != nil)", category: "Refresh")
        
        // Stage 1: Initializing
        logDebug("Stage: Initializing", category: "Refresh")
        await progressCallback?(.initializing, .inProgress, "Starting refresh...", nil, nil, nil)
        
        let gmailAccounts = gmailService.getAllAccounts()
        
        guard !gmailAccounts.isEmpty else {
            logError("No Gmail accounts found - user may need to sign in", category: "Refresh")
            logWarning("Hint: If accounts were previously signed in, there may be a keychain access issue", category: "Refresh")
            await progressCallback?(.initializing, .failed("No accounts - please sign in"), nil, nil, nil, nil)
            return nil
        }
        
        logDebug("Found \(gmailAccounts.count) Gmail account(s): \(gmailAccounts.map { $0.email }.joined(separator: ", "))", category: "Refresh")
        logDebug("Progress callback provided: \(progressCallback != nil)", category: "Refresh")
        
        await progressCallback?(.initializing, .completed, "Found \(gmailAccounts.count) account(s)", nil, gmailAccounts.count, nil)
        
        // Stage 2: Loading cache
        await progressCallback?(.loadingCache, .inProgress, "Loading existing data...", nil, nil, nil)
        let existingSnapshot = await dashboardCache.loadSnapshot()
        await progressCallback?(.loadingCache, .completed, "Cache loaded", nil, nil, nil)
        
        // Re-fetch accounts
        let updatedGmailAccounts = gmailService.getAllAccounts()
        
        // Fetch data from all accounts
        var allInboxMetadata: [EmailMetadata] = []
        var allStarredMetadata: [EmailMetadata] = []
        var allSentMetadata: [EmailMetadata] = []
        var allLabelsDict: [String: (name: String, unreadCount: Int)] = [:]
        
        // Convert GmailAccounts to EmailAccounts
        var emailAccounts: [EmailAccount] = []
        let totalAccounts = updatedGmailAccounts.count
        
        // Stage 3: Syncing accounts (skip - we do this implicitly)
        await progressCallback?(.syncingAccounts, .completed, "Accounts ready", nil, totalAccounts, totalAccounts)
        
        for (accountIndex, gmailAccount) in updatedGmailAccounts.enumerated() {
            let accountNum = accountIndex + 1
            
            // Stage 4: Fetching inbox (read + unread) metadata for lists and counts
            logDebug("Fetching inbox for \(gmailAccount.email)", category: "Refresh")
            await progressCallback?(.fetchingUnread, .inProgress, "Account \(accountNum) of \(totalAccounts)", gmailAccount.email, 0, nil)
            
            do {
                let inboxMetadata: [EmailMetadata]
                
                if shouldSync {
                    inboxMetadata = try await gmailService.syncInboxEmailMetadata(
                        for: gmailAccount,
                        maxResults: 1000,
                        progressCallback: { current, total in
                            await progressCallback?(.fetchingUnread, .inProgress, "Fetching inbox: \(current)/\(total ?? 0)", gmailAccount.email, current, total)
                        }
                    )
                    
                    // Update health status - success
                    var health = accountHealthMap[gmailAccount.email] ?? AccountHealth(email: gmailAccount.email)
                    health.status = .healthy
                    health.lastSuccessfulSync = Date()
                    health.lastError = nil
                    health.lastChecked = Date()
                    accountHealthMap[gmailAccount.email] = health
                    logDebug("Health: \(gmailAccount.email) marked healthy", category: "Health")
                    
                } else {
                    // Load from existing snapshot (full inbox list, not unread-only)
                    if let existing = existingSnapshot {
                        inboxMetadata = existing.allEmails
                            .filter { $0.account_email == gmailAccount.email }
                            .map { $0.toEmailMetadata() }
                    } else {
                        inboxMetadata = []
                    }
                }
                
                allInboxMetadata.append(contentsOf: inboxMetadata)
                await progressCallback?(.fetchingUnread, .inProgress, "\(inboxMetadata.count) inbox messages from \(gmailAccount.email)", gmailAccount.email, inboxMetadata.count, nil)
                
                // Count unread per label
                for email in inboxMetadata where !email.is_read {
                    for labelId in email.labels {
                        if allLabelsDict[labelId] == nil {
                            allLabelsDict[labelId] = (name: labelId, unreadCount: 0)
                        }
                        allLabelsDict[labelId]?.unreadCount += 1
                    }
                }
            } catch {
                logError("Error fetching inbox for \(gmailAccount.email): \(error)", category: "Refresh")
                await progressCallback?(.fetchingUnread, .failed(error.localizedDescription), "Failed: \(error.localizedDescription)", gmailAccount.email, nil, nil)
                
                // Update health status - error
                var health = accountHealthMap[gmailAccount.email] ?? AccountHealth(email: gmailAccount.email)
                health.status = .error(error.localizedDescription)
                health.lastError = error.localizedDescription
                health.lastChecked = Date()
                accountHealthMap[gmailAccount.email] = health
            }
            
            // Stage 5: Fetching starred emails
            await progressCallback?(.fetchingStarred, .inProgress, "Account \(accountNum) of \(totalAccounts)", gmailAccount.email, 0, nil)
            logDebug("Fetching starred for \(gmailAccount.email)", category: "Refresh")
            
            do {
                let starredMetadata: [EmailMetadata]
                
                if shouldSync {
                    starredMetadata = try await gmailService.syncStarredEmailMetadata(
                        for: gmailAccount,
                        maxResults: 500,
                        progressCallback: { current, total in
                            await progressCallback?(.fetchingStarred, .inProgress, "Fetching starred: \(current)/\(total ?? 0)", gmailAccount.email, current, total)
                        }
                    )
                    logDebug("syncStarredEmailMetadata returned \(starredMetadata.count) starred for \(gmailAccount.email)", category: "Starred")
                } else {
                    if let existing = existingSnapshot {
                        starredMetadata = existing.starredEmails
                            .filter { $0.account_email.lowercased() == gmailAccount.email.lowercased() }
                            .map { item in
                                EmailMetadata(
                                    id: item.id,
                                    gmail_id: item.gmail_id,
                                    thread_id: "",
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
                        logDebug("Loaded \(starredMetadata.count) cached starred for \(gmailAccount.email)", category: "Starred")
                    } else {
                        starredMetadata = []
                    }
                }
                
                allStarredMetadata.append(contentsOf: starredMetadata)
                logDebug("Total starred so far: \(allStarredMetadata.count)", category: "Starred")
                await progressCallback?(.fetchingStarred, .inProgress, "\(starredMetadata.count) starred from \(gmailAccount.email)", gmailAccount.email, starredMetadata.count, nil)
                
            } catch {
                logError("Error fetching starred emails for \(gmailAccount.email): \(error)", category: "Starred")
                await progressCallback?(.fetchingStarred, .failed(error.localizedDescription), "Failed: \(error.localizedDescription)", gmailAccount.email, nil, nil)
            }

            // Stage 6: Fetching sent emails
            await progressCallback?(.fetchingSent, .inProgress, "Account \(accountNum) of \(totalAccounts)", gmailAccount.email, 0, nil)
            logDebug("Fetching sent for \(gmailAccount.email)", category: "Refresh")

            do {
                let sentMetadata: [EmailMetadata]

                if shouldSync {
                    sentMetadata = try await gmailService.syncSentEmailMetadata(
                        for: gmailAccount,
                        maxResults: 500,
                        progressCallback: { current, total in
                            await progressCallback?(.fetchingSent, .inProgress, "Fetching sent: \(current)/\(total ?? 0)", gmailAccount.email, current, total)
                        }
                    )
                    logDebug("syncSentEmailMetadata returned \(sentMetadata.count) sent for \(gmailAccount.email)", category: "Refresh")
                } else {
                    if let existing = existingSnapshot {
                        sentMetadata = existing.sentEmails
                            .filter { $0.account_email.lowercased() == gmailAccount.email.lowercased() }
                            .map { item in
                                EmailMetadata(
                                    id: item.id,
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
                    } else {
                        sentMetadata = []
                    }
                }

                allSentMetadata.append(contentsOf: sentMetadata)
                await progressCallback?(.fetchingSent, .inProgress, "\(sentMetadata.count) sent from \(gmailAccount.email)", gmailAccount.email, sentMetadata.count, nil)
            } catch {
                logError("Error fetching sent emails for \(gmailAccount.email): \(error)", category: "Refresh")
                await progressCallback?(.fetchingSent, .failed(error.localizedDescription), "Failed: \(error.localizedDescription)", gmailAccount.email, nil, nil)
            }
            
            // Create EmailAccount - use current date as lastSync since we just synced
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let lastSyncString = shouldSync ? dateFormatter.string(from: Date()) : gmailAccount.lastSync.map { dateFormatter.string(from: $0) }
            
            let emailAccount = EmailAccount(
                id: gmailAccount.numericId,
                email: gmailAccount.email,
                is_active: true,
                last_sync: lastSyncString,
                created_at: dateFormatter.string(from: Date()),
                email_count: allInboxMetadata.filter { $0.account_email == gmailAccount.email }.count
            )
            emailAccounts.append(emailAccount)
            logDebug("Created EmailAccount for \(gmailAccount.email), lastSync: \(lastSyncString ?? "nil")", category: "Refresh")
        }
        
        // Mark fetch stages as complete
        await progressCallback?(.fetchingUnread, .completed, "Fetched all inbox messages", nil, allInboxMetadata.count, nil)
        await progressCallback?(.fetchingStarred, .completed, "Fetched all starred emails", nil, allStarredMetadata.count, nil)
        await progressCallback?(.fetchingSent, .completed, "Fetched all sent emails", nil, allSentMetadata.count, nil)
        
        // Stage 6: Processing data
        await progressCallback?(.processingData, .inProgress, "Processing \(allInboxMetadata.count) emails...", nil, nil, nil)
        
        // Convert labels dict to Label array
        var labels: [GmailLabel] = []
        if allLabelsDict["UNREAD"] != nil {
            labels.append(GmailLabel(
                id: "UNREAD",
                name: "Unread",
                unread_count: allLabelsDict["UNREAD"]?.unreadCount ?? 0
            ))
        }
        if allLabelsDict["STARRED"] != nil {
            labels.append(GmailLabel(
                id: "STARRED",
                name: "Starred",
                unread_count: allLabelsDict["STARRED"]?.unreadCount ?? 0
            ))
        }
        
        await progressCallback?(.processingData, .completed, "Processed \(allInboxMetadata.count) emails", nil, allInboxMetadata.count, nil)
        
        // Stage 7: Merging emails
        await progressCallback?(.mergingEmails, .inProgress, "Merging email data...", nil, nil, nil)
        
        // Convert metadata to EmailListItem for storage
        let inboxEmails = allInboxMetadata.map { $0.toEmailListItem() }
        let starredEmails = allStarredMetadata.map { $0.toEmailListItem() }
        let sentEmails = allSentMetadata.map { $0.toEmailListItem() }
        
        // Sort by received_at descending
        let sortedInbox = inboxEmails.sorted { $0.received_at > $1.received_at }
        let sortedUnreadOnly = sortedInbox.filter { !$0.is_read }
        let sortedStarred = starredEmails.sorted { $0.received_at > $1.received_at }
        let sortedSent = sentEmails.sorted { $0.received_at > $1.received_at }
        
        await progressCallback?(.mergingEmails, .completed, "Merged \(sortedInbox.count) inbox messages", nil, sortedInbox.count, nil)
        
        // Stage 8: Filtering old
        await progressCallback?(.filteringOld, .inProgress, "Filtering...", nil, nil, nil)
        await progressCallback?(.filteringOld, .completed, "Filtered to \(sortedInbox.count) emails", nil, sortedInbox.count, nil)
        
        // Stage 9: Counting labels
        await progressCallback?(.countingLabels, .inProgress, "Counting labels...", nil, nil, nil)
        await progressCallback?(.countingLabels, .completed, "Counted \(labels.count) labels", nil, labels.count, nil)
        
        // Stage 10: Saving cache
        await progressCallback?(.savingCache, .inProgress, "Saving to cache...", nil, nil, nil)
        await progressCallback?(.savingCache, .completed, "Cache saved", nil, nil, nil)
        
        // Stage 11: Saving snapshot
        await progressCallback?(.savingSnapshot, .inProgress, "Saving final snapshot...", nil, nil, nil)
        
        let snapshot = DashboardDataSnapshot(
            timestamp: Date(),
            accounts: emailAccounts,
            emails: sortedUnreadOnly,
            allEmails: sortedInbox,
            starredEmails: sortedStarred,
            sentEmails: sortedSent,
            labels: labels
        )
        await dashboardCache.saveSnapshot(snapshot)
        await InboxMetricsStore.shared.reconcileReceivedEmails(from: sortedInbox)
        Telemetry.event("dashboard.refresh.snapshot_saved", metadata: [
            "inbox_count": "\(sortedInbox.count)",
            "unread_count": "\(sortedUnreadOnly.count)",
            "starred_count": "\(sortedStarred.count)",
            "sent_count": "\(sortedSent.count)"
        ])
        
        await progressCallback?(.savingSnapshot, .completed, "Snapshot saved", nil, nil, nil)
        
        // Stage 12: Complete
        await progressCallback?(.complete, .completed, "Refresh completed!", nil, nil, nil)
        
        logSuccess("Refresh complete: \(sortedInbox.count) inbox messages (\(sortedUnreadOnly.count) unread), \(sortedStarred.count) starred, \(sortedSent.count) sent", category: "Refresh")
        logDebug("Health statuses: \(accountHealthMap.mapValues { String(describing: $0.status) })", category: "Health")
        Telemetry.event("dashboard.refresh.complete", metadata: [
            "elapsed_ms": "\(Int(Date().timeIntervalSince(refreshStart) * 1000))",
            "inbox_count": "\(sortedInbox.count)",
            "unread_count": "\(sortedUnreadOnly.count)",
            "starred_count": "\(sortedStarred.count)",
            "sent_count": "\(sortedSent.count)"
        ])
        
        return snapshot
    }

    @discardableResult
    public func refreshData(forAccountEmail accountEmail: String, shouldSync: Bool, progressCallback: ProgressCallback? = nil) async -> DashboardDataSnapshot? {
        guard shouldSync else {
            return await refreshData(shouldSync: shouldSync, progressCallback: progressCallback)
        }

        let normalizedTarget = accountEmail.lowercased()
        guard let gmailAccount = gmailService.getAllAccounts().first(where: { $0.email.lowercased() == normalizedTarget }) else {
            logWarning("Scoped refresh skipped: account not found for \(accountEmail)", category: "Refresh")
            return await dashboardCache.loadSnapshot()
        }

        let existingSnapshot = await dashboardCache.loadSnapshot()
        let refreshStart = Date()
        await progressCallback?(.initializing, .inProgress, "Refreshing \(gmailAccount.email)...", gmailAccount.email, nil, nil)

        do {
            let inboxMetadata = try await gmailService.syncInboxEmailMetadata(
                for: gmailAccount,
                maxResults: 1000,
                progressCallback: { current, total in
                    await progressCallback?(.fetchingUnread, .inProgress, "Fetching inbox: \(current)/\(total ?? 0)", gmailAccount.email, current, total)
                }
            )
            await progressCallback?(.fetchingUnread, .completed, "Fetched inbox", gmailAccount.email, inboxMetadata.count, nil)

            let starredMetadata = try await gmailService.syncStarredEmailMetadata(
                for: gmailAccount,
                maxResults: 500,
                progressCallback: { current, total in
                    await progressCallback?(.fetchingStarred, .inProgress, "Fetching starred: \(current)/\(total ?? 0)", gmailAccount.email, current, total)
                }
            )
            await progressCallback?(.fetchingStarred, .completed, "Fetched starred", gmailAccount.email, starredMetadata.count, nil)

            let sentMetadata = try await gmailService.syncSentEmailMetadata(
                for: gmailAccount,
                maxResults: 500,
                progressCallback: { current, total in
                    await progressCallback?(.fetchingSent, .inProgress, "Fetching sent: \(current)/\(total ?? 0)", gmailAccount.email, current, total)
                }
            )
            await progressCallback?(.fetchingSent, .completed, "Fetched sent", gmailAccount.email, sentMetadata.count, nil)

            var health = accountHealthMap[gmailAccount.email] ?? AccountHealth(email: gmailAccount.email)
            health.status = .healthy
            health.lastSuccessfulSync = Date()
            health.lastError = nil
            health.lastChecked = Date()
            accountHealthMap[gmailAccount.email] = health

            let updatedInboxForAccount = inboxMetadata.map { $0.toEmailListItem() }
            let updatedStarredForAccount = starredMetadata.map { $0.toEmailListItem() }
            let updatedSentForAccount = sentMetadata.map { $0.toEmailListItem() }

            let baseSnapshot = existingSnapshot ?? DashboardDataSnapshot(
                timestamp: Date(),
                accounts: [],
                emails: [],
                allEmails: [],
                starredEmails: [],
                sentEmails: [],
                labels: []
            )

            let mergedInbox = (baseSnapshot.allEmails.filter { $0.account_email.lowercased() != normalizedTarget } + updatedInboxForAccount)
                .sorted { $0.received_at > $1.received_at }
            let mergedUnreadOnly = mergedInbox.filter { !$0.is_read }
            let mergedStarred = (baseSnapshot.starredEmails.filter { $0.account_email.lowercased() != normalizedTarget } + updatedStarredForAccount)
                .sorted { $0.received_at > $1.received_at }
            let mergedSent = (baseSnapshot.sentEmails.filter { $0.account_email.lowercased() != normalizedTarget } + updatedSentForAccount)
                .sorted { $0.received_at > $1.received_at }

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let nowString = dateFormatter.string(from: Date())
            var mergedAccounts = baseSnapshot.accounts
            if let index = mergedAccounts.firstIndex(where: { $0.email.lowercased() == normalizedTarget }) {
                let current = mergedAccounts[index]
                mergedAccounts[index] = EmailAccount(
                    id: current.id,
                    email: current.email,
                    is_active: current.is_active,
                    last_sync: nowString,
                    created_at: current.created_at,
                    email_count: mergedInbox.filter { $0.account_email.lowercased() == normalizedTarget }.count
                )
            } else {
                mergedAccounts.append(
                    EmailAccount(
                        id: gmailAccount.numericId,
                        email: gmailAccount.email,
                        is_active: true,
                        last_sync: nowString,
                        created_at: nowString,
                        email_count: mergedInbox.filter { $0.account_email.lowercased() == normalizedTarget }.count
                    )
                )
            }

            let labels = labelsForUnreadEmails(mergedUnreadOnly)
            let updatedSnapshot = DashboardDataSnapshot(
                timestamp: Date(),
                accounts: mergedAccounts,
                emails: mergedUnreadOnly,
                allEmails: mergedInbox,
                starredEmails: mergedStarred,
                sentEmails: mergedSent,
                labels: labels
            )
            await dashboardCache.saveSnapshot(updatedSnapshot)
            await InboxMetricsStore.shared.reconcileReceivedEmails(from: mergedInbox)
            Telemetry.event("dashboard.refresh.account.complete", metadata: [
                "account_scope": "single_account",
                "elapsed_ms": "\(Int(Date().timeIntervalSince(refreshStart) * 1000))",
                "inbox_count": "\(updatedInboxForAccount.count)",
                "unread_count": "\(mergedUnreadOnly.filter { $0.account_email.lowercased() == normalizedTarget }.count)",
                "starred_count": "\(updatedStarredForAccount.count)"
            ])
            await progressCallback?(.complete, .completed, "Account refresh completed", gmailAccount.email, nil, nil)
            return updatedSnapshot
        } catch {
            var health = accountHealthMap[gmailAccount.email] ?? AccountHealth(email: gmailAccount.email)
            health.status = .error(error.localizedDescription)
            health.lastError = error.localizedDescription
            health.lastChecked = Date()
            accountHealthMap[gmailAccount.email] = health
            await progressCallback?(.complete, .failed(error.localizedDescription), "Account refresh failed", gmailAccount.email, nil, nil)
            logError("Scoped refresh failed for \(gmailAccount.email): \(error)", category: "Refresh")
            return existingSnapshot
        }
    }
    
    /// Check health of all accounts (quick connectivity test)
    public func checkAccountsHealth() async -> [AccountHealth] {
        let accounts = gmailService.getAllAccounts()
        
        for account in accounts {
            do {
                // Try to get profile as a quick health check
                _ = try await gmailService.getUserProfile(for: account)
                
                var health = accountHealthMap[account.email] ?? AccountHealth(email: account.email)
                health.status = .healthy
                health.lastChecked = Date()
                health.lastError = nil
                accountHealthMap[account.email] = health
                
            } catch {
                var health = accountHealthMap[account.email] ?? AccountHealth(email: account.email)
                
                // Determine error type
                let errorString = error.localizedDescription
                if errorString.contains("token") || errorString.contains("expired") || errorString.contains("auth") {
                    health.status = .error("Authentication expired - please re-login")
                } else if errorString.contains("network") || errorString.contains("connection") {
                    health.status = .warning("Network issue - will retry")
                } else {
                    health.status = .error(errorString)
                }
                
                health.lastError = errorString
                health.lastChecked = Date()
                accountHealthMap[account.email] = health
            }
        }
        
        return Array(accountHealthMap.values)
    }
    
    public func markEmailAsRead(emailId: Int) async {
        guard let snapshot = await dashboardCache.loadSnapshot() else {
            return
        }
        guard let current = snapshot.allEmails.first(where: { $0.id == emailId }) else {
            return
        }
        guard !current.is_read else {
            return
        }
        
        let updatedAllEmails = snapshot.allEmails.map { item in
            item.id == emailId ? item.updating(isRead: true) : item
        }
        let updatedSnapshot = rebuiltSnapshot(from: snapshot, allEmails: updatedAllEmails)
        await dashboardCache.saveSnapshot(updatedSnapshot)
        
        // Notify dashboard to update
        await MainActor.run {
            NotificationCenter.default.post(name: .dashboardNeedsUpdate, object: nil)
        }
    }
    
    public func markEmailAsUnread(emailId: Int, accountId: Int?) async {
        guard let snapshot = await dashboardCache.loadSnapshot() else {
            return
        }
        guard let current = snapshot.allEmails.first(where: { $0.id == emailId }) else {
            return
        }
        guard current.is_read else {
            return
        }
        
        let updatedAllEmails = snapshot.allEmails.map { item in
            item.id == emailId ? item.updating(isRead: false) : item
        }
        let updatedSnapshot = rebuiltSnapshot(from: snapshot, allEmails: updatedAllEmails)
        await dashboardCache.saveSnapshot(updatedSnapshot)
        
        // Notify dashboard to update
        await MainActor.run {
            NotificationCenter.default.post(name: .dashboardNeedsUpdate, object: nil)
        }
    }
    
    /// Update starred status for an email
    public func updateEmailStarred(emailId: Int, isStarred: Bool) async {
        guard let snapshot = await dashboardCache.loadSnapshot() else {
            return
        }
        guard let current = snapshot.allEmails.first(where: { $0.id == emailId }) else {
            return
        }
        guard current.is_starred != isStarred else {
            return
        }
        
        let updatedAllEmails = snapshot.allEmails.map { item in
            item.id == emailId ? item.updating(isStarred: isStarred) : item
        }
        let updatedSnapshot = rebuiltSnapshot(from: snapshot, allEmails: updatedAllEmails)
        await dashboardCache.saveSnapshot(updatedSnapshot)
        logDebug(
            "Updated starred status for email \(emailId): \(isStarred), starred count now: \(updatedSnapshot.starredEmails.count)",
            category: "Starred"
        )
        
        // Notify dashboard to update
        await MainActor.run {
            NotificationCenter.default.post(name: .dashboardNeedsUpdate, object: nil)
        }
    }
    
    /// Replace unread email set (optionally for one account) and rebuild snapshot canonically.
    public func replaceUnreadEmails(_ unreadItems: [EmailListItem], forAccountEmail accountEmail: String?) async {
        guard let snapshot = await dashboardCache.loadSnapshot() else { return }
        
        let baseAllEmails: [EmailListItem]
        if let accountEmail {
            // Remove only the target account's emails; other accounts' emails are preserved via merge.
            baseAllEmails = snapshot.allEmails.filter { $0.account_email != accountEmail }
        } else {
            // No specific account targeted — keep everything already in allEmails as the base so
            // that read emails are never lost when Catch Up updates the unread set across all accounts.
            baseAllEmails = snapshot.allEmails
        }
        
        var mergedByGmailId: [String: EmailListItem] = [:]
        for item in baseAllEmails {
            mergedByGmailId[item.gmail_id] = item
        }
        for item in unreadItems {
            mergedByGmailId[item.gmail_id] = item
        }
        
        let merged = Array(mergedByGmailId.values)
        let updatedSnapshot = rebuiltSnapshot(from: snapshot, allEmails: merged)
        await dashboardCache.saveSnapshot(updatedSnapshot)
        
        await MainActor.run {
            NotificationCenter.default.post(name: .dashboardNeedsUpdate, object: nil)
        }
    }
    
    private func rebuiltSnapshot(from snapshot: DashboardDataSnapshot, allEmails: [EmailListItem]) -> DashboardDataSnapshot {
        let sortedAll = allEmails.sorted { $0.received_at > $1.received_at }
        let unread = sortedAll.filter { !$0.is_read }
        let starred = sortedAll.filter { $0.is_starred }
        let labels = labelsForUnreadEmails(unread)
        
        return DashboardDataSnapshot(
            timestamp: Date(),
            accounts: snapshot.accounts,
            emails: unread,
            allEmails: sortedAll,
            starredEmails: starred,
            sentEmails: snapshot.sentEmails,
            labels: labels
        )
    }

    /// Insert or update a sent message in the dashboard snapshot after a successful app send.
    public func upsertSentEmail(from gmailMessage: GmailMessage, accountEmail: String) async {
        guard !gmailMessage.id.isEmpty else { return }
        guard let snapshot = await dashboardCache.loadSnapshot() else { return }

        let emailId = StableID.emailId(gmailId: gmailMessage.id)
        let metadata = GmailAPIService.shared.parseEmailMetadata(
            from: gmailMessage,
            accountEmail: accountEmail,
            emailId: emailId
        )
        let listItem = metadata.toEmailListItem()

        var sentEmails = snapshot.sentEmails.filter { $0.gmail_id != listItem.gmail_id }
        sentEmails.insert(listItem, at: 0)
        sentEmails.sort { $0.received_at > $1.received_at }

        let updated = DashboardDataSnapshot(
            timestamp: Date(),
            accounts: snapshot.accounts,
            emails: snapshot.emails,
            allEmails: snapshot.allEmails,
            starredEmails: snapshot.starredEmails,
            sentEmails: sentEmails,
            labels: snapshot.labels
        )
        await dashboardCache.saveSnapshot(updated)

        await MainActor.run {
            NotificationCenter.default.post(name: .dashboardNeedsUpdate, object: nil)
        }
    }

    private func labelsForUnreadEmails(_ unread: [EmailListItem]) -> [GmailLabel] {
        let unreadCount = unread.filter { $0.labels.contains("UNREAD") }.count
        let starredUnreadCount = unread.filter { $0.labels.contains("STARRED") }.count
        var labels: [GmailLabel] = []
        if unreadCount > 0 {
            labels.append(GmailLabel(id: "UNREAD", name: "Unread", unread_count: unreadCount))
        }
        if starredUnreadCount > 0 {
            labels.append(GmailLabel(id: "STARRED", name: "Starred", unread_count: starredUnreadCount))
        }
        return labels
    }
}
