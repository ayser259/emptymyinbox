//
//  MenuView.swift
//  emptyMyInbox
//
//  Menu view for account management and settings
//

import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
import EmptyMyInboxShared

struct MenuView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var isAddingAccount = false

    var body: some View {
        NavigationStack {
            AppSettingsMenuContent(
                vaultSettings: { VaultSettingsView() },
                isAddingAccount: $isAddingAccount,
                onAddGmailAccount: { addGmailAccount() },
                onDismiss: { dismiss() },
                accentColor: AppTheme.accent
            )
            .environmentObject(authManager)
        }
    }

    private func addGmailAccount() {
        isAddingAccount = true
        Task {
            do {
                #if canImport(UIKit)
                guard let windowScene = await MainActor.run(body: {
                    UIApplication.shared.connectedScenes.first as? UIWindowScene
                }),
                      let rootViewController = await MainActor.run(body: {
                          windowScene.windows.first?.rootViewController
                      }) else {
                    await MainActor.run { isAddingAccount = false }
                    return
                }

                _ = try await GmailAPIService.shared.signIn(presentingViewController: rootViewController)

                await MainActor.run {
                    authManager.accounts = GmailAPIService.shared.getAllAccounts()
                    NotificationCenter.default.post(name: .accountAdded, object: nil)
                    isAddingAccount = false
                }
                #endif
            } catch {
                logError("Error adding Gmail account: \(error)", category: "Auth")
                await MainActor.run { isAddingAccount = false }
            }
        }
    }
}
