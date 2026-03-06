//
//  SendersView.swift
//  emptyMyInbox
//
//  View for displaying and managing email senders with rich information
//

import SwiftUI

struct SendersView: View {
    @State private var allEmails: [EmailListItem] = []
    @State private var isLoading = false
    @State private var isUnreadSendersExpanded = true
    @State private var isSendersExpanded = true
    @State private var unsubscribingSenders: Set<String> = []
    @State private var sendersWithUnsubscribe: Set<String> = []  // Track which senders have unsubscribe available
    @State private var cachedSenders: [RichSenderInfo] = []  // Cached sender data
    
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
                            VStack(spacing: 12) {
                                // Show cached senders if available and no fresh data yet
                                let displaySenders = unreadSenders.isEmpty && !cachedSenders.isEmpty ? 
                                    cachedSenders.filter { $0.unreadCount30Days > 0 } : unreadSenders
                                
                                ForEach(displaySenders, id: \.id) { sender in
                                    RichSenderRow(
                                        sender: sender,
                                        isUnsubscribing: unsubscribingSenders.contains(sender.email),
                                        hasUnsubscribe: sendersWithUnsubscribe.contains(sender.email),
                                        onUnsubscribe: {
                                            await handleUnsubscribe(sender: sender)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, AppTheme.spacingMedium)
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
                            VStack(spacing: 12) {
                                // Show cached senders if available and no fresh data yet
                                let displaySenders = allSenders.isEmpty && !cachedSenders.isEmpty ? 
                                    cachedSenders : allSenders
                                
                                ForEach(displaySenders, id: \.id) { sender in
                                    RichSenderRow(
                                        sender: sender,
                                        isUnsubscribing: unsubscribingSenders.contains(sender.email),
                                        hasUnsubscribe: sendersWithUnsubscribe.contains(sender.email),
                                        onUnsubscribe: {
                                            await handleUnsubscribe(sender: sender)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, AppTheme.spacingMedium)
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
            // Only check unsubscribe if we have fresh email data
            if !allEmails.isEmpty {
                await checkUnsubscribeAvailability()
            }
        }
        .refreshable {
            await refreshFromServer()
            await checkUnsubscribeAvailability()
        }
    }
    
    // MARK: - Computed Properties
    
    private var unreadSenders: [RichSenderInfo] {
        let unreadEmails = allEmails.filter { !$0.is_read }
        return calculateRichSenderInfo(from: unreadEmails)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private var unreadSendersCount: Int {
        unreadSenders.count
    }
    
    private var allSenders: [RichSenderInfo] {
        return calculateRichSenderInfo(from: allEmails)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private var allSendersCount: Int {
        allSenders.count
    }
    
    // MARK: - Helper Methods
    
    private func calculateRichSenderInfo(from emails: [EmailListItem]) -> [RichSenderInfo] {
        let grouped = Dictionary(grouping: emails) { email in
            email.sender
        }
        
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return grouped.map { (senderEmail, senderEmails) in
            let firstEmail = senderEmails.first!
            let senderName = firstEmail.sender_name ?? senderEmail
            
            // Calculate 30-day stats
            let recentEmails = senderEmails.filter { email in
                if let date = dateFormatter.date(from: email.received_at) {
                    return date >= thirtyDaysAgo
                }
                return false
            }
            
            let totalCount30Days = recentEmails.count
            let unreadCount30Days = recentEmails.filter { !$0.is_read }.count
            let starredCount30Days = recentEmails.filter { $0.is_starred }.count
            
            // Get most recent email subjects (up to 3)
            let recentSubjects = recentEmails
                .sorted { email1, email2 in
                    let date1 = dateFormatter.date(from: email1.received_at) ?? Date.distantPast
                    let date2 = dateFormatter.date(from: email2.received_at) ?? Date.distantPast
                    return date1 > date2
                }
                .prefix(3)
                .map { $0.subject.isEmpty ? "(No Subject)" : $0.subject }
            
            return RichSenderInfo(
                id: senderEmail,
                email: senderEmail,
                name: senderName,
                totalCount30Days: totalCount30Days,
                unreadCount30Days: unreadCount30Days,
                starredCount30Days: starredCount30Days,
                recentSubjects: Array(recentSubjects)
            )
        }
    }
    
    // MARK: - Data Loading
    
    private func loadCachedEmails() async {
        isLoading = true
        
        // Get account email
        let accountEmail: String
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            accountEmail = snapshot.allEmails.first?.account_email ?? ""
            await MainActor.run {
                self.allEmails = snapshot.allEmails
            }
        } else {
            accountEmail = ""
        }
        
        // Load cached sender data
        let cachedData = await SenderCache.shared.loadSenders(accountEmail: accountEmail)
        if !cachedData.isEmpty {
            let cachedRichSenders = cachedData.map { cached in
                RichSenderInfo(
                    id: cached.senderEmail,
                    email: cached.senderEmail,
                    name: cached.senderName,
                    totalCount30Days: cached.totalCount30Days,
                    unreadCount30Days: cached.unreadCount30Days,
                    starredCount30Days: cached.starredCount30Days,
                    recentSubjects: cached.recentSubjects
                )
            }
            
            let cachedUnsubscribeSet = Set(cachedData.filter { $0.hasUnsubscribe }.map { $0.senderEmail })
            
            await MainActor.run {
                self.cachedSenders = cachedRichSenders
                self.sendersWithUnsubscribe = cachedUnsubscribeSet
            }
        }
        
        // If we have email data, calculate and save sender info (updates cache with fresh data)
        if !accountEmail.isEmpty {
            await saveSenderData(accountEmail: accountEmail)
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func refreshFromServer() async {
        if let snapshot = await DashboardDataManager.shared.refreshData(shouldSync: true) {
            let accountEmail = snapshot.allEmails.first?.account_email ?? ""
            
            await MainActor.run {
                self.allEmails = snapshot.allEmails
            }
            
            // Calculate and save sender data
            await saveSenderData(accountEmail: accountEmail)
        }
    }
    
    /// Save sender data to cache
    private func saveSenderData(accountEmail: String) async {
        let richSenders = calculateRichSenderInfo(from: allEmails)
        
        // Convert to cached format
        let cachedData = richSenders.map { sender in
            CachedSenderData(
                senderEmail: sender.email,
                senderName: sender.name,
                totalCount30Days: sender.totalCount30Days,
                unreadCount30Days: sender.unreadCount30Days,
                starredCount30Days: sender.starredCount30Days,
                recentSubjects: sender.recentSubjects,
                hasUnsubscribe: sendersWithUnsubscribe.contains(sender.email),
                lastUpdated: Date(),
                accountEmail: accountEmail
            )
        }
        
        // Save to cache
        await SenderCache.shared.saveSenders(cachedData, accountEmail: accountEmail)
    }
    
    // MARK: - Unsubscribe Availability Check
    
    private func checkUnsubscribeAvailability() async {
        let allSendersList = allSenders
        let accountEmail = allEmails.first?.account_email ?? ""
        
        var availableSenders: Set<String> = []
        
        // Check unsubscribe availability for each sender
        let unsubscribeService = UnsubscribeService.shared
        for sender in allSendersList {
            if let _ = await unsubscribeService.getUnsubscribeInfoForSender(
                senderEmail: sender.email,
                accountEmail: accountEmail
            ) {
                availableSenders.insert(sender.email)
                
                // Update cache with unsubscribe availability
                await SenderCache.shared.updateUnsubscribeAvailability(
                    senderEmail: sender.email,
                    accountEmail: accountEmail,
                    hasUnsubscribe: true
                )
            } else {
                // Update cache - no unsubscribe available
                await SenderCache.shared.updateUnsubscribeAvailability(
                    senderEmail: sender.email,
                    accountEmail: accountEmail,
                    hasUnsubscribe: false
                )
            }
        }
        
        await MainActor.run {
            sendersWithUnsubscribe = availableSenders
        }
        
        // Save updated sender data with unsubscribe info
        await saveSenderData(accountEmail: accountEmail)
    }
    
    // MARK: - Unsubscribe Handler
    
    private func handleUnsubscribe(sender: RichSenderInfo) async {
        _ = await MainActor.run {
            unsubscribingSenders.insert(sender.email)
        }
        
        // Get account email (use first email's account)
        let accountEmail = allEmails.first(where: { $0.sender == sender.email })?.account_email ?? ""
        
        // Get unsubscribe info for this sender
        let unsubscribeService = UnsubscribeService.shared
        if let method = await unsubscribeService.getUnsubscribeInfoForSender(
            senderEmail: sender.email,
            accountEmail: accountEmail
        ) {
            let result = await unsubscribeService.executeUnsubscribe(
                method: method,
                userEmail: accountEmail
            )
            
            if result.success {
                logInfo("Successfully unsubscribed from \(sender.email)", category: "Unsubscribe")
            } else {
                logError("Failed to unsubscribe from \(sender.email): \(result.message)", category: "Unsubscribe")
            }
        } else {
            logWarning("No unsubscribe method found for \(sender.email)", category: "Unsubscribe")
        }
        
        _ = await MainActor.run {
            unsubscribingSenders.remove(sender.email)
        }
    }
}

// MARK: - Rich Sender Info Model

struct RichSenderInfo: Identifiable {
    let id: String
    let email: String
    let name: String
    let totalCount30Days: Int
    let unreadCount30Days: Int
    let starredCount30Days: Int
    let recentSubjects: [String]
}

// MARK: - Rich Sender Row View

struct RichSenderRow: View {
    let sender: RichSenderInfo
    let isUnsubscribing: Bool
    let hasUnsubscribe: Bool  // Whether unsubscribe is available for this sender
    let onUnsubscribe: () async -> Void
    
    @State private var isExpanded = false
    @State private var showUnsubscribeConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main card content (always visible)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    // Avatar
                    Circle()
                        .fill(AppTheme.accent.opacity(0.2))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Text(sender.name.prefix(1).uppercased())
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(AppTheme.accent)
                        )
                    
                    // Sender info
                    VStack(alignment: .leading, spacing: 8) {
                        // Name and email
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sender.name)
                                .font(.system(size: 17, weight: .semibold))
                                .primaryText()
                            
                            Text(sender.email)
                                .font(.system(size: 13))
                                .secondaryText()
                        }
                        
                        // 30-day stats (compact)
                        HStack(spacing: 12) {
                            StatBadge(
                                icon: "envelope.fill",
                                value: "\(sender.totalCount30Days)",
                                label: "total"
                            )
                            
                            if sender.unreadCount30Days > 0 {
                                StatBadge(
                                    icon: "envelope.badge.fill",
                                    value: "\(sender.unreadCount30Days)",
                                    label: "unread",
                                    color: AppTheme.accent
                                )
                            }
                            
                            if sender.starredCount30Days > 0 {
                                StatBadge(
                                    icon: "star.fill",
                                    value: "\(sender.starredCount30Days)",
                                    label: "starred",
                                    color: AppTheme.accent
                                )
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                        .padding(.top, 4)
                }
                .padding(AppTheme.spacingMedium)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded content (actions and details)
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .background(AppTheme.secondaryText.opacity(0.2))
                        .padding(.horizontal, AppTheme.spacingMedium)
                    
                    VStack(spacing: 16) {
                        // Recent subjects section
                        if !sender.recentSubjects.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Recent Emails")
                                    .font(.system(size: 13, weight: .semibold))
                                    .secondaryText()
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(sender.recentSubjects.enumerated()), id: \.offset) { _, subject in
                                        HStack(alignment: .top, spacing: 8) {
                                            Circle()
                                                .fill(AppTheme.accent.opacity(0.3))
                                                .frame(width: 6, height: 6)
                                                .padding(.top, 6)
                                            
                                            Text(subject)
                                                .font(.system(size: 13))
                                                .secondaryText()
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // Action buttons
                        HStack(spacing: 12) {
                            // View emails button
                            NavigationLink(value: EmailFilter.sender(email: sender.email, name: sender.name)) {
                                HStack(spacing: 8) {
                                    Image(systemName: "envelope.open")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("View Emails")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(AppTheme.primaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(AppTheme.secondaryBackground)
                                .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Unsubscribe button (only show if available)
                            if hasUnsubscribe {
                                Button {
                                    showUnsubscribeConfirmation = true
                                } label: {
                                    HStack(spacing: 8) {
                                        if isUnsubscribing {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.8)
                                        } else {
                                            Image("Unsubscribe")
                                                .resizable()
                                                .renderingMode(.template)
                                                .foregroundColor(.white)
                                                .frame(width: 16, height: 16)
                                        }
                                        Text(isUnsubscribing ? "Unsubscribing..." : "Unsubscribe")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(isUnsubscribing ? Color.red.opacity(0.6) : Color.red)
                                    .cornerRadius(10)
                                }
                                .disabled(isUnsubscribing)
                            }
                        }
                    }
                    .padding(AppTheme.spacingMedium)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppTheme.secondaryBackground.opacity(0.5))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.secondaryText.opacity(0.1), lineWidth: 1)
        )
        .alert("Unsubscribe from \(sender.name)?", isPresented: $showUnsubscribeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Unsubscribe", role: .destructive) {
                Task {
                    await onUnsubscribe()
                }
            }
        } message: {
            Text("This will attempt to unsubscribe you from emails sent by \(sender.email).")
        }
    }
}

// MARK: - Stat Badge View

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = AppTheme.secondaryText
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(color.opacity(0.7))
        }
    }
}

#Preview {
    NavigationStack {
        SendersView()
    }
}

