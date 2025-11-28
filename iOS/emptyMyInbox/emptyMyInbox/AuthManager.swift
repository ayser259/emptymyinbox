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
                    self.accounts = gmailAccounts
                    self.isAuthenticated = true
                    self.sessionState = .authenticated
        } else {
                    // Check if we have cached data for offline access
            Task {
                if let cachedSnapshot = await DashboardDataManager.shared.loadCachedSnapshot(),
                           !cachedSnapshot.accounts.isEmpty {
                    await MainActor.run {
                                self.isAuthenticated = true
                                self.sessionState = .authenticated
                    }
                } else {
                    await MainActor.run {
                                self.isAuthenticated = false
                        self.sessionState = .needsLogin
                            }
                        }
                    }
                }
            }
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
        
        _ = try await gmailService.signIn(presentingViewController: rootViewController)
        
        // Reload accounts
        self.accounts = gmailService.getAllAccounts()
        self.isAuthenticated = true
        self.sessionState = .authenticated
        #else
        throw GmailAPIError.configurationError
        #endif
    }
    
    @MainActor
    func logout(accountEmail: String? = nil) {
        gmailService.signOut(accountEmail: accountEmail)
        self.accounts = gmailService.getAllAccounts()
        
        if self.accounts.isEmpty {
        self.isAuthenticated = false
        self.sessionState = .needsLogin
    }
    }
}

