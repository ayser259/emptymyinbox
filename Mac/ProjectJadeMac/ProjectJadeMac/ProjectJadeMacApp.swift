//
//  ProjectJadeMacApp.swift
//  ProjectJadeMac
//

import SwiftUI
import GoogleSignIn
import ProjectJadeShared

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
struct ProjectJadeMacApp: App {
    @StateObject private var authManager: AuthManager
    @StateObject private var appearanceSettings = AppearanceSettingsStore.shared

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
            logWarning("GIDClientID missing - add Info.plist keys", category: "Auth")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(appearanceSettings)
                .preferredColorScheme(appearanceSettings.swiftUIColorScheme)
                .tint(appearanceSettings.resolvedPalette.accent)
                .appThemePalette(appearanceSettings.resolvedPalette)
                .task {
                    await AppLifecycleCloudSync.performStartupSync()
                }
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
        .commands {
            CommandMenu("Go") {
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
        }
    }
}
