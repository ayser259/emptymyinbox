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
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let email = email {
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
                                        Text(email.body_text)
                                            .font(.system(size: 15))
                                            .primaryText()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .multilineTextAlignment(.leading)
                                            .padding(AppTheme.spacingMedium)
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
        
        do {
            let fetchedEmail = try await APIService.shared.getEmailDetails(emailId: emailId)
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
        
        do {
            let updatedEmail: EmailDetail
            if email.is_starred {
                updatedEmail = try await APIService.shared.unstarEmail(emailId: email.id)
            } else {
                updatedEmail = try await APIService.shared.starEmail(emailId: email.id)
            }
            
            await MainActor.run {
                self.email = updatedEmail
            }
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
        
        do {
            let updatedEmail = try await APIService.shared.markEmailAsRead(emailId: email.id)
            await MainActor.run {
                self.email = updatedEmail
            }
        } catch {
            print("Error marking email as read: \(error)")
        }
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

