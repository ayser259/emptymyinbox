//
//  EmailDetailView.swift
//  emptyMyInbox
//
//  View for displaying full email details
//

import SwiftUI
import WebKit

struct EmailDetailView: View {
    let emailId: Int
    @State private var email: EmailDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @ObservedObject private var debugSettings = DebugSettings.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let email = email {
                    ZStack {
                    VStack(spacing: 0) {
                        // Email content - takes remaining space
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                // Header section
                                VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                                    // Sender and date row
                                    HStack {
                                        Text(email.sender_name ?? email.sender)
                                            .font(.system(size: 18, weight: .semibold))
                                            .primaryText()
                                        
                                        Spacer()
                                        
                                        Text(formatCompactDate(email.received_at))
                                            .font(.system(size: 14, weight: .medium))
                                            .secondaryText()
                                    }
                                    
                                    // Subject row
                                    Text(email.subject.isEmpty ? "(No Subject)" : email.subject)
                                        .font(.system(size: 16, weight: .medium))
                                        .primaryText()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .multilineTextAlignment(.leading)
                                    
                                    // Recipients (if available)
                                    if let recipientsTo = email.recipients_to, !recipientsTo.isEmpty {
                                        Text("To: \(recipientsTo)")
                                            .font(.system(size: 14))
                                            .secondaryText()
                                    }
                                }
                                .padding(AppTheme.spacingMedium)
                                .background(Color(hex: "#252525"))
                                
                                // Email body section
                                VStack(alignment: .leading, spacing: 0) {
                                    if let bodyHtml = email.body_html, !bodyHtml.isEmpty {
                                        HTMLWebView(htmlContent: bodyHtml, isDarkMode: false, onLoadComplete: nil)
                                            .frame(minHeight: max(400, geometry.size.height - 250)) // Account for header and action bar
                                    } else if !email.body_text.isEmpty {
                                        // Check if body_text is actually HTML (fallback for cached emails)
                                        if looksLikeHTML(email.body_text) {
                                            HTMLWebView(htmlContent: email.body_text, isDarkMode: false, onLoadComplete: nil)
                                                .frame(minHeight: max(400, geometry.size.height - 250))
                                        } else {
                                            Text(email.body_text)
                                                .font(.system(size: 15))
                                                .primaryText()
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .multilineTextAlignment(.leading)
                                                .padding(AppTheme.spacingMedium)
                                        }
                                    } else {
                                        Text(email.snippet)
                                            .font(.system(size: 15))
                                            .secondaryText()
                                            .italic()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .multilineTextAlignment(.leading)
                                            .padding(AppTheme.spacingMedium)
                                    }
                                }
                                .background(Color(hex: "#252525"))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Bottom action bar with scrollable buttons
                        VStack(spacing: 0) {
                            Divider()
                                .background(AppTheme.secondaryText.opacity(0.2))
                            
                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        // Reply button (peeking from left, scrollable)
                                        Button {
                                            Task {
                                                await handleReply()
                                            }
                                        } label: {
                                            VStack(spacing: 6) {
                                                Image(systemName: "arrowshape.turn.up.left")
                                                    .font(.system(size: 20, weight: .medium))
                                                    .foregroundColor(AppTheme.accent)
                                                
                                                Text("Reply")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(AppTheme.accent)
                                            }
                                            .frame(width: 80, height: 51.2)
                                            .background(Color.black)
                                            .cornerRadius(12)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                        }
                                        .id("reply")
                                        .disabled(isProcessing)
                                        
                                        // Star button
                                        Button {
                                            Task {
                                                await handleStar()
                                            }
                                        } label: {
                                            VStack(spacing: 6) {
                                                Image(systemName: email.is_starred ? "star.fill" : "star")
                                                    .font(.system(size: 20, weight: .medium))
                                                    .foregroundColor(AppTheme.accent)
                                                
                                                Text("Star")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(AppTheme.accent)
                                            }
                                            .frame(width: 80, height: 51.2)
                                            .background(Color.black)
                                            .cornerRadius(12)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(
                                                        email.is_starred ? AppTheme.accent : Color.white.opacity(0.2),
                                                        lineWidth: email.is_starred ? 2 : 1
                                                    )
                                            )
                                        }
                                        .id("star")
                                        .disabled(isProcessing)
                                        
                                        // Keep Unread button
                                        Button {
                                            Task {
                                                await handleKeepUnread()
                                            }
                                        } label: {
                                            Text("Keep Unread")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(AppTheme.primaryText)
                                                .frame(width: 150, height: 51.2)
                                                .background(AppTheme.secondaryBackground)
                                                .cornerRadius(12)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(AppTheme.accent, lineWidth: 2)
                                                )
                                        }
                                        .id("keepUnread")
                                        .disabled(isProcessing)
                                        
                                        // Mark as Read button
                                        Button {
                                            Task {
                                                await handleMarkAsRead()
                                            }
                                        } label: {
                                            Text("Mark as Read")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.black)
                                                .frame(width: 150, height: 51.2)
                                                .background(AppTheme.accent)
                                                .cornerRadius(12)
                                        }
                                        .id("markAsRead")
                                        .disabled(isProcessing)
                                    }
                                    .padding(.leading, AppTheme.spacingLarge - 60) // Start with Reply partially visible (peeking)
                                    .padding(.trailing, AppTheme.spacingLarge)
                                    .padding(.vertical, 12)
                                }
                                .onAppear {
                                    // Scroll to show Star button initially, with Reply peeking from left
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation {
                                            proxy.scrollTo("star", anchor: .leading)
                                        }
                                    }
                                }
                            }
                        }
                        .background(AppTheme.primaryBackground)
                    }
                    
                    // Debug copy button overlay
                    if debugSettings.isDebugModeEnabled {
                        VStack {
                            HStack {
                                Spacer()
                                DebugCopyButton(content: email.debugCopyContent)
                                    .padding(.trailing, 16)
                            }
                            Spacer()
                        }
                        .padding(.top, 16)
                    }
                    } // End ZStack for email content
                } else {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.secondaryText)
                            .padding()
                        
                        Text("Failed to load email")
                            .font(AppTheme.title3)
                            .primaryText()
                        
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(AppTheme.body)
                                .secondaryText()
                                .padding(.top, AppTheme.spacingSmall)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Email")
        .navigationBarTitleDisplayMode(.inline)
        .customBackButton()
        .primaryBackground()
        .task {
            await loadEmail()
        }
    }
    
    private func loadEmail() async {
        isLoading = true
        defer { isLoading = false }
        
        // First try to load from persistent cache
        if let cachedEmail = await EmailCache.shared.loadEmailDetail(emailId: emailId) {
            print("📧 EmailDetailView: Loaded email \(emailId) from persistent cache")
            await MainActor.run {
                self.email = cachedEmail
                self.isLoading = false
            }
            return
        }
        
        // If not in cache, try to find in dashboard snapshot to get gmail_id and account
        if let snapshot = await DashboardDataManager.shared.loadCachedSnapshot() {
            // Find email in allEmails by ID
            if let foundEmail = snapshot.allEmails.first(where: { $0.id == emailId }) {
                // We have the list item, but need the detail - fetch it
                print("📧 EmailDetailView: Email \(emailId) not in cache, fetching from Gmail")
                await fetchEmailDetail(gmailId: foundEmail.gmail_id, accountEmail: foundEmail.account_email)
                return
            }
            
            // Also check starred emails
            if let foundEmail = snapshot.starredEmails.first(where: { $0.id == emailId }) {
                print("📧 EmailDetailView: Email \(emailId) found in starred, fetching from Gmail")
                await fetchEmailDetail(gmailId: foundEmail.gmail_id, accountEmail: foundEmail.account_email)
                return
            }
        }
        
        await MainActor.run {
            self.errorMessage = "Email not found"
        }
    }
    
    private func fetchEmailDetail(gmailId: String, accountEmail: String) async {
        // First check if already cached by Gmail ID
        if let cachedEmail = await EmailCache.shared.loadEmailDetail(gmailId: gmailId) {
            print("📧 EmailDetailView: Found email by gmailId \(gmailId) in cache")
            await MainActor.run {
                self.email = cachedEmail
            }
            return
        }
        
        let gmailService = GmailAPIService.shared
        guard let account = gmailService.getAccount(byEmail: accountEmail) else {
            await MainActor.run {
                self.errorMessage = "Account not found"
            }
            return
        }
        
        do {
            let fetchedEmail = try await gmailService.getEmailDetail(for: account, gmailId: gmailId)
            // Save to persistent cache
            await EmailCache.shared.saveEmailDetail(fetchedEmail)
            print("📧 EmailDetailView: Fetched and cached email \(fetchedEmail.id) from Gmail")
            await MainActor.run {
                self.email = fetchedEmail
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func handleReply() async {
        // TODO: Implement reply functionality
        print("Reply to email \(emailId)")
    }
    
    private func handleStar() async {
        guard let email = email, !isProcessing else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let gmailService = GmailAPIService.shared
        guard let account = gmailService.getAccount(byEmail: email.account_email) else {
            print("Account not found for email")
            return
        }
        
        let newStarState = !email.is_starred
        
        do {
            if email.is_starred {
                try await gmailService.unstarMessage(for: account, messageId: email.gmail_id)
                await EmailActionSynchronizer.shared.enqueueStar(emailId: email.id, gmailId: email.gmail_id, accountEmail: email.account_email, shouldStar: false)
            } else {
                try await gmailService.starMessage(for: account, messageId: email.gmail_id)
                await EmailActionSynchronizer.shared.enqueueStar(emailId: email.id, gmailId: email.gmail_id, accountEmail: email.account_email, shouldStar: true)
            }
            
            // Update local state
            await MainActor.run {
                self.email = email.updating(isStarred: newStarState)
            }
            
            // Update email detail cache
            if let updatedEmail = self.email {
                await EmailCache.shared.saveEmailDetail(updatedEmail)
            }
            
            // Update dashboard cache with starred status change
            await DashboardDataManager.shared.updateEmailStarred(emailId: email.id, isStarred: newStarState)
        } catch {
            print("Error toggling star: \(error)")
        }
    }
    
    private func handleKeepUnread() async {
        guard let email = email, !isProcessing else { return }
        
        // If email is already unread, do nothing
        if !email.is_read {
            return
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // TODO: Implement "keep unread" - this might require marking as unread
        // For now, we'll just reload the email to ensure state is current
        await loadEmail()
    }
    
    private func handleMarkAsRead() async {
        guard let email = email, !isProcessing else { return }
        
        // If email is already read, do nothing
        if email.is_read {
            return
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let gmailService = GmailAPIService.shared
        guard let account = gmailService.getAccount(byEmail: email.account_email) else {
            print("Account not found for email")
            return
        }
        
        do {
            try await gmailService.markAsRead(for: account, messageId: email.gmail_id)
            await EmailActionSynchronizer.shared.enqueueMarkRead(emailId: email.id, gmailId: email.gmail_id, accountEmail: email.account_email)
            
            // Update local state
            await MainActor.run {
                self.email = email.updating(isRead: true)
            }
            
            // Update cache and dashboard
            if let updatedEmail = self.email {
                await EmailCache.shared.saveEmailDetail(updatedEmail)
                await DashboardDataManager.shared.markEmailAsRead(emailId: email.id)
            }
        } catch {
            print("Error marking email as read: \(error)")
        }
    }
    
    /// Detect if text content is actually HTML that should be rendered
    private func looksLikeHTML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Check for common HTML document indicators
        if trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html") {
            return true
        }
        // Check for HTML tags that indicate structured content
        if trimmed.hasPrefix("<") && (
            trimmed.contains("<head") ||
            trimmed.contains("<body") ||
            trimmed.contains("<div") ||
            trimmed.contains("<table") ||
            trimmed.contains("<style") ||
            trimmed.contains("<meta")
        ) {
            return true
        }
        return false
    }
    
    private func formatCompactDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) else {
            return ""
        }
        
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Yesterday at \(timeFormatter.string(from: date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: date)
        }
    }
}

#Preview {
    NavigationView {
        EmailDetailView(emailId: 1)
    }
}

