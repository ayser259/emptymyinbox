import SwiftUI

/// Shared settings list used by iOS menu sheet and macOS settings panel.
public struct AppSettingsMenuContent<Vault: View>: View {
    @EnvironmentObject public var authManager: AuthManager
    @Binding public var isAddingAccount: Bool
    @StateObject private var debugSettings = DebugSettings.shared
    @State private var showClearedAlert = false
    @State private var showDebugLogs = false
    @State private var cachedEmailCount: Int = 0
    @State private var accountToDisconnect: GmailAccount?
    @State private var showDisconnectConfirmation = false

    private let vaultSettings: () -> Vault
    private let onAddGmailAccount: () -> Void
    private let onDismiss: () -> Void
    private let accentColor: Color

    public init(
        vaultSettings: @escaping () -> Vault,
        isAddingAccount: Binding<Bool>,
        onAddGmailAccount: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        accentColor: Color = SharedAppTheme.accent
    ) {
        self.vaultSettings = vaultSettings
        self._isAddingAccount = isAddingAccount
        self.onAddGmailAccount = onAddGmailAccount
        self.onDismiss = onDismiss
        self.accentColor = accentColor
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
                Text("Connected Accounts")
            } footer: {
                if authManager.accounts.isEmpty {
                    Text("No accounts connected. Add a Gmail account to get started.")
                } else {
                    Text("Tap the disconnect button to remove an account. You can reconnect it anytime.")
                }
            }

            Section {
                HStack {
                    SwiftUI.Label("Cached Emails", systemImage: "internaldrive")
                    Spacer()
                    Text("\(cachedEmailCount) emails")
                        .font(SharedAppTheme.caption)
                        .foregroundStyle(SharedAppTheme.secondaryText)
                }

                Button {
                    Task {
                        await DashboardCache.shared.clear()
                        await EmailCache.shared.clearAll()
                        await MainActor.run {
                            cachedEmailCount = 0
                            NotificationCenter.default.post(name: .cacheCleared, object: nil)
                            showClearedAlert = true
                        }
                    }
                } label: {
                    SwiftUI.Label("Clear Cache", systemImage: "trash")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Local Storage")
            } footer: {
                Text("Email content is stored locally for fast access and offline viewing.")
            }

            Section {
                NavigationLink {
                    vaultSettings()
                } label: {
                    HStack {
                        Image(systemName: "shippingbox")
                            .foregroundStyle(accentColor)
                        Text("Vault")
                    }
                }
            } header: {
                Text("Vault")
            } footer: {
                Text("Store Calendar and Action Items as files in Inbox, Calendar, and Action Items folders—locally, in a synced folder, or on Google Drive.")
            }

            Section {
                NavigationLink {
                    CalendarVisibilitySettingsView()
                } label: {
                    HStack {
                        Image(systemName: "eye.slash.circle")
                            .foregroundStyle(accentColor)
                        Text("Calendar visibility")
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                Text("Choose which connected accounts and Google calendars appear in the Calendar tab.")
            }

            Section {
                Button {
                    authManager.logout()
                    onDismiss()
                } label: {
                    SwiftUI.Label("Logout All Accounts", systemImage: "arrow.right.square")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Account")
            } footer: {
                Text("This will disconnect all accounts and clear local data.")
            }

            Section {
                NavigationLink {
                    LLMManagementView()
                } label: {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(accentColor)
                        Text("LLM Management")
                    }
                }

                NavigationLink {
                    FeatureInclusionSettingsView()
                } label: {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(accentColor)
                        Text("Feature Inclusions")
                    }
                }
            } header: {
                Text("AI")
            } footer: {
                Text("Configure API key, model tiering, and runtime settings.")
            }

            Section {
                Toggle(isOn: $debugSettings.isDebugModeEnabled) {
                    HStack {
                        Image(systemName: "hammer.fill")
                            .foregroundStyle(debugSettings.isDebugModeEnabled ? .purple : SharedAppTheme.secondaryText)
                        Text("Debug Mode")
                    }
                }
                .tint(.purple)

                Button {
                    showDebugLogs = true
                } label: {
                    HStack {
                        SwiftUI.Label("Debug Logs", systemImage: "ladybug")
                        Spacer()
                        Text("\(DebugLogger.shared.entries.count)")
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                    }
                }
            } header: {
                Text("Developer")
            } footer: {
                if debugSettings.isDebugModeEnabled {
                    Text("Debug mode is ON. Copy buttons will appear in email views.")
                        .foregroundStyle(.purple)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onDismiss()
                }
                .foregroundStyle(accentColor)
            }
        }
        .alert("Cache cleared", isPresented: $showClearedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Local cache was removed.")
        }
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
                Text("This will disconnect \(account.email) from the app. You can reconnect it later.")
            } else {
                Text("This will disconnect the account from the app.")
            }
        }
        .sheet(isPresented: $showDebugLogs) {
            DebugLogView()
        }
        .task {
            cachedEmailCount = await EmailCache.shared.cachedEmailCount()
        }
    }
}
