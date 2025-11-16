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
            // Inbox-only unread for parity with Gmail badge
            async let inboxUnreadTask = APIService.shared.getEmailsByLabel(labelId: "INBOX")
            async let allEmailsTask = APIService.shared.getEmails()
            async let starredEmailsTask = APIService.shared.getStarredEmails()
            async let labelsTask = APIService.shared.getLabels()
            
            let (accounts,
                 inboxUnreadAll,
                 allEmails,
                 starredEmails,
                 labels) = try await (
                    accountsTask,
                    inboxUnreadTask,
                    allEmailsTask,
                    starredEmailsTask,
                    labelsTask
                 )
            
            // Only keep messages that are still unread
            let unreadEmails = inboxUnreadAll.filter { $0.is_read == false }
            
            await EmailCache.shared.saveUnreadEmails(unreadEmails)
            let groupedUnread = Dictionary(grouping: unreadEmails) { $0.account_email }
            for account in accounts {
                let accountUnread = groupedUnread[account.email] ?? []
                await EmailCache.shared.saveUnreadEmails(accountUnread, accountId: account.id)
            }
            
            let snapshot = DashboardDataSnapshot(timestamp: Date(),
                                                 accounts: accounts,
                                                 emails: unreadEmails,
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
    
    func markEmailAsRead(emailId: Int) async {
        guard let snapshot = await DashboardCache.shared.loadSnapshot() else {
            return
        }
        
        func markRead(in list: [EmailListItem]) -> [EmailListItem] {
            list.map { item in
                item.id == emailId ? item.updating(isRead: true) : item
            }
        }
        
        let updatedSnapshot = DashboardDataSnapshot(
            timestamp: Date(),
            accounts: snapshot.accounts,
            emails: markRead(in: snapshot.emails),
            allEmails: markRead(in: snapshot.allEmails),
            starredEmails: markRead(in: snapshot.starredEmails),
            labels: snapshot.labels
        )
        
        await DashboardCache.shared.saveSnapshot(updatedSnapshot)
    }
}


