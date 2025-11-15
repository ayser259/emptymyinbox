//
//  DashboardDataManager.swift
//  emptyMyInbox
//
//  Centralized loader for dashboard data and caches.
//

import Foundation

actor DashboardDataManager {
    static let shared = DashboardDataManager()
    
    func loadCachedSnapshot() async -> DashboardDataSnapshot? {
        await DashboardCache.shared.loadSnapshot()
    }
    
    @discardableResult
    func refreshData(shouldSync: Bool) async -> DashboardDataSnapshot? {
        if shouldSync {
            do {
                _ = try await APIService.shared.syncAllAccounts()
                print("Synced all accounts")
            } catch {
                print("Error syncing accounts: \(error.localizedDescription)")
            }
        }
        
        do {
            async let accountsTask = APIService.shared.getAccounts()
            async let emailsTask = APIService.shared.getEmails()
            async let allEmailsTask = APIService.shared.getEmails()
            async let starredEmailsTask = APIService.shared.getStarredEmails()
            async let labelsTask = APIService.shared.getLabels()
            async let unreadEmailsTask = APIService.shared.getUnreadEmails()
            
            let (accounts,
                 emails,
                 allEmails,
                 starredEmails,
                 labels,
                 unreadEmails) = try await (
                    accountsTask,
                    emailsTask,
                    allEmailsTask,
                    starredEmailsTask,
                    labelsTask,
                    unreadEmailsTask
                 )
            
            await EmailCache.shared.saveUnreadEmails(unreadEmails)
            let groupedUnread = Dictionary(grouping: unreadEmails) { $0.account_email }
            for account in accounts {
                let accountUnread = groupedUnread[account.email] ?? []
                await EmailCache.shared.saveUnreadEmails(accountUnread, accountId: account.id)
            }
            
            let snapshot = DashboardDataSnapshot(timestamp: Date(),
                                                 accounts: accounts,
                                                 emails: emails,
                                                 allEmails: allEmails,
                                                 starredEmails: starredEmails,
                                                 labels: labels)
            await DashboardCache.shared.saveSnapshot(snapshot)
            
            return snapshot
        } catch {
            print("DashboardDataManager refresh error: \(error.localizedDescription)")
            return nil
        }
    }
}


