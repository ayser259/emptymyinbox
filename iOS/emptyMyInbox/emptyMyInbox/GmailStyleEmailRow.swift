//
//  GmailStyleEmailRow.swift
//  emptyMyInbox
//
//  Gmail-style email row component
//

import SwiftUI

struct GmailStyleEmailRow: View {
    let email: EmailListItem
    @State private var isStarred: Bool
    @State private var isUpdating = false
    
    init(email: EmailListItem) {
        self.email = email
        _isStarred = State(initialValue: email.is_starred)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacingMedium) {
            // Star button
            Button {
                Task {
                    await toggleStar()
                }
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundColor(isStarred ? AppTheme.accent : AppTheme.secondaryText.opacity(0.5))
                    .font(.system(size: 16))
                    .frame(width: 24)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isUpdating)
            
            // Email content
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: AppTheme.spacingSmall) {
                    // Sender name
                    Text(email.sender_name ?? email.sender)
                        .font(.system(size: 15, weight: email.is_read ? .regular : .semibold))
                        .foregroundColor(email.is_read ? AppTheme.secondaryText : AppTheme.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Date
                    Text(formatDate(email.received_at))
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                }
                
                // Subject
                Text(email.subject.isEmpty ? "(No Subject)" : email.subject)
                    .font(.system(size: 15, weight: email.is_read ? .regular : .semibold))
                    .foregroundColor(email.is_read ? AppTheme.secondaryText : AppTheme.primaryText)
                    .lineLimit(2)
                
                // Snippet
                if !email.snippet.isEmpty {
                    Text(email.snippet)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.secondaryText.opacity(0.8))
                        .lineLimit(2)
                }
            }
            
            // Unread indicator
            if !email.is_read {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 8, height: 8)
                    .padding(.leading, 4)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, AppTheme.spacingSmall)
        .background(AppTheme.secondaryBackground.opacity(0.3))
        .cornerRadius(AppTheme.cornerRadiusSmall)
        .contentShape(Rectangle())
    }
    
    private func toggleStar() async {
        isUpdating = true
        defer { isUpdating = false }
        
        let gmailService = GmailAPIService.shared
        guard let account = gmailService.getAccount(byEmail: email.account_email) else {
            logError("Account not found for email", category: "Email")
            return
        }
        
        do {
            if isStarred {
                try await gmailService.unstarMessage(for: account, messageId: email.gmail_id)
                await EmailActionSynchronizer.shared.enqueueStar(emailId: email.id, gmailId: email.gmail_id, accountEmail: email.account_email, shouldStar: false)
            } else {
                try await gmailService.starMessage(for: account, messageId: email.gmail_id)
                await EmailActionSynchronizer.shared.enqueueStar(emailId: email.id, gmailId: email.gmail_id, accountEmail: email.account_email, shouldStar: true)
            }
            
            await MainActor.run {
                self.isStarred = !self.isStarred
            }
        } catch {
            logError("Error toggling star: \(error)", category: "Email")
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        // Parse ISO date string and format it
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let calendar = Calendar.current
            let now = Date()
            
            if calendar.isDateInToday(date) {
                // Show time for today
                let timeFormatter = DateFormatter()
                timeFormatter.timeStyle = .short
                return timeFormatter.string(from: date)
            } else if calendar.isDateInYesterday(date) {
                return "Yesterday"
            } else if calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) ?? false {
                // Show day name for this week
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "EEE"
                return dayFormatter.string(from: date)
            } else {
                // Show date
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d"
                return dateFormatter.string(from: date)
            }
        }
        
        return ""
    }
}

#Preview {
    GmailStyleEmailRow(email: EmailListItem(
        id: 1,
        gmail_id: "123",
        subject: "Test Email",
        sender: "test@example.com",
        sender_name: "Test User",
        snippet: "This is a test email snippet",
        is_read: false,
        is_starred: false,
        labels: [],
        received_at: "2024-01-01T12:00:00Z",
        account_email: "user@example.com",
        marked_read_at: nil
    ))
    .padding()
    .primaryBackground()
}

