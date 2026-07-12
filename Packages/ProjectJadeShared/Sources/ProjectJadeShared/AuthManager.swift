//
//  AuthManager.swift
//  Shared authentication state for iOS and macOS.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

public class AuthManager: ObservableObject {
    public enum SessionState: Equatable {
        case checking
        case authenticated
        case needsLogin
    }
    
    @Published public var isAuthenticated = false
    @Published public var isLoading = false
    @Published public var sessionState: SessionState = .checking
    @Published public var accounts: [GmailAccount] = []
    
    private let gmailService: GmailServiceProtocol
    private let emailCache: EmailCacheProtocol
    private let dashboardCache: DashboardCacheProtocol
    
    public init(
        gmailService: GmailServiceProtocol = GmailAPIService.shared,
        emailCache: EmailCacheProtocol = EmailCache.shared,
        dashboardCache: DashboardCacheProtocol = DashboardCache.shared
    ) {
        self.gmailService = gmailService
        self.emailCache = emailCache
        self.dashboardCache = dashboardCache
        checkAuthStatus()
    }
    
    public func checkAuthStatus() {
        sessionState = .checking
        logDebug("Auth: checking saved session…", category: "Auth")
        Task { @MainActor in
            let gmailAccounts = self.gmailService.getAllAccounts()

            if !gmailAccounts.isEmpty {
                self.accounts = gmailAccounts
                self.isAuthenticated = true
                self.sessionState = .authenticated
                logDebug("Auth: Found \(gmailAccounts.count) authenticated account(s)", category: "Auth")
                Telemetry.counter("auth.accounts_loaded", delta: gmailAccounts.count)
                if let api = self.gmailService as? GmailAPIService {
                    await api.restoreGoogleSignInSessionIfNeeded()
                }
                await VaultManager.shared.detachActiveVaultIfOwnerNotAmongConnectedAccounts()
            } else {
                switch self.gmailService.getAccountsLoadStatus() {
                case .notFound:
                    logDebug("Auth: No saved Gmail session yet (sign in to store accounts in keychain)", category: "Auth")
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
                logDebug("Auth: showing sign-in (no saved accounts)", category: "Auth")
            }
        }
    }
    
    private func clearAllCaches(removedEmail: String?, accountsEmpty: Bool) {
        Task {
            await dashboardCache.clear()
            await emailCache.clearAll()
            if let email = removedEmail {
                await CalendarCache.shared.clear(accountEmail: email)
                await SenderCache.shared.clear(accountEmail: email)
            } else {
                await CalendarCache.shared.clearAll()
                await SenderCache.shared.clearAll()
            }
            await CalendarVisibilityStore.shared.refreshFromConnectedAccounts()
            await AccountInclusionStore.shared.refreshFromConnectedAccounts()
            if accountsEmpty {
                await VaultManager.shared.purgeAllLocalVaultMirrorsAndReset()
                await InterestProfileStore.shared.clear()
                await StoriesFeedStore.shared.clear()
                Telemetry.event("auth.full_sign_out_local_data_purged")
                logInfo("Auth: Purged vault mirrors and app-support data after full sign-out", category: "Auth")
            } else {
                await clearVaultConfigIfNeeded(removedEmail: removedEmail)
            }
            Telemetry.event("auth.cache_cleared")
            logInfo("Auth: Cleared all local caches", category: "Auth")
        }
    }

    /// When an account disconnects, drop the active vault if it was tied to that account (any backend).
    ///
    /// Previously we only cleared `.googleDrive` prefs and matched `driveAccountEmail` exactly, so local / folder vaults
    /// (and case-mismatched emails) could stay linked to a disconnected account. We also reload `VaultManager` so
    /// in-memory state matches disk (otherwise the UI could still show the old owner until restart).
    private func clearVaultConfigIfNeeded(removedEmail: String?) async {
        guard let removedEmail, !removedEmail.isEmpty else { return }
        let config = await VaultSettingsStore.shared.activeConfiguration()
        guard let config else { return }
        guard let owner = config.resolvedOwnerEmail else { return }
        guard owner.caseInsensitiveCompare(removedEmail) == .orderedSame else { return }
        let mirrorId = config.vaultId
        await VaultSettingsStore.shared.clearActiveConfiguration()
        await VaultManager.shared.reloadFromPreferences()
        await VaultManager.shared.removeLocalMirrorDirectoryIfPresent(vaultId: mirrorId)
        logInfo("Auth: Cleared vault config (owner \(owner)) for disconnected account", category: "Auth")
    }
    
    @MainActor
    public func signInWithGoogle() async throws {
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
        
        self.accounts = gmailService.getAllAccounts()
        self.isAuthenticated = true
        self.sessionState = .authenticated
        await VaultManager.shared.detachActiveVaultIfOwnerNotAmongConnectedAccounts()
        await CalendarVisibilityStore.shared.refreshFromConnectedAccounts()

        NotificationCenter.default.post(name: .accountAdded, object: nil)
        #elseif os(macOS)
        guard let api = gmailService as? GmailAPIService else {
            throw GmailAPIError.configurationError
        }
        let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first
        let account = try await api.signIn(presentingWindow: window)
        logSuccess("Auth: Signed in as \(account.email)", category: "Auth")
        Telemetry.event("auth.sign_in.success", metadata: ["account_hash": Telemetry.hashForDiagnostics(account.email)])
        self.accounts = gmailService.getAllAccounts()
        self.isAuthenticated = true
        self.sessionState = .authenticated
        await VaultManager.shared.detachActiveVaultIfOwnerNotAmongConnectedAccounts()
        await CalendarVisibilityStore.shared.refreshFromConnectedAccounts()
        NotificationCenter.default.post(name: .accountAdded, object: nil)
        #else
        throw GmailAPIError.configurationError
        #endif
    }
    
    @MainActor
    public func logout(accountEmail: String? = nil) {
        gmailService.signOut(accountEmail: accountEmail)
        self.accounts = gmailService.getAllAccounts()
        clearAllCaches(removedEmail: accountEmail, accountsEmpty: self.accounts.isEmpty)

        if self.accounts.isEmpty {
            self.isAuthenticated = false
            self.sessionState = .needsLogin
            logSuccess("Auth: Logged out, cleared all data", category: "Auth")
        } else {
            logSuccess("Auth: Disconnected \(accountEmail ?? "account"), caches cleared", category: "Auth")
        }
    }
}
