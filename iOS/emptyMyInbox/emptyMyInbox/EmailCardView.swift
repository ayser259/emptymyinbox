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
    var isActive: Bool = true // Whether this is the top card with normal text
    var onLoadComplete: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Fixed header section (sender, date, subject) - inside grey box
            VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                // Row 1: Sender (left) and Date (right)
                HStack {
                    Text(email.sender_name ?? email.sender)
                        .font(.system(size: 18, weight: .semibold))
                        .primaryText()
                    
                    Spacer()
                    
                    Text(formatCompactDate(email.received_at))
                        .font(.system(size: 14, weight: .medium))
                        .secondaryText()
                }
                
                // Row 2: Subject (full width)
                HStack {
                    Text(email.subject.isEmpty ? "(No Subject)" : email.subject)
                        .font(.system(size: 16, weight: .medium))
                        .primaryText()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
            }
            .padding(AppTheme.spacingMedium)
            .background(Color(hex: "#252525"))
            
            // Scrollable email body section - takes remaining space
            GeometryReader { scrollGeometry in
                YellowScrollView {
                    VStack(alignment: .center, spacing: 0) {
                        if let bodyHtml = email.body_html, !bodyHtml.isEmpty {
                            // Render HTML content - use light mode for better readability
                            HTMLWebView(htmlContent: bodyHtml, isDarkMode: false, onLoadComplete: onLoadComplete)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: scrollGeometry.size.height)
                        } else if !email.body_text.isEmpty {
                            // For text emails, mark as loaded immediately
                            Text(email.body_text)
                                .font(.system(size: 15))
                                .primaryText()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .onAppear {
                                    onLoadComplete?()
                                }
                        } else {
                            Text(email.snippet)
                                .font(.system(size: 15))
                                .secondaryText()
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .onAppear {
                                    onLoadComplete?()
                                }
                        }
                    }
                    .padding(.top, 0)
                    .padding(.horizontal, AppTheme.spacingMedium)
                    .padding(.bottom, AppTheme.spacingMedium)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Color(hex: "#252525"))
        }
        .background(Color(hex: "#252525"))
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            // Grey overlay for inactive cards to match background and hide text (inside border)
            Group {
                if !isActive {
                    Color(hex: "#252525").opacity(0.99)
                        .cornerRadius(AppTheme.cornerRadiusMedium)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(AppTheme.accent, lineWidth: 2)
        )
        .padding(.horizontal, AppTheme.spacingMedium)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: geometry.size.height * 0.85) // Leave space for buttons and card peeking
    }
    
    private func formatCompactDate(_ dateString: String) -> String {
        // Try ISO8601 format first (with fractional seconds)
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var date = formatterWithFractional.date(from: dateString)
        
        // Fallback to ISO8601 without fractional seconds
        if date == nil {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: dateString)
        }
        
        // Fallback to standard date formatter
        if date == nil {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            date = dateFormatter.date(from: dateString)
        }
        
        if let date = date {
            let calendar = Calendar.current
            
            if calendar.isDateInToday(date) {
                let timeFormatter = DateFormatter()
                timeFormatter.locale = Locale(identifier: "en_US_POSIX")
                timeFormatter.dateFormat = "h:mm a"
                return timeFormatter.string(from: date)
            } else {
                let day = calendar.component(.day, from: date)
                let year = calendar.component(.year, from: date)
                
                // Get abbreviated month name with English locale
                let monthFormatter = DateFormatter()
                monthFormatter.locale = Locale(identifier: "en_US_POSIX")
                monthFormatter.dateFormat = "MMM"
                let monthString = monthFormatter.string(from: date)
                
                // Get two-digit year with apostrophe
                let yearString = "'\(String(year).suffix(2))"
                
                return "\(day) \(monthString) \(yearString)"
            }
        }
        
        // If all parsing fails, return original string
        return dateString
    }
}

