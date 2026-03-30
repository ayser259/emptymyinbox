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
import EmptyMyInboxShared
#endif

struct MenuView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @StateObject private var debugSettings = DebugSettings.shared
    @State private var showClearedAlert = false
    @State private var showDebugLogs = false
    @State private var cachedEmailCount: Int = 0
    @State private var accountToDisconnect: GmailAccount?
    @State private var showDisconnectConfirmation = false
    @State private var isAddingAccount = false
    
    var body: some View {
        NavigationView {
            List {
                // Connected Accounts section with individual account management
                Section {
                    // Account rows with disconnect buttons
                    ForEach(authManager.accounts) { account in
                        ConnectedAccountRow(
                            account: account,
                            onDisconnect: {
                                accountToDisconnect = account
                                showDisconnectConfirmation = true
                            }
                        )
                    }
                    
                    // Add Gmail button - inside the Connected Accounts section
                    Button {
                        addGmailAccount()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(AppTheme.accent)
                            
                            Text("Add Gmail Account")
                                .font(AppTheme.body)
                                .foregroundColor(AppTheme.accent)
                            
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
                
                // Storage section
                Section {
                    HStack {
                        SwiftUI.Label("Cached Emails", systemImage: "internaldrive")
                        Spacer()
                        Text("\(cachedEmailCount) emails")
                            .font(AppTheme.caption)
                            .foregroundColor(AppTheme.secondaryText)
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
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("Local Storage")
                } footer: {
                    Text("Email content is stored locally for fast access and offline viewing.")
                }

                Section {
                    NavigationLink {
                        VaultSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "shippingbox")
                                .foregroundColor(AppTheme.accent)
                            Text("Vault")
                        }
                    }
                } header: {
                    Text("Vault")
                } footer: {
                    Text("Store Calendar and Action Items as files in Inbox, Calendar, and Action Items folders—locally, in a synced folder, or on Google Drive.")
                }
                
                // Account actions section
                Section {
                    Button {
                        authManager.logout()
                        dismiss()
                    } label: {
                        HStack {
                            SwiftUI.Label("Logout All Accounts", systemImage: "arrow.right.square")
                                .foregroundColor(.red)
                        }
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
                                .foregroundColor(AppTheme.accent)
                            Text("LLM Management")
                        }
                    }

                    NavigationLink {
                        FeatureInclusionSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundColor(AppTheme.accent)
                            Text("Feature Inclusions")
                        }
                    }
                } header: {
                    Text("AI")
                } footer: {
                    Text("Configure API key, model tiering, and runtime settings.")
                }
                
                // Debug section
                Section {
                    // Debug Mode Toggle
                    Toggle(isOn: $debugSettings.isDebugModeEnabled) {
                        HStack {
                            Image(systemName: "hammer.fill")
                                .foregroundColor(debugSettings.isDebugModeEnabled ? .purple : AppTheme.secondaryText)
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
                                .font(AppTheme.caption)
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    if debugSettings.isDebugModeEnabled {
                        Text("Debug mode is ON. Copy buttons will appear in email views.")
                            .foregroundColor(.purple)
                    }
                }
            }
            .primaryBackground()
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .textButton()
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
                // Load cached email count
                cachedEmailCount = await EmailCache.shared.cachedEmailCount()
            }
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
                    // Refresh accounts
                    authManager.accounts = GmailAPIService.shared.getAllAccounts()
                    // Notify dashboard
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

// MARK: - Connected Account Row

struct ConnectedAccountRow: View {
    let account: GmailAccount
    let onDisconnect: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Account icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.3), AppTheme.accent.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: "envelope.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.accent)
            }
            
            // Account info
            VStack(alignment: .leading, spacing: 2) {
                Text(account.email)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: "#4ade80"))
                        .frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
            
            Spacer()
            
            // Disconnect button
            Button {
                onDisconnect()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.5))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

