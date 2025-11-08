//
//  EmailCardView.swift
//  emptyMyInbox
//
//  Reusable email card component for catch up view
//

import SwiftUI
import WebKit

struct EmailCardView: View {
    let email: EmailDetail
    let geometry: GeometryProxy
    
    var body: some View {
        VStack(spacing: 0) {
            // Fixed header section (sender, subject, to) - inside grey box
            VStack(alignment: .leading, spacing: 0) {
                // Sender name
                Text(email.sender_name ?? email.sender)
                    .font(.system(size: 18, weight: .semibold))
                    .primaryText()
                    .padding(.bottom, AppTheme.spacingMedium)
                
                Divider()
                    .background(AppTheme.secondaryText.opacity(0.3))
                    .padding(.bottom, AppTheme.spacingMedium)
                
                // Subject
                Text(email.subject.isEmpty ? "(No Subject)" : email.subject)
                    .font(.system(size: 16, weight: .medium))
                    .primaryText()
                    .padding(.bottom, AppTheme.spacingMedium)
                
                Divider()
                    .background(AppTheme.secondaryText.opacity(0.3))
                    .padding(.bottom, AppTheme.spacingMedium)
                
                // To field
                if let to = email.recipients_to, !to.isEmpty {
                    HStack {
                        Text("To:")
                            .font(.system(size: 13))
                            .secondaryText()
                        Text(to)
                            .font(.system(size: 13))
                            .primaryText()
                    }
                    .padding(.bottom, AppTheme.spacingMedium)
                    
                    Divider()
                        .background(AppTheme.secondaryText.opacity(0.3))
                        .padding(.bottom, AppTheme.spacingMedium)
                }
                
                // Date
                HStack {
                    Text("Date:")
                        .font(.system(size: 13))
                        .secondaryText()
                    Text(formatDate(email.received_at))
                        .font(.system(size: 13))
                        .primaryText()
                }
                .padding(.bottom, AppTheme.spacingMedium)
                
                Divider()
                    .background(AppTheme.secondaryText.opacity(0.3))
            }
            .padding(AppTheme.spacingMedium)
            .background(Color(hex: "#252525"))
            
            // Scrollable email body section - takes remaining space
            GeometryReader { scrollGeometry in
                YellowScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let bodyHtml = email.body_html, !bodyHtml.isEmpty {
                            // Render HTML content
                            HTMLWebView(htmlContent: bodyHtml, isDarkMode: true)
                                .frame(maxWidth: .infinity, minHeight: scrollGeometry.size.height, alignment: .leading)
                        } else if !email.body_text.isEmpty {
                            Text(email.body_text)
                                .font(.system(size: 15))
                                .primaryText()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(email.snippet)
                                .font(.system(size: 15))
                                .secondaryText()
                                .italic()
                        }
                    }
                    .padding(AppTheme.spacingMedium)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Color(hex: "#252525"))
        }
        .background(Color(hex: "#252525"))
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(AppTheme.accent, lineWidth: 2)
        )
        .padding(.horizontal, AppTheme.spacingMedium)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: geometry.size.height - 150) // Account for top bar and bottom buttons
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: date)
        }
        return dateString
    }
}

