//
//  ServiceProtocols.swift
//  emptyMyInbox
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

protocol GmailServiceProtocol: AnyObject {
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
    func syncStarredEmailMetadata(
        for account: GmailAccount,
        maxResults: Int,
        progressCallback: ((Int, Int?) async -> Void)?
    ) async throws -> [EmailMetadata]
}

#if canImport(UIKit)
protocol GmailAuthServiceProtocol: GmailServiceProtocol {
    @MainActor
    func signIn(presentingViewController: UIViewController) async throws -> GmailAccount
}
#endif

protocol DashboardCacheProtocol: Actor {
    func loadSnapshot() -> DashboardDataSnapshot?
    func saveSnapshot(_ snapshot: DashboardDataSnapshot)
    func clear()
}

protocol EmailCacheProtocol: Actor {
    func clearAll()
    func cleanupOldEmails(olderThanDays days: Int) async
}

protocol ActionSyncProtocol: Actor {
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
