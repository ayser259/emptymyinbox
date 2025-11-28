//
//  DashboardDataManager.swift
//  emptyMyInbox
//
//  Centralized loader for dashboard data and caches.
//

import Foundation

actor DashboardDataManager {
    static let shared = DashboardDataManager()
    
    private let gmailService = GmailAPIService.shared
    
    // Progress callback type
    typealias ProgressCallback = (RefreshStage, ProgressStatus, String?, String?, Int?, Int?) async -> Void
    
    func loadCachedSnapshot() async -> DashboardDataSnapshot? {
        await DashboardCache.shared.loadSnapshot()
    }
    
    @discardableResult
    func refreshData(shouldSync: Bool, progressCallback: ProgressCallback? = nil) async -> DashboardDataSnapshot? {
        await progressCallback?(.initializing, .inProgress, nil, nil, nil, nil)
        
        let gmailAccounts = gmailService.getAllAccounts()
        
        guard !gmailAccounts.isEmpty else {
            print("No Gmail accounts found")
            await progressCallback?(.initializing, .failed("No Gmail accounts found"), nil, nil, nil, nil)
            return nil
        }
        
        await progressCallback?(.loadingCache, .inProgress, nil, nil, nil, nil)
        // Load existing snapshot first to preserve marked_read_at timestamps
        let existingSnapshot = await DashboardCache.shared.loadSnapshot()
        await progressCallback?(.loadingCache, .completed, nil, nil, nil, nil)
        var existingEmailsMap: [Int: EmailListItem] = [:]
        if let existing = existingSnapshot {
            for email in existing.allEmails {
                existingEmailsMap[email.id] = email
            }
        }
        
        // Re-fetch accounts
        let updatedGmailAccounts = gmailService.getAllAccounts()
        
        // Fetch data from all accounts
        var allUnreadEmails: [EmailListItem] = []
        var allStarredEmails: [EmailListItem] = []
        var allLabelsDict: [String: (name: String, unreadCount: Int)] = [:]
        
        // Convert GmailAccounts to EmailAccounts
        var emailAccounts: [EmailAccount] = []
        
        for (accountIndex, gmailAccount) in updatedGmailAccounts.enumerated() {
            // Sync unread emails
            await progressCallback?(.fetchingUnread, .inProgress, "Fetching unread emails for account \(accountIndex + 1) of \(updatedGmailAccounts.count)", gmailAccount.email, accountIndex + 1, updatedGmailAccounts.count)
            do {
                let unreadEmails: [EmailListItem]
                
                if shouldSync {
                    // Perform smart sync (fetch IDs, diff, download new)
                    (unreadEmails, _) = try await gmailService.syncUnreadEmails(
                        for: gmailAccount,
                        maxResults: 500,
                        usePagination: false,
                        resetPagination: false,
                        progressCallback: { current, total in
                            await progressCallback?(.fetchingUnread, .inProgress, "Fetched \(current) unread emails", gmailAccount.email, current, total)
                        }
                    )
                } else {
                    // Load from cache only
                    unreadEmails = await EmailCache.shared.loadUnreadEmails(accountId: gmailAccount.numericId)
                }
                
                allUnreadEmails.append(contentsOf: unreadEmails)
                await progressCallback?(.fetchingUnread, .inProgress, "Fetched \(unreadEmails.count) unread emails from \(gmailAccount.email)", gmailAccount.email, unreadEmails.count, nil)
                
                // Count unread per label for this account
                for email in unreadEmails where !email.is_read {
                    for labelId in email.labels {
                        if allLabelsDict[labelId] == nil {
                            // We'll get the label name later
                            allLabelsDict[labelId] = (name: labelId, unreadCount: 0)
                        }
                        allLabelsDict[labelId]?.unreadCount += 1
                    }
                }
            } catch {
                print("Error fetching unread emails for \(gmailAccount.email): \(error)")
                await progressCallback?(.fetchingUnread, .failed(error.localizedDescription), "Failed to fetch unread emails", gmailAccount.email, nil, nil)
            }
            
            // Sync starred emails
            await progressCallback?(.fetchingStarred, .inProgress, "Fetching starred emails for account \(accountIndex + 1) of \(updatedGmailAccounts.count)", gmailAccount.email, accountIndex + 1, updatedGmailAccounts.count)
            do {
                let starredEmails: [EmailListItem]
                
                if shouldSync {
                     starredEmails = try await gmailService.syncStarredEmails(for: gmailAccount, maxResults: 500, progressCallback: { current, total in
                        await progressCallback?(.fetchingStarred, .inProgress, "Fetched \(current) starred emails", gmailAccount.email, current, total)
                    })
                } else {
                    // For starred, we need to load from somewhere. 
                    // The cache for starred is in the snapshot, but we might want to be more robust.
                    // For now, we'll use the existing snapshot's starred emails if available, or empty.
                    // Or improved: we should probably cache starred emails separately like unread?
                    // But currently they live in DashboardSnapshot.
                    if let existing = existingSnapshot {
                        starredEmails = existing.starredEmails.filter { $0.account_email == gmailAccount.email }
                    } else {
                        starredEmails = []
                    }
                }
                
                // Preserve marked_read_at from existing emails
                let starredWithTimestamps = starredEmails.map { email in
                    if let existing = existingEmailsMap[email.id], let markedReadAt = existing.marked_read_at {
                        return email.updating(markedReadAt: markedReadAt)
                    }
                    return email
                }
                allStarredEmails.append(contentsOf: starredWithTimestamps)
                await progressCallback?(.fetchingStarred, .inProgress, "Fetched \(starredEmails.count) starred emails from \(gmailAccount.email)", gmailAccount.email, starredEmails.count, nil)
            } catch {
                print("Error fetching starred emails for \(gmailAccount.email): \(error)")
                await progressCallback?(.fetchingStarred, .failed(error.localizedDescription), "Failed to fetch starred emails", gmailAccount.email, nil, nil)
            }
            
            // Skip labels fetching - user doesn't need them anymore
            
            // Create EmailAccount
            let dateFormatter = ISO8601DateFormatter()
            let lastSyncString = gmailAccount.lastSync.map { dateFormatter.string(from: $0) }
            
            let emailAccount = EmailAccount(
                id: gmailAccount.numericId,
                email: gmailAccount.email,
                is_active: true,
                last_sync: lastSyncString,
                created_at: dateFormatter.string(from: Date()),
                email_count: allUnreadEmails.filter { $0.account_email == gmailAccount.email }.count
            )
            emailAccounts.append(emailAccount)
        }
        
        // Convert labels dict to Label array (only UNREAD and STARRED)
        var labels: [Label] = []
        // Only create labels for UNREAD and STARRED (system labels)
        if allLabelsDict["UNREAD"] != nil {
            labels.append(Label(
                id: "UNREAD",
                name: "Unread",
                unread_count: allLabelsDict["UNREAD"]?.unreadCount ?? 0
            ))
        }
        if allLabelsDict["STARRED"] != nil {
            labels.append(Label(
                id: "STARRED",
                name: "Starred",
                unread_count: allLabelsDict["STARRED"]?.unreadCount ?? 0
            ))
        }
        // Labels processed (stage removed from UI)
        
        await progressCallback?(.processingData, .inProgress, "Processing \(allUnreadEmails.count) unread and \(allStarredEmails.count) starred emails", nil, nil, nil)
        
        // Merge new emails from Gmail with existing emails, preserving marked_read_at
        await progressCallback?(.mergingEmails, .inProgress, "Merging emails with existing data", nil, nil, nil)
        var mergedAllEmails: [EmailListItem] = []
        var gmailEmailIds = Set(allUnreadEmails.map { $0.id })
        
        for email in allUnreadEmails {
            // Preserve marked_read_at from existing email if it exists
            if let existing = existingEmailsMap[email.id], let markedReadAt = existing.marked_read_at {
                mergedAllEmails.append(email.updating(markedReadAt: markedReadAt))
            } else {
                mergedAllEmails.append(email)
            }
        }
        
        // Add existing emails that weren't in the Gmail sync (to preserve marked_read_at)
        // But only if they're starred (starred emails are exempt from deletion)
        if let existing = existingSnapshot {
            for existingEmail in existing.allEmails {
                if !gmailEmailIds.contains(existingEmail.id) && existingEmail.is_starred {
                    mergedAllEmails.append(existingEmail)
                }
            }
        }
        
        // Delete emails marked as read 10+ days ago (unless starred)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        let tenDaysAgoString = dateFormatter.string(from: tenDaysAgo)
        
        mergedAllEmails = mergedAllEmails.filter { email in
            // Keep starred emails always
            if email.is_starred {
                return true
            }
            // Keep unread emails
            if !email.is_read {
                return true
            }
            // Delete if marked as read 10+ days ago
            if let markedReadAt = email.marked_read_at, markedReadAt < tenDaysAgoString {
                return false
            }
            // Keep if no marked_read_at timestamp (shouldn't happen, but be safe)
            return true
        }
        
        // Remove emails that are no longer unread in Gmail (sync status)
        // Create a set of Gmail IDs that are currently unread
        let gmailUnreadIds = Set(allUnreadEmails.filter { !$0.is_read }.map { $0.gmail_id })
        
        // Filter merged emails: keep if unread in Gmail, or if starred, or if recently marked as read locally
        mergedAllEmails = mergedAllEmails.filter { email in
            // Always keep starred emails
            if email.is_starred {
                return true
            }
            // Keep if still unread in Gmail
            if gmailUnreadIds.contains(email.gmail_id) {
                return true
            }
            // Keep if marked as read locally but less than 10 days ago
            if let markedReadAt = email.marked_read_at, markedReadAt >= tenDaysAgoString {
                return true
            }
            // Remove if no longer unread in Gmail and not recently marked locally
            return false
        }
        await progressCallback?(.mergingEmails, .completed, "Merged \(mergedAllEmails.count) emails", nil, mergedAllEmails.count, nil)
        
        await progressCallback?(.filteringOld, .inProgress, "Filtering old emails", nil, nil, nil)
        
        // Filter to only unread emails for the unread list
        let unreadEmails = mergedAllEmails.filter { $0.is_read == false }
        await progressCallback?(.filteringOld, .completed, "Filtered to \(unreadEmails.count) unread emails", nil, unreadEmails.count, nil)
        
        await progressCallback?(.countingLabels, .inProgress, "Counting emails per label", nil, nil, nil)
        await progressCallback?(.countingLabels, .completed, "Counted \(labels.count) labels", nil, labels.count, nil)
            
        await progressCallback?(.savingCache, .inProgress, "Saving emails to cache", nil, nil, nil)
        // Save to caches
        await EmailCache.shared.saveUnreadEmails(unreadEmails)
        let groupedUnread = Dictionary(grouping: unreadEmails) { $0.account_email }
        for account in emailAccounts {
            let accountUnread = groupedUnread[account.email] ?? []
            await EmailCache.shared.saveUnreadEmails(accountUnread, accountId: account.id)
        }
        
        // Delete email details for emails that were removed
        let currentEmailIds = Set(mergedAllEmails.map { $0.id })
        if let existing = existingSnapshot {
            for existingEmail in existing.allEmails {
                if !currentEmailIds.contains(existingEmail.id) {
                    await EmailCache.shared.deleteEmailDetail(emailId: existingEmail.id)
                }
            }
        }
        await progressCallback?(.savingCache, .completed, "Saved \(unreadEmails.count) unread emails to cache", nil, unreadEmails.count, nil)
        
        await progressCallback?(.savingSnapshot, .inProgress, "Saving final snapshot", nil, nil, nil)
        let snapshot = DashboardDataSnapshot(
            timestamp: Date(),
            accounts: emailAccounts,
            emails: unreadEmails,
            allEmails: mergedAllEmails,
            starredEmails: allStarredEmails,
            labels: labels
        )
        await DashboardCache.shared.saveSnapshot(snapshot)
        await progressCallback?(.savingSnapshot, .completed, "Snapshot saved", nil, nil, nil)
        
        await progressCallback?(.complete, .completed, "Refresh completed successfully", nil, nil, nil)
        return snapshot
    }
    
    func markEmailAsRead(emailId: Int) async {
        guard let snapshot = await DashboardCache.shared.loadSnapshot() else {
            return
        }
        
        // Find the email to mark as read
        guard let emailToMark = snapshot.allEmails.first(where: { $0.id == emailId }) else {
            return
        }
        
        // Only tag for deletion if not starred (starred emails are exempt)
        let shouldTagForDeletion = !emailToMark.is_starred
        
        func markRead(in list: [EmailListItem]) -> [EmailListItem] {
            list.map { item in
                if item.id == emailId {
                    return item.updating(isRead: true)
                }
                return item
            }
        }
        
        // Remove from unread emails list
        let updatedUnreadEmails = snapshot.emails.filter { $0.id != emailId }
        
        let updatedSnapshot = DashboardDataSnapshot(
            timestamp: Date(),
            accounts: snapshot.accounts,
            emails: updatedUnreadEmails,
            allEmails: markRead(in: snapshot.allEmails),
            starredEmails: markRead(in: snapshot.starredEmails),
            labels: snapshot.labels
        )
        
        await DashboardCache.shared.saveSnapshot(updatedSnapshot)
        
        // Remove from unread cache
        await EmailCache.shared.removeUnreadEmail(emailId: emailId, accountId: nil)
        for account in snapshot.accounts {
            await EmailCache.shared.removeUnreadEmail(emailId: emailId, accountId: account.id)
        }
    }
    
    func markEmailAsUnread(emailId: Int, accountId: Int?) async {
        guard let snapshot = await DashboardCache.shared.loadSnapshot() else {
            return
        }
        
        func markUnread(in list: [EmailListItem]) -> [EmailListItem] {
            list.map { item in
                item.id == emailId ? item.updating(isRead: false) : item
            }
        }
        
        // Find the email to add to unread cache
        guard let emailToMark = snapshot.allEmails.first(where: { $0.id == emailId }) else {
            return
        }
        
        let updatedEmail = emailToMark.updating(isRead: false)
        
        // Update allEmails and starredEmails
        let updatedAllEmails = markUnread(in: snapshot.allEmails)
        let updatedStarredEmails = markUnread(in: snapshot.starredEmails)
        
        // Update unread emails list - add if not already there, or update if it is
        var updatedUnreadEmails = snapshot.emails
        if let existingIndex = updatedUnreadEmails.firstIndex(where: { $0.id == emailId }) {
            updatedUnreadEmails[existingIndex] = updatedEmail
        } else {
            // Email wasn't in unread list, so add it and sort by received_at
            updatedUnreadEmails.append(updatedEmail)
            updatedUnreadEmails.sort { $0.received_at > $1.received_at }
        }
        
        let updatedSnapshot = DashboardDataSnapshot(
            timestamp: Date(),
            accounts: snapshot.accounts,
            emails: updatedUnreadEmails,
            allEmails: updatedAllEmails,
            starredEmails: updatedStarredEmails,
            labels: snapshot.labels
        )
        
        await DashboardCache.shared.saveSnapshot(updatedSnapshot)
        
        // Add to unread cache
        if let accountId = accountId {
            await EmailCache.shared.upsertUnreadEmail(updatedEmail, accountId: accountId)
        }
        // Also update the default unread cache
        await EmailCache.shared.upsertUnreadEmail(updatedEmail, accountId: nil)
    }
}


