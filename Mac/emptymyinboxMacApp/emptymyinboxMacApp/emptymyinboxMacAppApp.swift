//
//  emptymyinboxMacAppApp.swift
//  emptymyinboxMacApp
//

import SwiftUI
import GoogleSignIn
import EmptyMyInboxShared

struct MacAppEnvironment {
    let gmailService: GmailServiceProtocol
    let emailCache: EmailCacheProtocol
    let dashboardCache: DashboardCacheProtocol

    static let live = MacAppEnvironment(
        gmailService: GmailAPIService.shared,
        emailCache: EmailCache.shared,
        dashboardCache: DashboardCache.shared
    )
}

@main
struct emptymyinboxMacAppApp: App {
    @StateObject private var authManager: AuthManager

    init() {
        let environment = MacAppEnvironment.live
        _authManager = StateObject(
            wrappedValue: AuthManager(
                gmailService: environment.gmailService,
                emailCache: environment.emailCache,
                dashboardCache: environment.dashboardCache
            )
        )

        let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String
        if let clientID, !clientID.isEmpty {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            logSuccess("Google Sign-In configured for macOS", category: "Auth")
        } else {
            logWarning("GIDClientID missing — add Info.plist keys", category: "Auth")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .preferredColorScheme(.dark)
                .tint(MacAppTheme.accent)
                .task {
                    await VaultManager.shared.reloadFromPreferences()
                    await AppLifecycleCloudSync.performStartupSync()
                }
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
        .commands {
            CommandMenu("Account") {
                Button("Sign Out") {
                    authManager.logout()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandMenu("Vault") {
                Button("Vault Settings…") {
                    NotificationCenter.default.post(name: .macOpenVaultSettings, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }
    }
}
