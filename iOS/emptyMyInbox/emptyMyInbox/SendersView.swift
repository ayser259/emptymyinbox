//
//  SendersView.swift
//  emptyMyInbox
//
//  View for displaying and managing email senders
//

import SwiftUI

struct SendersView: View {
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
                        title: "Senders",
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
                                        SlackStyleSenderRow(sender: sender)
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshDashboard"))) { _ in
            Task {
                await loadCachedEmails()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var unreadSenders: [SenderInfo] {
        let unreadEmails = allEmails.filter { !$0.is_read }
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
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private var unreadSendersCount: Int {
        unreadSenders.count
    }
    
    private var allSenders: [SenderInfo] {
        let grouped = Dictionary(grouping: allEmails) { email in
            email.sender
        }
        
        return grouped.map { (email, emails) in
            let firstEmail = emails.first!
            let unreadCount = emails.filter { !$0.is_read }.count
            return SenderInfo(
                id: email,
                email: email,
                name: firstEmail.sender_name ?? email,
                unreadCount: unreadCount
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
            NotificationCenter.default.post(name: NSNotification.Name("RefreshDashboard"), object: nil)
        }
    }
}

#Preview {
    NavigationStack {
        SendersView()
    }
}

