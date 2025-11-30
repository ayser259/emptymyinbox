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
    
    private let gmailService = GmailAPIService.shared
    
    init() {
        // Check if user is already authenticated
        checkAuthStatus()
    }
    
    func checkAuthStatus() {
        sessionState = .checking
        Task {
            await MainActor.run {
                let gmailAccounts = self.gmailService.getAllAccounts()
                
                if !gmailAccounts.isEmpty {
                    // We have valid accounts in keychain
                    self.accounts = gmailAccounts
                    self.isAuthenticated = true
                    self.sessionState = .authenticated
                    logSuccess("Auth: Found \(gmailAccounts.count) authenticated account(s)", category: "Auth")
                } else {
                    // No accounts in keychain - clear all caches and require login
                    logWarning("Auth: No accounts in keychain - clearing caches and requiring login", category: "Auth")
                    self.clearAllCaches()
                    self.accounts = []
                    self.isAuthenticated = false
                    self.sessionState = .needsLogin
                }
            }
        }
    }
    
    /// Clear all local caches when accounts are disconnected
    private func clearAllCaches() {
        Task {
            await DashboardCache.shared.clear()
            await EmailCache.shared.clearAll()
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
        
        let account = try await gmailService.signIn(presentingViewController: rootViewController)
        logSuccess("Auth: Signed in as \(account.email)", category: "Auth")
        
        // Reload accounts
        self.accounts = gmailService.getAllAccounts()
        self.isAuthenticated = true
        self.sessionState = .authenticated
        
        // Post notification so dashboard refreshes
        NotificationCenter.default.post(name: NSNotification.Name("AccountAdded"), object: nil)
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
