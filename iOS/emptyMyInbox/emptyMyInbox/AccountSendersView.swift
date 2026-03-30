//
//  AccountSendersView.swift
//  emptyMyInbox
//
//  View for displaying senders for a specific account
//

import SwiftUI
import EmptyMyInboxShared

struct AccountSendersView: View {
    let accountEmail: String
    @State private var allEmails: [EmailListItem] = []
    @State private var isLoading = false
    @State private var isUnreadSendersExpanded = true
    @State private var isSendersExpanded = true
    
    var body: some View {
        ZStack {
            AppTheme.primaryBackground
                .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacingMedium) {
                    // Account header
                    Text(accountEmail)
                        .font(.system(size: 13))
                        .secondaryText()
                        .padding(.horizontal, AppTheme.spacingMedium)
                    
                    // Unread senders
                    CollapsibleSection(
                        title: "Unread senders",
                        count: unreadSendersCount,
                        isExpanded: $isUnreadSendersExpanded
                    ) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if unreadSenders.isEmpty {
                            Text("No unread senders")
                                .font(AppTheme.subheadline)
                                .secondaryText()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppTheme.spacingMedium)
                                .padding(.vertical, AppTheme.spacingSmall)
                        } else {
                            VStack(spacing: 2) {
                                ForEach(unreadSenders, id: \.id) { sender in
                                    NavigationLink(value: EmailFilter.sender(email: sender.email, name: sender.name)) {
                                        SlackStyleSenderRow(sender: sender)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    
                    // All senders
                    CollapsibleSection(
                        title: "All senders",
                        count: allSendersCount,
                        isExpanded: $isSendersExpanded
                    ) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if allSenders.isEmpty {
                            Text("No senders")
                                .font(AppTheme.subheadline)
                                .secondaryText()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppTheme.spacingMedium)
                                .padding(.vertical, AppTheme.spacingSmall)
                        } else {
                            VStack(spacing: 2) {
                                ForEach(allSenders, id: \.id) { sender in
                                    NavigationLink(value: EmailFilter.sender(email: sender.email, name: sender.name)) {
                                        AccountSenderRow(sender: sender)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                }
                .padding(.top, AppTheme.spacingMedium)
                .padding(.bottom, AppTheme.spacingLarge)
            }
        }
        .navigationTitle("Senders")
        .navigationBarTitleDisplayMode(.large)
        .primaryBackground()
        .task {
            await loadCachedEmails()
        }
        .refreshable {
            await refreshFromServer()
        }
    }
    
    // MARK: - Computed Properties
    
    private var accountEmails: [EmailListItem] {
        allEmails.filter { $0.account_email.lowercased() == accountEmail.lowercased() }
    }
    
    private var unreadSenders: [SenderInfo] {
        let unreadEmails = accountEmails.filter { !$0.is_read }
        let grouped = Dictionary(grouping: unreadEmails) { email in
            email.sender
        }
        
        return grouped.map { (email, emails) in
            let firstEmail = emails.first!
            return SenderInfo(
                id: email,
                email: email,
                name: firstEmail.sender_name ?? email,
                unreadCount: emails.count
            )
        }
        .sorted { $0.unreadCount > $1.unreadCount } // Sort by unread count descending
    }
    
    private var unreadSendersCount: Int {
        unreadSenders.count
    }
    
    private var allSenders: [AccountSenderInfo] {
        let grouped = Dictionary(grouping: accountEmails) { email in
            email.sender
        }
        
        return grouped.map { (email, emails) in
            let firstEmail = emails.first!
            let unreadCount = emails.filter { !$0.is_read }.count
            let readCount = emails.filter { $0.is_read }.count
            return AccountSenderInfo(
                id: email,
                email: email,
                name: firstEmail.sender_name ?? email,
                totalCount: emails.count,
                unreadCount: unreadCount,
                readCount: readCount
            )
        }
        .sorted { $0.totalCount > $1.totalCount } // Sort by total count descending
    }
    
    private var allSendersCount: Int {
        allSenders.count
    }
    
    // MARK: - Data Loading
    
    private func loadCachedEmails() async {
        isLoading = true
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            await MainActor.run {
                self.allEmails = snapshot.allEmails
            }
        }
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func refreshFromServer() async {
        if let snapshot = await DashboardDataManager.shared.refreshData(shouldSync: true) {
            await MainActor.run {
                self.allEmails = snapshot.allEmails
            }
        }
    }
}

// MARK: - Account Sender Info

struct AccountSenderInfo: Identifiable, Hashable {
    let id: String
    let email: String
    let name: String
    let totalCount: Int
    let unreadCount: Int
    let readCount: Int
}

// MARK: - Account Sender Row

struct AccountSenderRow: View {
    let sender: AccountSenderInfo
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar circle with initials
            Circle()
                .fill(AppTheme.accent.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(sender.name.prefix(1).uppercased())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.accent)
                )
            
            // Sender info
            VStack(alignment: .leading, spacing: 2) {
                Text(sender.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isPressed ? AppTheme.accent : AppTheme.primaryText)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    // Total emails
                    HStack(spacing: 2) {
                        Image(systemName: "envelope")
                            .font(.system(size: 10))
                        Text("\(sender.totalCount)")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(AppTheme.secondaryText)
                    
                    if sender.unreadCount > 0 {
                        // Unread count
                        HStack(spacing: 2) {
                            Image(systemName: "envelope.badge")
                                .font(.system(size: 10))
                            Text("\(sender.unreadCount)")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(AppTheme.accent)
                    }
                    
                    if sender.readCount > 0 {
                        // Read count
                        HStack(spacing: 2) {
                            Image(systemName: "envelope.open")
                                .font(.system(size: 10))
                            Text("\(sender.readCount)")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                    }
                }
            }
            
            Spacer()
            
            // Unread badge
            if sender.unreadCount > 0 {
                Text("\(sender.unreadCount)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, sender.unreadCount > 99 ? 6 : 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.secondaryText.opacity(0.5))
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, 8)
        .background(
            isPressed
                ? AppTheme.secondaryBackground.opacity(0.6)
                : Color.clear
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

#Preview {
    NavigationStack {
        AccountSendersView(accountEmail: "test@gmail.com")
    }
}

