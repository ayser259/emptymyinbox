//
//  AccountsView.swift
//  emptyMyInbox
//
//  View for managing email accounts
//

import SwiftUI

struct AccountsView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var accounts: [EmailAccount] = []
    @State private var isLoading = false
    @State private var isAddingAccount = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            AppTheme.primaryBackground
                .ignoresSafeArea()
                
                if isLoading && accounts.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.spacingMedium) {
                            // Add account button
                            Button {
                                Task {
                                    await addGmailAccount()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                    
                                    Text("Add Gmail Account")
                                        .font(AppTheme.headline)
                                    
                                    Spacer()
                                    
                                    if isAddingAccount {
                                        ProgressView()
                                    }
                                }
                                .foregroundColor(AppTheme.primaryText)
                                .padding(AppTheme.spacingMedium)
                                .background(AppTheme.secondaryBackground)
                                .cornerRadius(AppTheme.cornerRadiusMedium)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .disabled(isAddingAccount)
                            .padding(.horizontal, AppTheme.spacingMedium)
                            .padding(.top, AppTheme.spacingMedium)
                            
                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .font(AppTheme.footnote)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, AppTheme.spacingMedium)
                            }
                            
                            // Accounts list
                            if accounts.isEmpty {
                                VStack(spacing: AppTheme.spacingMedium) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 48))
                                        .foregroundColor(AppTheme.secondaryText)
                                    
                                    Text("No accounts connected")
                                        .font(AppTheme.title3)
                                        .primaryText()
                                    
                                    Text("Add a Gmail account to get started")
                                        .font(AppTheme.body)
                                        .secondaryText()
                                        .multilineTextAlignment(.center)
                                }
                                .padding(AppTheme.spacingXLarge)
                            } else {
                                VStack(spacing: AppTheme.spacingSmall) {
                                    ForEach(accounts, id: \.id) { account in
                                        AccountRow(account: account)
                                    }
                                }
                                .padding(.horizontal, AppTheme.spacingMedium)
                            }
                        }
                        .padding(.bottom, AppTheme.spacingLarge)
                    }
                    .refreshable {
                        await loadAccounts()
                    }
                }
            }
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.large)
        .customBackButton()
        .task {
            await loadAccounts()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccountConnected"))) { _ in
            Task {
                // Wait a moment for backend to finish processing
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await loadAccounts()
            }
        }
    }
    
    private func loadAccounts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let fetchedAccounts = try await APIService.shared.getAccounts()
            await MainActor.run {
                self.accounts = fetchedAccounts
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func addGmailAccount() async {
        isAddingAccount = true
        errorMessage = nil
        defer { isAddingAccount = false }
        
        do {
            // Get Gmail OAuth URL from backend, include redirect back into the app
            let redirectURI = "emptymyinbox://account_connected"
            let authURL = try await APIService.shared.getGmailAuthURL(redirectURI: redirectURI)
            
            // Open URL in Safari/WebView
            if let url = URL(string: authURL) {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
                
                // Note: The OAuth callback will be handled by the backend
                // and the user will be redirected back. We'll need to refresh
                // accounts after a delay or use a notification
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await loadAccounts()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to add account: \(error.localizedDescription)"
            }
        }
    }
}

struct AccountRow: View {
    let account: EmailAccount
    
    var body: some View {
        HStack(spacing: AppTheme.spacingMedium) {
            // Account icon
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.accent)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(account.email)
                    .font(AppTheme.headline)
                    .primaryText()
                
                if account.is_active {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        
                        Text("Active")
                            .font(AppTheme.caption)
                            .foregroundColor(AppTheme.secondaryText)
                    }
                }
                
                if let lastSync = account.last_sync {
                    Text("Last synced: \(formatDate(lastSync))")
                        .font(AppTheme.caption)
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                }
            }
            
            Spacer()
            
            Text("\(account.email_count)")
                .font(AppTheme.subheadline)
                .foregroundColor(AppTheme.accent)
                .padding(.horizontal, AppTheme.spacingUnit)
                .padding(.vertical, 4)
                .background(AppTheme.accentMuted)
                .cornerRadius(AppTheme.cornerRadiusSmall)
        }
        .padding(AppTheme.spacingMedium)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: date)
        }
        return ""
    }
}

#Preview {
    AccountsView()
        .environmentObject(AuthManager())
}

