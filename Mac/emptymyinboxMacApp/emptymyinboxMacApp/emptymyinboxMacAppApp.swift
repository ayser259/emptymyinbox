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
                    await VaultManager.shared.detachActiveVaultIfOwnerNotAmongConnectedAccounts()
                    await AppLifecycleCloudSync.performStartupSync()
                }
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
        .commands {
            CommandMenu("Go") {
                Button("Mail") {
                    NotificationCenter.default.post(name: .macSelectRootTab, object: MacRootTab.mail.rawValue)
                }
                .keyboardShortcut("1", modifiers: .command)
                Button("Calendar") {
                    NotificationCenter.default.post(name: .macSelectRootTab, object: MacRootTab.calendar.rawValue)
                }
                .keyboardShortcut("2", modifiers: .command)
                Button("Action Items") {
                    NotificationCenter.default.post(name: .macSelectRootTab, object: MacRootTab.actionItems.rawValue)
                }
                .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button("Next Primary Tab") {
                    NotificationCenter.default.post(name: .macCycleRootTabForward, object: nil)
                }
                .keyboardShortcut(.tab, modifiers: .control)
                Button("Refresh") {
                    NotificationCenter.default.post(name: .macRefreshCurrentRootTab, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Catch Up") {
                    NotificationCenter.default.post(name: .macSelectMailTool, object: "catchUp")
                }
                .keyboardShortcut("c", modifiers: .option)
                Button("Stories") {
                    NotificationCenter.default.post(name: .macSelectMailTool, object: "stories")
                }
                .keyboardShortcut("s", modifiers: .option)
                Button("Brief") {
                    NotificationCenter.default.post(name: .macSelectMailTool, object: "brief")
                }
                .keyboardShortcut("b", modifiers: .option)
            }
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
