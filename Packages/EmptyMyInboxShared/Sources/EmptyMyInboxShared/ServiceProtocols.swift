//
//  ServiceProtocols.swift
//  emptyMyInbox
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

public protocol GmailServiceProtocol: AnyObject {
    func getAllAccounts() -> [GmailAccount]
    func getAccount(byEmail email: String) -> GmailAccount?
    func getAccountsLoadStatus() -> GmailAPIService.AccountLoadStatus
    func signOut(accountEmail: String?)
    func getUserProfile(for account: GmailAccount) async throws -> GmailProfile
    func syncUnreadEmailMetadata(
        for account: GmailAccount,
        maxResults: Int,
        progressCallback: ((Int, Int?) async -> Void)?
    ) async throws -> [EmailMetadata]
    /// Inbox messages (read and unread), metadata only — used for dashboard “all emails” lists.
    func syncInboxEmailMetadata(
        for account: GmailAccount,
        maxResults: Int,
        progressCallback: ((Int, Int?) async -> Void)?
    ) async throws -> [EmailMetadata]
    func syncStarredEmailMetadata(
        for account: GmailAccount,
        maxResults: Int,
        progressCallback: ((Int, Int?) async -> Void)?
    ) async throws -> [EmailMetadata]
}

#if canImport(UIKit)
public protocol GmailAuthServiceProtocol: GmailServiceProtocol {
    @MainActor
    func signIn(presentingViewController: UIViewController) async throws -> GmailAccount
}
#endif

public protocol DashboardCacheProtocol: Actor {
    func loadSnapshot() -> DashboardDataSnapshot?
    func saveSnapshot(_ snapshot: DashboardDataSnapshot)
    func clear()
}

public protocol EmailCacheProtocol: Actor {
    func clearAll()
    func cleanupOldEmails(olderThanDays days: Int) async
}

public protocol ActionSyncProtocol: Actor {
    func resumePendingActions()
    func enqueueStar(emailId: Int, gmailId: String, accountEmail: String, shouldStar: Bool)
    func enqueueMarkRead(emailId: Int, gmailId: String, accountEmail: String)
    func enqueueMarkUnread(emailId: Int, gmailId: String, accountEmail: String)
}

extension GmailAPIService: GmailServiceProtocol {}
#if canImport(UIKit)
extension GmailAPIService: GmailAuthServiceProtocol {}
#endif
extension DashboardCache: DashboardCacheProtocol {}
extension EmailCache: EmailCacheProtocol {}
extension EmailActionSynchronizer: ActionSyncProtocol {}
