import SwiftUI

/// Gmail accounts, add account, per-account disconnect (shared iOS + macOS).
public struct SettingsConnectedAccountsView: View {
    @EnvironmentObject public var authManager: AuthManager
    @Binding public var isAddingAccount: Bool

    public let accentColor: Color
    public let onAddGmailAccount: () -> Void

    @State private var accountToDisconnect: GmailAccount?
    @State private var showDisconnectConfirmation = false

    public init(
        isAddingAccount: Binding<Bool>,
        accentColor: Color = AppThemePalette.defaultDarkGold.accent,
        onAddGmailAccount: @escaping () -> Void
    ) {
        self._isAddingAccount = isAddingAccount
        self.accentColor = accentColor
        self.onAddGmailAccount = onAddGmailAccount
    }

    public var body: some View {
        List {
            Section {
                ForEach(authManager.accounts) { account in
                    SettingsConnectedAccountRow(
                        account: account,
                        accent: accentColor,
                        onDisconnect: {
                            accountToDisconnect = account
                            showDisconnectConfirmation = true
                        }
                    )
                }

                Button {
                    onAddGmailAccount()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(accentColor)
                        Text("Add Gmail Account")
                            .font(SharedAppTheme.body)
                            .foregroundStyle(accentColor)
                        Spacer()
                        if isAddingAccount {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isAddingAccount)
            } header: {
                Text("Accounts")
            } footer: {
                if authManager.accounts.isEmpty {
                    Text("No accounts connected. Add a Gmail account to get started.")
                } else {
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        #if os(macOS)
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .tint(accentColor)
        #endif
        .navigationTitle("Connected Accounts")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Disconnect Account?", isPresented: $showDisconnectConfirmation) {
            Button("Cancel", role: .cancel) {
                accountToDisconnect = nil
            }
            Button("Disconnect", role: .destructive) {
                if let account = accountToDisconnect {
                    authManager.logout(accountEmail: account.email)
                    NotificationCenter.default.post(name: .cacheCleared, object: nil)
                }
                accountToDisconnect = nil
            }
        } message: {
            if let account = accountToDisconnect {
                Text(disconnectExplanation(for: account))
            } else {
                Text("This will disconnect the account from the app.")
            }
        }
    }

    private func disconnectExplanation(for account: GmailAccount) -> String {
        var lines: [String] = []
        lines.append("You will remove \(account.email) from \(AppearanceSettingsStore.shared.resolvedDisplayName).")
        if authManager.accounts.count == 1 {
            lines.append("This is your only account: signing out clears local app data on this device.")
        }
        return lines.joined(separator: "\n\n")
    }
}
