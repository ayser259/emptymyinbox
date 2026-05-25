//
//  EmailDetailView.swift
//  emptyMyInbox
//
//  View for displaying full email details
//

import SwiftUI
import WebKit
import EmptyMyInboxShared

struct EmailDetailView: View {
    let emailId: Int
    @State private var email: EmailDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var hasUnsubscribeAvailable = false
    @State private var showUnsubscribeToast = false
    @State private var unsubscribeToastMessage = ""
    @State private var unsubscribeToastIsSuccess = false
    @State private var unsubscribeManualURL: URL? = nil
    @State private var showUnsubscribeWebView = false
    @State private var replyPresentation: ReplyComposerPresentation?
    @ObservedObject private var debugSettings = DebugSettings.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()
                
                // Unsubscribe toast overlay
                if showUnsubscribeToast {
                    VStack {
                        Spacer()
                        
                        Button {
                            if unsubscribeManualURL != nil {
                                showUnsubscribeWebView = true
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Image(systemName: unsubscribeToastIsSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundColor(unsubscribeToastIsSuccess ? .green : .orange)
                                    Text(unsubscribeToastIsSuccess ? "Unsubscribed" : "Unsubscribe Failed")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                    
                                    if unsubscribeManualURL != nil {
                                        Spacer()
                                        Image(systemName: "arrow.up.right.square")
                                            .foregroundColor(.white.opacity(0.7))
                                            .font(.system(size: 12))
                                    }
                                }
                                
                                Text(unsubscribeToastMessage)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(3)
                                
                                if unsubscribeManualURL != nil {
                                    Text("Tap to complete unsubscribe")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.top, 2)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.9))
                            .cornerRadius(12)
                            .frame(maxWidth: UIScreen.main.bounds.width - 40)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1000)
                }
                
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
                                        EmailHTMLWebView(htmlContent: bodyHtml, isDarkMode: false, onLoadComplete: nil)
                                            .frame(minHeight: max(400, geometry.size.height - 250)) // Account for header and action bar
                                    } else if !email.body_text.isEmpty {
                                        // Check if body_text is actually HTML (fallback for cached emails)
                                        if looksLikeHTML(email.body_text) {
                                            EmailHTMLWebView(htmlContent: email.body_text, isDarkMode: false, onLoadComplete: nil)
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
                        
                        EmailReadingActionBar(
                            email: self.email,
                            isDisabled: isProcessing,
                            hasUnsubscribe: $hasUnsubscribeAvailable,
                            handlers: emailReadingHandlers
                        )
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
        .sheet(isPresented: $showUnsubscribeWebView) {
            if let url = unsubscribeManualURL {
                UnsubscribeWebView(url: url)
            }
        }
        .sheet(item: $replyPresentation) { presentation in
            EmailReplyComposerView(
                email: presentation.email,
                mode: presentation.mode,
                isCatchUpContext: presentation.isCatchUpContext
            )
        }
        .task {
            await loadEmail()
        }
    }
    
    private func loadEmail() async {
        isLoading = true
        defer { isLoading = false }
        
        // First try to load from persistent cache
        if let cachedEmail = await EmailCache.shared.loadEmailDetail(emailId: emailId) {
            logInfo("EmailDetailView: Loaded email \(emailId) from persistent cache", category: "Email")
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
                logInfo("EmailDetailView: Email \(emailId) not in cache, fetching from Gmail", category: "Email")
                await fetchEmailDetail(gmailId: foundEmail.gmail_id, accountEmail: foundEmail.account_email)
                return
            }
            
            // Also check starred emails
            if let foundEmail = snapshot.starredEmails.first(where: { $0.id == emailId }) {
                logInfo("EmailDetailView: Email \(emailId) found in starred, fetching from Gmail", category: "Email")
                await fetchEmailDetail(gmailId: foundEmail.gmail_id, accountEmail: foundEmail.account_email)
                return
            }

            if let foundEmail = snapshot.sentEmails.first(where: { $0.id == emailId }) {
                logInfo("EmailDetailView: Email \(emailId) found in sent, fetching from Gmail", category: "Email")
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
            logInfo("EmailDetailView: Found email by gmailId \(gmailId) in cache", category: "Email")
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
            logInfo("EmailDetailView: Fetched and cached email \(fetchedEmail.id) from Gmail", category: "Email")
            await MainActor.run {
                self.email = fetchedEmail
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    private var emailReadingHandlers: EmailReadingActionHandlers {
        EmailReadingActionHandlers(
            onReply: { Task { await handleReply(mode: .reply) } },
            onReplyAll: { Task { await handleReply(mode: .replyAll) } },
            onStar: { Task { await handleStar() } },
            onMarkUnread: { Task { await handleKeepUnread() } },
            onMarkAsRead: { Task { await handleMarkAsRead() } },
            onUnsubscribe: { Task { await handleUnsubscribe() } }
        )
    }

    private func handleReply(mode: ReplyMode) async {
        guard let email else { return }
        await MainActor.run {
            replyPresentation = ReplyComposerPresentation(email: email, mode: mode)
        }
    }
    
    private func handleStar() async {
        guard let email = email, !isProcessing else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let newStarState = !email.is_starred
        
        await EmailActionSynchronizer.shared.enqueueStar(
            emailId: email.id,
            gmailId: email.gmail_id,
            accountEmail: email.account_email,
            shouldStar: newStarState
        )
        
        // Update local state immediately.
        await MainActor.run {
            self.email = email.updating(isStarred: newStarState)
        }
        
        if let updatedEmail = self.email {
            await EmailCache.shared.saveEmailDetail(updatedEmail)
        }
        
        await DashboardDataManager.shared.updateEmailStarred(emailId: email.id, isStarred: newStarState)
    }
    
    private func handleKeepUnread() async {
        guard let email = email, !isProcessing else { return }
        
        // If email is already unread, do nothing
        if !email.is_read {
            return
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        await EmailActionSynchronizer.shared.enqueueMarkUnread(
            emailId: email.id,
            gmailId: email.gmail_id,
            accountEmail: email.account_email
        )
        
        await MainActor.run {
            self.email = email.updating(isRead: false)
        }
        
        if let updatedEmail = self.email {
            await EmailCache.shared.saveEmailDetail(updatedEmail)
            await DashboardDataManager.shared.markEmailAsUnread(emailId: email.id, accountId: nil)
        }
    }
    
    private func handleMarkAsRead() async {
        guard let email = email, !isProcessing else { return }
        
        // If email is already read, do nothing
        if email.is_read {
            return
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        await EmailActionSynchronizer.shared.enqueueMarkRead(
            emailId: email.id,
            gmailId: email.gmail_id,
            accountEmail: email.account_email
        )
        
        // Update local state immediately.
        await MainActor.run {
            self.email = email.updating(isRead: true)
        }
        
        if let updatedEmail = self.email {
            await EmailCache.shared.saveEmailDetail(updatedEmail)
            await DashboardDataManager.shared.markEmailAsRead(emailId: email.id)
        }
    }
    
    private func handleUnsubscribe() async {
        guard let email = email, !isProcessing else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Get unsubscribe info
        let unsubscribeService = UnsubscribeService.shared
        if let method = await unsubscribeService.getUnsubscribeInfo(for: email, accountEmail: email.account_email) {
            let result = await unsubscribeService.executeUnsubscribe(
                method: method,
                userEmail: email.account_email
            )
            
            // Log detailed information
            let logMessage = """
            Unsubscribe Result:
            - Success: \(result.success)
            - Method: \(result.verificationInfo)
            - Details: \(result.details ?? "N/A")
            """
            
            if result.success {
                logInfo("✅ Successfully unsubscribed\n\(logMessage)", category: "Unsubscribe")
                
                // If manual action is required, open web view immediately
                if result.requiresManualAction, let url = result.manualActionURL {
                    await MainActor.run {
                        unsubscribeManualURL = url
                        showUnsubscribeWebView = true
                    }
                } else {
                    // Show success toast with verification info
                    await MainActor.run {
                        unsubscribeToastMessage = result.verificationInfo
                        unsubscribeToastIsSuccess = true
                        unsubscribeManualURL = result.manualActionURL
                        showUnsubscribeToast = true
                    }
                    
                    // Hide toast after 4 seconds
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    await MainActor.run {
                        withAnimation {
                            showUnsubscribeToast = false
                        }
                    }
                }
            } else {
                logError("❌ Failed to unsubscribe\n\(logMessage)", category: "Unsubscribe")
                
                // If manual action URL is available, open it immediately
                if let url = result.manualActionURL {
                    await MainActor.run {
                        unsubscribeManualURL = url
                        showUnsubscribeWebView = true
                    }
                } else {
                    // Show error toast
                    await MainActor.run {
                        unsubscribeToastMessage = result.verificationInfo
                        unsubscribeToastIsSuccess = false
                        showUnsubscribeToast = true
                    }
                    
                    // Hide toast after 3 seconds
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        withAnimation {
                            showUnsubscribeToast = false
                        }
                    }
                }
            }
        } else {
            logWarning("⚠️ No unsubscribe method found for this email", category: "Unsubscribe")
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

