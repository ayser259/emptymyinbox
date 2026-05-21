//
//  emptyMyInboxApp.swift
//  emptyMyInbox
//
//  Created by Ayser Choudhury on 11/7/25.
//

import SwiftUI
import GoogleSignIn
import EmptyMyInboxShared

struct AppEnvironment {
    let gmailService: GmailServiceProtocol
    let emailCache: EmailCacheProtocol
    let dashboardCache: DashboardCacheProtocol
    
    static let live = AppEnvironment(
        gmailService: GmailAPIService.shared,
        emailCache: EmailCache.shared,
        dashboardCache: DashboardCache.shared
    )
}

@main
struct emptyMyInboxApp: App {
    @StateObject private var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        let environment = AppEnvironment.live
        _authManager = StateObject(
            wrappedValue: AuthManager(
                gmailService: environment.gmailService,
                emailCache: environment.emailCache,
                dashboardCache: environment.dashboardCache
            )
        )
        // Suppress WebKit console noise by setting environment variable
        // This reduces the RBS assertion errors and process termination messages
        setenv("OS_ACTIVITY_MODE", "disable", 1)
        
        // Configure Google Sign-In
        // Try GIDClientID first (preferred by Google Sign-In SDK), then fallback to GOOGLE_CLIENT_ID
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String
        
        if let clientID = clientID, !clientID.isEmpty {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            logSuccess("Google Sign-In configured with Client ID: \(clientID)", category: "Auth")
        } else {
            logWarning("GIDClientID or GOOGLE_CLIENT_ID not found in Info.plist", category: "Auth")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            rootView
            .environmentObject(authManager)
            .preferredColorScheme(.dark) // Force dark mode
            .background(AppTheme.primaryBackground)
            .task {
                await VaultManager.shared.reloadFromPreferences()
                await VaultManager.shared.detachActiveVaultIfOwnerNotAmongConnectedAccounts()
                await AppLifecycleCloudSync.performStartupSync()
                // Clean up old cached emails in background
                Task.detached(priority: .background) {
                    await EmailCache.shared.cleanupOldEmails(olderThanDays: 10)
                }
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .background {
                    Task { await AppLifecycleCloudSync.pushLocalStateOnly() }
                }
                // Only refresh once per day when app comes to foreground
                if oldPhase != .active && newPhase == .active {
                    checkAndRefreshIfNeeded()
                }
            }
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        if GIDSignIn.sharedInstance.handle(url) {
            return
        }
        // Handle OAuth callback
        if url.scheme == "emptymyinbox" {
            if url.host == "account_connected" || url.query?.contains("account_connected=true") == true {
                // Account connected - user can manually refresh if needed
            }
        }
    }
    
    private func checkAndRefreshIfNeeded() {
        // Only refresh once per day (first time app is opened that day)
        let userDefaults = UserDefaults.standard
        let lastAutoRefreshKey = "lastAutoRefreshDate"
        // Get today's date (just the date, not time)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Get last refresh date
        if let lastRefreshDate = userDefaults.object(forKey: lastAutoRefreshKey) as? Date {
            let lastRefreshDay = calendar.startOfDay(for: lastRefreshDate)
            
            // Only refresh if it's a new day
            if calendar.isDate(today, inSameDayAs: lastRefreshDay) {
                // Already refreshed today, skip
                return
            }
        }
        
        // It's a new day (or first time), refresh and save the date
        userDefaults.set(today, forKey: lastAutoRefreshKey)
        
        // Post notification to refresh (only if authenticated)
        if case .authenticated = authManager.sessionState {
            NotificationCenter.default.post(name: .appShouldRefreshData, object: nil)
            NotificationCenter.default.post(name: .companionVaultCalendarActionItemsRefresh, object: nil)

        }
    }
    
    @ViewBuilder
    private var rootView: some View {
        switch authManager.sessionState {
        case .checking:
            SplashView()
        case .authenticated:
            mainAppView
        case .needsLogin:
            LoginView()
        }
    }
    
    @ViewBuilder
    private var mainAppView: some View {
        AdaptiveRootView()
    }
}

extension Notification.Name {
    static let appShouldRefreshData = Notification.Name("AppShouldRefreshData")
}

struct SplashView: View {
    var body: some View {
        ZStack {
            AppTheme.primaryBackground.ignoresSafeArea()
            VStack(spacing: AppTheme.spacingMedium) {
                LogoView(size: 64)
                Text("Loading your inbox…")
                    .font(AppTheme.body)
                    .primaryText()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))
            }
        }
    }
}

struct OfflineBanner: View {
    var message: String?
    var retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.spacingSmall) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundColor(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Working offline")
                        .font(AppTheme.subheadline)
                        .primaryText()
                    if let message = message {
                        Text(message)
                            .font(AppTheme.caption)
                            .secondaryText()
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button("Retry") {
                    retryAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            .padding(AppTheme.spacingMedium)
            .background(AppTheme.secondaryBackground.opacity(0.95))
            Divider()
                .background(AppTheme.accent.opacity(0.5))
        }
        .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)
    }
}
