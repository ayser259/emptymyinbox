//
//  AccountSummaryCard.swift
//  emptyMyInbox
//
//  Account summary card component for dashboard
//

import SwiftUI
import EmptyMyInboxShared

struct AccountSummaryCard: View {
    let account: EmailAccount
    let unreadCount: Int
    let starredCount: Int
    let totalEmailCount: Int
    let unreadSenderCount: Int
    let lastRefreshTime: Date?
    let healthStatus: AccountHealthStatus?
    let onRefresh: () async -> Void
    var onReconnect: (() async -> Void)? = nil
    
    @State private var isRefreshing = false
    @State private var isReconnecting = false
    
    // Gradient colors for card
    private let cardGradient = LinearGradient(
        colors: [
            Color(hex: "#1a1a1a"),
            Color(hex: "#0d0d0d")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top section: Email + Refresh button
            HStack(alignment: .center) {
                // Account info
                VStack(alignment: .leading, spacing: 4) {
                    // Email address with subtle shadow for depth
                    Text(account.email)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .primaryText()
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    
                    // Last sync time
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                        
                        if let lastRefresh = lastRefreshTime {
                            Text(formatLastRefreshTime(lastRefresh))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                        } else if account.email_count == 0 {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .tint(AppTheme.accent)
                                Text("Syncing...")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.accent)
                            }
                        } else {
                            Text("Never synced")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                        }
                    }
                }
                
                Spacer()
                
                // Refresh button - pill style
                Button {
                    Task {
                        await MainActor.run { isRefreshing = true }
                        await onRefresh()
                        await MainActor.run { isRefreshing = false }
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppTheme.accent.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                            )
                        
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(AppTheme.accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.accent)
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isRefreshing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
            
            // Health status bar - glass morphism style
            HStack(spacing: 8) {
                Image(systemName: healthIconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(healthColor)
                
                Text(healthText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(healthColor)
                
                Spacer()
                
                // Reconnect button when not healthy
                if !isHealthy, onReconnect != nil {
                    Button {
                        Task {
                            await MainActor.run { isReconnecting = true }
                            await onReconnect?()
                            await MainActor.run { isReconnecting = false }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isReconnecting {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(healthColor)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Reconnect")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .foregroundColor(healthColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(healthColor.opacity(0.15))
                                .overlay(
                                    Capsule()
                                        .stroke(healthColor.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isReconnecting)
                } else {
                    // Animated health indicator
                    Circle()
                        .fill(healthColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: healthColor.opacity(0.6), radius: 4, x: 0, y: 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(healthColor.opacity(0.08))
                    .overlay(
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [healthColor.opacity(0.15), healthColor.opacity(0.05)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            )
            
            // Error/Warning message if applicable
            if let status = healthStatus {
                switch status {
                case .error(let message):
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                case .warning(let message):
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                default:
                    EmptyView()
                }
            }
            
            // Short summary (counts only) — full lists open via “View more”
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(accountInboxSummaryLine)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.primaryText.opacity(0.95))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if unreadSenderCount > 0 {
                        Text("\(unreadSenderCount) senders with unread")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                NavigationLink(value: EmailFilter.accountAll(accountEmail: account.email)) {
                    HStack(spacing: 4) {
                        Text("View more")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Catch up button - subtle dark style that blends in
            if unreadCount > 0 {
                NavigationLink(value: "catch_up_\(account.id)") {
                    HStack(spacing: 8) {
                        // Yellow catchup icon for accent
                        Image("Catchup")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                        
                        Text("Catch Up")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        
                        Spacer()
                        
                        // Count badge
                        Text("\(unreadCount)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(AppTheme.accent.opacity(0.15))
                            )
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                    }
                    .foregroundColor(AppTheme.primaryText.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardGradient)
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04),
                            healthBorderGlow
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var accountInboxSummaryLine: String {
        [
            "\(unreadCount) unread",
            "\(starredCount) starred",
            "\(totalEmailCount) total"
        ].joined(separator: " · ")
    }

    // MARK: - Health Properties
    
    private var healthIconName: String {
        guard let status = healthStatus else { return "circle.dotted" }
        switch status {
        case .healthy: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.shield.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var healthColor: Color {
        guard let status = healthStatus else { return AppTheme.secondaryText }
        switch status {
        case .healthy: return Color(hex: "#4ade80") // Brighter green
        case .warning: return .orange
        case .error: return .red
        case .unknown: return AppTheme.secondaryText
        }
    }
    
    private var healthText: String {
        guard let status = healthStatus else { return "Checking..." }
        switch status {
        case .healthy: return "Connected"
        case .warning: return "Warning"
        case .error: return "Error"
        case .unknown: return "Unknown"
        }
    }
    
    private var healthBorderGlow: Color {
        guard let status = healthStatus else { return Color.clear }
        switch status {
        case .healthy: return Color.clear
        case .warning: return Color.orange.opacity(0.3)
        case .error: return Color.red.opacity(0.3)
        case .unknown: return Color.clear
        }
    }
    
    private var isHealthy: Bool {
        guard let status = healthStatus else { return true }
        if case .healthy = status { return true }
        return false
    }
    
    private func formatLastRefreshTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if let seconds = calendar.dateComponents([.second], from: date, to: now).second, seconds < 60 {
            return "just now"
        }
        
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return timeFormatter.string(from: date)
        }
        
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        return dateFormatter.string(from: date)
    }
}
