//
//  AccountsView.swift
//  emptyMyInbox
//
//  View for managing email accounts
//

import SwiftUI
import UIKit
import AuthenticationServices

struct AccountsView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var accounts: [EmailAccount] = []
    @State private var isLoading = false
    @State private var isAddingAccount = false
    @State private var errorMessage: String?
    @State private var authSession: ASWebAuthenticationSession?
    @State private var lastRefreshTime: Date?
    @State private var unreadCountsByEmail: [String: Int] = [:]
    
    private let authSessionCoordinator = AuthenticationSessionCoordinator()
    
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
                            
                            if let lastRefreshTime {
                                RefreshStatusView(
                                    lastRefreshTime: lastRefreshTime,
                                    mostRecentEmailTime: nil
                                )
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
                                        NavigationLink {
                                            AccountDetailView(account: account)
                                        } label: {
                                            AccountRow(
                                                account: account,
                                                unreadCount: unreadCountsByEmail[account.email],
                                                dashboardRefreshTime: lastRefreshTime
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, AppTheme.spacingMedium)
                            }
                        }
                        .padding(.bottom, AppTheme.spacingLarge)
                    }
                    .refreshable {
                        await refreshAccounts()
                    }
                }
            }
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.large)
        .customBackButton()
        .task {
            await loadCachedAccounts()
        }
    }
    
    private func loadCachedAccounts() async {
        isLoading = accounts.isEmpty
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            await MainActor.run {
                applySnapshot(snapshot)
            }
        }
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func refreshAccounts() async {
        isLoading = true
        if let snapshot = await DashboardDataManager.shared.refreshData(shouldSync: true) {
            await MainActor.run {
                applySnapshot(snapshot)
            }
        } else {
            await MainActor.run {
                self.errorMessage = "Unable to refresh accounts. Please try again."
            }
        }
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func addGmailAccount() async {
        isAddingAccount = true
        errorMessage = nil
        defer { isAddingAccount = false }
        
        do {
            // Get the root view controller for Google Sign-In
            let rootViewController: UIViewController? = await MainActor.run {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootVC = windowScene.windows.first?.rootViewController else {
                    return nil
                }
                return rootVC
            }
            
            guard let rootViewController = rootViewController else {
                await MainActor.run {
                    self.errorMessage = "Unable to start authentication"
                }
                return
            }
            
            // Sign in directly with Google using GmailAPIService
            let gmailAccount = try await GmailAPIService.shared.signIn(presentingViewController: rootViewController)
            
            logSuccess("Successfully authenticated Gmail account: \(gmailAccount.email)", category: "Auth")
            
            // Immediately add account to snapshot optimistically (so it shows up right away)
            await addAccountOptimistically(gmailAccount: gmailAccount)
            
            // Then do full sync in background
            await refreshAccounts()
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to add account: \(error.localizedDescription)"
            }
            logError("Gmail authentication failed: \(error)", category: "Auth")
        }
    }
    
    private func addAccountOptimistically(gmailAccount: GmailAccount) async {
        // Load current snapshot
        guard let currentSnapshot = await DashboardDataManager.shared.loadCachedSnapshot() else {
            // No snapshot yet, create a new one with just this account
            let dateFormatter = ISO8601DateFormatter()
            let newAccount = EmailAccount(
                id: gmailAccount.numericId,
                email: gmailAccount.email,
                is_active: true,
                last_sync: nil, // nil = "Never synced" / "Syncing..."
                created_at: dateFormatter.string(from: Date()),
                email_count: 0 // Will be updated after sync
            )
            
            let newSnapshot = DashboardDataSnapshot(
                timestamp: Date(),
                accounts: [newAccount],
                emails: [],
                allEmails: [],
                starredEmails: [],
                labels: []
            )
            
            await DashboardCache.shared.saveSnapshot(newSnapshot)
            await MainActor.run {
                applySnapshot(newSnapshot)
            }
            return
        }
        
        // Check if account already exists
        if currentSnapshot.accounts.contains(where: { $0.email == gmailAccount.email }) {
            // Account already exists, no need to add
            return
        }
        
        // Create new account (optimistically, before sync)
        let dateFormatter = ISO8601DateFormatter()
        let newAccount = EmailAccount(
            id: gmailAccount.numericId,
            email: gmailAccount.email,
            is_active: true,
            last_sync: nil, // nil = "Never synced" / "Syncing..."
            created_at: dateFormatter.string(from: Date()),
            email_count: 0 // Will be updated after sync
        )
        
        // Add to existing accounts
        var updatedAccounts = currentSnapshot.accounts
        updatedAccounts.append(newAccount)
        
        // Create updated snapshot
        let updatedSnapshot = DashboardDataSnapshot(
            timestamp: Date(),
            accounts: updatedAccounts,
            emails: currentSnapshot.emails,
            allEmails: currentSnapshot.allEmails,
            starredEmails: currentSnapshot.starredEmails,
            labels: currentSnapshot.labels
        )
        
        // Save updated snapshot
        await DashboardCache.shared.saveSnapshot(updatedSnapshot)
        
        // Update local state
        await MainActor.run {
            applySnapshot(updatedSnapshot)
            // Notify DashboardView to refresh (so new account shows immediately)
            NotificationCenter.default.post(name: NSNotification.Name("AccountAdded"), object: nil)
        }
    }
    
    @MainActor
    private func applySnapshot(_ snapshot: DashboardDataSnapshot) {
        self.accounts = snapshot.accounts
        self.lastRefreshTime = snapshot.timestamp
        self.unreadCountsByEmail = calculateUnreadCounts(from: snapshot.emails)
        self.errorMessage = nil
    }
    
    private func calculateUnreadCounts(from emails: [EmailListItem]) -> [String: Int] {
        let unreadEmails = emails.filter { !$0.is_read }
        let grouped = Dictionary(grouping: unreadEmails, by: { $0.account_email })
        return grouped.mapValues { $0.count }
    }
}

private final class AuthenticationSessionCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return ASPresentationAnchor()
        }
        return window
    }
}

struct AccountRow: View {
    let account: EmailAccount
    let unreadCount: Int?
    let dashboardRefreshTime: Date?
    
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
                
                if let dashboardRefreshTime {
                    Text("Last refreshed: \(formatDate(dashboardRefreshTime))")
                        .font(AppTheme.caption)
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                }
                
                if let lastSync = account.last_sync {
                    Text("Gmail sync: \(formatDate(lastSync))")
                        .font(AppTheme.caption)
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                }
            }
            
            Spacer()
            
            Text("\(unreadCount ?? account.email_count)")
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

struct AccountDetailView: View {
    let account: EmailAccount
    @EnvironmentObject var authManager: AuthManager
    @State private var emails: [EmailListItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastRefreshTime: Date?
    @State private var mostRecentEmailTime: Date?
    @State private var unreadCountForChip: Int = 0
    
    var body: some View {
        ZStack {
            AppTheme.primaryBackground
                .ignoresSafeArea()
            
            if isLoading && emails.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: AppTheme.spacingMedium) {
                        catchUpEntry
                        
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(AppTheme.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(AppTheme.spacingMedium)
                                .background(AppTheme.secondaryBackground)
                                .cornerRadius(AppTheme.cornerRadiusMedium)
                        }
                        
                        if emails.isEmpty {
                            VStack(spacing: AppTheme.spacingMedium) {
                                Image(systemName: "envelope.badge")
                                    .font(.system(size: 48))
                                    .foregroundColor(AppTheme.secondaryText)
                                
                                Text("No emails yet")
                                    .font(AppTheme.title3)
                                    .primaryText()
                                
                                Text("We couldn't find any messages for \(account.email).")
                                    .font(AppTheme.body)
                                    .secondaryText()
                                    .multilineTextAlignment(.center)
                            }
                            .padding(AppTheme.spacingXLarge)
                            .frame(maxWidth: .infinity)
                            .background(AppTheme.secondaryBackground)
                            .cornerRadius(AppTheme.cornerRadiusLarge)
                        } else {
                            if let lastRefresh = lastRefreshTime {
                                RefreshStatusView(
                                    lastRefreshTime: lastRefresh,
                                    mostRecentEmailTime: mostRecentEmailTime
                                )
                                .padding(.horizontal, AppTheme.spacingMedium)
                            }
                            
                            LazyVStack(spacing: 0) {
                                ForEach(emails, id: \.id) { email in
                                    GmailStyleEmailRow(email: email)
                                        .padding(.horizontal, AppTheme.spacingMedium)
                                        .padding(.vertical, 4)
                                }
                            }
                            .padding(.vertical, AppTheme.spacingSmall)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                                    .fill(AppTheme.secondaryBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingMedium)
                    .padding(.top, AppTheme.spacingMedium)
                    .padding(.bottom, AppTheme.spacingLarge)
                }
                .refreshable {
                    await refreshEmails()
                }
            }
        }
        .navigationTitle(account.email)
        .navigationBarTitleDisplayMode(.inline)
        .customBackButton()
        .task {
            await loadCachedEmails()
            await refreshUnreadCountForChip()
        }
    }
    
    private var catchUpEntry: some View {
        NavigationLink(
            destination: CatchUpView(accountId: account.id, accountEmail: account.email)
                .environmentObject(authManager)
        ) {
            ShortcutActionChip(
                title: "Catch up",
                subtitle: "\(unreadCountForChip) unread • \(account.email)",
                icon: "bolt.fill",
                badgeText: unreadCountForChip > 0 ? "\(unreadCountForChip)" : nil
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func refreshUnreadCountForChip() async {
        // loadUnreadEmails already filters out starred emails
        let count = await EmailCache.shared.loadUnreadEmails(accountId: account.id).count
        await MainActor.run {
            self.unreadCountForChip = count
        }
    }
    
    private func loadCachedEmails() async {
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            let cachedEmails = snapshot.allEmails.filter { $0.account_email == account.email }
            await MainActor.run {
                self.emails = cachedEmails
                self.lastRefreshTime = snapshot.timestamp
                if let mostRecent = cachedEmails.first {
                    self.mostRecentEmailTime = parseDate(mostRecent.received_at)
                } else {
                    self.mostRecentEmailTime = nil
                }
            }
        }
    }
    
    private func refreshEmails() async {
        isLoading = true
        if let snapshot = await DashboardDataManager.shared.refreshData(shouldSync: true) {
            let filtered = snapshot.allEmails.filter { $0.account_email == account.email }
            await MainActor.run {
                self.emails = filtered
                self.lastRefreshTime = snapshot.timestamp
                self.errorMessage = nil
                if let mostRecent = filtered.first {
                    self.mostRecentEmailTime = parseDate(mostRecent.received_at)
                } else {
                    self.mostRecentEmailTime = nil
                }
            }
        } else {
            await MainActor.run {
                self.errorMessage = "Unable to refresh emails. Please try again."
            }
        }
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString)
    }
}

struct ShortcutActionChip: View {
    let title: String
    let subtitle: String
    let icon: String
    let badgeText: String?
    
    var body: some View {
        HStack(spacing: AppTheme.spacingMedium) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.8))
                    .tracking(0.8)
                Text(subtitle)
                    .font(AppTheme.subheadline)
                    .primaryText()
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            
            Spacer()
            
            if let badgeText {
                Text(badgeText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.secondaryText.opacity(0.8))
        }
        .padding(AppTheme.spacingMedium)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                .fill(AppTheme.secondaryBackground)
                .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

#Preview {
    AccountsView()
        .environmentObject(AuthManager())
}

