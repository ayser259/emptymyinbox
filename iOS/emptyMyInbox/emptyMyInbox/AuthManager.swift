//
//  AuthManager.swift
//  emptyMyInbox
//
//  Authentication state manager - now uses Gmail OAuth only
//

import Foundation
import SwiftUI

class AuthManager: ObservableObject {
    enum SessionState: Equatable {
        case checking
        case authenticated
        case needsLogin
    }
    
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var sessionState: SessionState = .checking
    @Published var accounts: [GmailAccount] = []
    
    private let gmailService: GmailServiceProtocol
    private let emailCache: EmailCacheProtocol
    private let dashboardCache: DashboardCacheProtocol
    
    init(
        gmailService: GmailServiceProtocol = GmailAPIService.shared,
        emailCache: EmailCacheProtocol = EmailCache.shared,
        dashboardCache: DashboardCacheProtocol = DashboardCache.shared
    ) {
        self.gmailService = gmailService
        self.emailCache = emailCache
        self.dashboardCache = dashboardCache
        // Check if user is already authenticated
        checkAuthStatus()
    }
    
    func checkAuthStatus() {
        sessionState = .checking
        Telemetry.event("auth.check_status.started")
        Task {
            await MainActor.run {
                let gmailAccounts = self.gmailService.getAllAccounts()
                
                if !gmailAccounts.isEmpty {
                    // We have valid accounts in keychain
                    self.accounts = gmailAccounts
                    self.isAuthenticated = true
                    self.sessionState = .authenticated
                    logSuccess("Auth: Found \(gmailAccounts.count) authenticated account(s)", category: "Auth")
                    Telemetry.counter("auth.accounts_loaded", delta: gmailAccounts.count)
                } else {
                    // Do not clear caches here. Empty accounts can be intentional sign-out OR transient keychain issue.
                    switch self.gmailService.getAccountsLoadStatus() {
                    case .notFound:
                        logInfo("Auth: No accounts found in keychain", category: "Auth")
                    case .transientFailure(let status):
                        logWarning("Auth: Keychain transient failure (\(status)); preserving caches", category: "Auth")
                    case .corruptedData:
                        logWarning("Auth: Keychain data corrupted/unreadable; preserving caches", category: "Auth")
                    case .loaded:
                        logWarning("Auth: Account load status is loaded but no accounts available", category: "Auth")
                    }
                    self.accounts = []
                    self.isAuthenticated = false
                    self.sessionState = .needsLogin
                    Telemetry.event("auth.check_status.needs_login")
                }
            }
        }
    }
    
    /// Clear all local caches when accounts are disconnected
    private func clearAllCaches() {
        Task {
            await dashboardCache.clear()
            await emailCache.clearAll()
            Telemetry.event("auth.cache_cleared")
            logInfo("Auth: Cleared all local caches", category: "Auth")
        }
    }
    
    @MainActor
    func signInWithGoogle() async throws {
        isLoading = true
        defer { isLoading = false }
        
        #if canImport(UIKit)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw GmailAPIError.configurationError
        }
        
        guard let authService = gmailService as? GmailAuthServiceProtocol else {
            throw GmailAPIError.configurationError
        }
        let account = try await authService.signIn(presentingViewController: rootViewController)
        logSuccess("Auth: Signed in as \(account.email)", category: "Auth")
        Telemetry.event("auth.sign_in.success", metadata: ["account_hash": Telemetry.hashForDiagnostics(account.email)])
        
        // Reload accounts
        self.accounts = gmailService.getAllAccounts()
        self.isAuthenticated = true
        self.sessionState = .authenticated
        
        // Post notification so dashboard refreshes
        NotificationCenter.default.post(name: .accountAdded, object: nil)
        #else
        throw GmailAPIError.configurationError
        #endif
    }
    
    @MainActor
    func logout(accountEmail: String? = nil) {
        gmailService.signOut(accountEmail: accountEmail)
        self.accounts = gmailService.getAllAccounts()
        
        if self.accounts.isEmpty {
            // Clear all caches when fully logged out
            clearAllCaches()
            self.isAuthenticated = false
            self.sessionState = .needsLogin
            logSuccess("Auth: Logged out, cleared all data", category: "Auth")
        }
    }
}
