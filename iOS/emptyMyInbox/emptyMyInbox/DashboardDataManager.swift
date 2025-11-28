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
    
    func loadCachedSnapshot() async -> DashboardDataSnapshot? {
        await DashboardCache.shared.loadSnapshot()
    }
    
    @discardableResult
    func refreshData(shouldSync: Bool) async -> DashboardDataSnapshot? {
        let gmailAccounts = gmailService.getAllAccounts()
        
        guard !gmailAccounts.isEmpty else {
            print("No Gmail accounts found")
            return nil
        }
        
        // Load existing snapshot first to preserve marked_read_at timestamps
        let existingSnapshot = await DashboardCache.shared.loadSnapshot()
        var existingEmailsMap: [Int: EmailListItem] = [:]
        if let existing = existingSnapshot {
            for email in existing.allEmails {
                existingEmailsMap[email.id] = email
            }
        }
        
        // Sync all accounts if requested
        if shouldSync {
            for account in gmailAccounts {
            do {
                    _ = try await gmailService.syncUnreadEmails(for: account, maxResults: 50, usePagination: true, resetPagination: false)
                    _ = try await gmailService.syncStarredEmails(for: account, maxResults: 500)
                    print("Synced account: \(account.email)")
            } catch {
                    print("Error syncing account \(account.email): \(error.localizedDescription)")
            }
        }
        }
        
        // Re-fetch accounts after syncing to get updated lastSync timestamps
        let updatedGmailAccounts = gmailService.getAllAccounts()
        
        // Fetch data from all accounts
        var allUnreadEmails: [EmailListItem] = []
        var allStarredEmails: [EmailListItem] = []
        var allLabelsDict: [String: (name: String, unreadCount: Int)] = [:]
        
        // Convert GmailAccounts to EmailAccounts
        var emailAccounts: [EmailAccount] = []
        
        for gmailAccount in updatedGmailAccounts {
            // Sync unread emails
            do {
                let (unreadEmails, _) = try await gmailService.syncUnreadEmails(
                    for: gmailAccount,
                    maxResults: 500,
                    usePagination: false,
                    resetPagination: false
                )
                allUnreadEmails.append(contentsOf: unreadEmails)
                
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
            }
            
            // Sync starred emails - always get the most recent
            do {
                let starredEmails = try await gmailService.syncStarredEmails(for: gmailAccount, maxResults: 500)
                // Preserve marked_read_at from existing emails
                let starredWithTimestamps = starredEmails.map { email in
                    if let existing = existingEmailsMap[email.id], let markedReadAt = existing.marked_read_at {
                        return email.updating(markedReadAt: markedReadAt)
                    }
                    return email
                }
                allStarredEmails.append(contentsOf: starredWithTimestamps)
            } catch {
                print("Error fetching starred emails for \(gmailAccount.email): \(error)")
            }
            
            // Get labels for this account
            do {
                let labelsDict = try await gmailService.getAllLabels(for: gmailAccount)
                for (labelId, labelName) in labelsDict {
                    if allLabelsDict[labelId] == nil {
                        allLabelsDict[labelId] = (name: labelName, unreadCount: 0)
                    } else {
                        // Update name if we have it
                        allLabelsDict[labelId]?.name = labelName
                    }
                }
            } catch {
                print("Error fetching labels for \(gmailAccount.email): \(error)")
            }
            
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
        
        // Convert labels dict to Label array
        var labels: [Label] = []
        for (labelId, data) in allLabelsDict {
            labels.append(Label(
                id: labelId,
                name: data.name,
                unread_count: data.unreadCount
            ))
        }
        
        // Sort labels by name
        labels.sort { $0.name < $1.name }
        
        // Merge new emails from Gmail with existing emails, preserving marked_read_at
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
        
        // Filter to only unread emails for the unread list
        let unreadEmails = mergedAllEmails.filter { $0.is_read == false }
            
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
            
        let snapshot = DashboardDataSnapshot(
            timestamp: Date(),
            accounts: emailAccounts,
            emails: unreadEmails,
            allEmails: mergedAllEmails,
            starredEmails: allStarredEmails,
            labels: labels
        )
        await DashboardCache.shared.saveSnapshot(snapshot)
            
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


