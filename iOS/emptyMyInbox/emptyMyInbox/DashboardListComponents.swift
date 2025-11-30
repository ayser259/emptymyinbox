//
//  DashboardListComponents.swift
//  emptyMyInbox
//
//  Reusable list components for dashboard-related views
//

import SwiftUI

struct CollapsibleSection<Content: View>: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
            // Section header with chevron
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                            .frame(width: 16)
                        
                        Text(title)
                            .font(AppTheme.caption)
                            .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                            .fontWeight(.semibold)
                            .tracking(0.5)
                        
                        Spacer()
                        
                        // Count badge
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, count > 99 ? 5 : 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent)
                                .clipShape(Capsule())
                                .frame(minWidth: 18, minHeight: 18)
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingMedium)
                    .padding(.vertical, AppTheme.spacingSmall)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Content (expanded)
            if isExpanded {
                content
            }
        }
    }
}

struct SenderInfo: Identifiable, Hashable {
    let id: String
    let email: String
    let name: String
    let unreadCount: Int
}

struct SlackStyleSenderRow: View {
    let sender: SenderInfo
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Circle icon prefix (Slack-style for users)
            Image(systemName: "person.circle.fill")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                .frame(width: 16, alignment: .leading)
            
            // Sender name
            Text(sender.name)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(isPressed ? AppTheme.accent : AppTheme.secondaryText)
                .lineLimit(1)
            
            Spacer()
            
            // Unread count badge (Slack-style rounded badge)
            if sender.unreadCount > 0 {
                Text("\(sender.unreadCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, sender.unreadCount > 99 ? 5 : 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
                    .frame(minWidth: 18, minHeight: 18)
            }
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, 4)
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

// MARK: - Legacy Components (for compatibility)

struct LabelRow: View {
    let label: Label
    
    var body: some View {
        HStack {
            Image(systemName: "tag.fill")
                .foregroundColor(AppTheme.accent)
                .font(.system(size: 16))
            
            Text(label.name)
                .font(AppTheme.body)
                .primaryText()
            
            Spacer()
            
            if label.unread_count > 0 {
                Text("\(label.unread_count)")
                    .font(AppTheme.subheadline)
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, AppTheme.spacingUnit)
                    .padding(.vertical, 4)
                    .background(AppTheme.accentMuted)
                    .cornerRadius(AppTheme.cornerRadiusSmall)
            }
        }
        .padding(AppTheme.spacingMedium)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct SlackStyleLabelRow: View {
    let label: Label
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Hash symbol prefix (Slack-style)
            Text("#")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                .frame(width: 16, alignment: .leading)
            
            // Label name
            Text(label.name)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(isPressed ? AppTheme.accent : AppTheme.secondaryText)
                .lineLimit(1)
            
            Spacer()
            
            // Unread count badge (Slack-style rounded badge)
            if label.unread_count > 0 {
                Text("\(label.unread_count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, label.unread_count > 99 ? 5 : 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
                    .frame(minWidth: 18, minHeight: 18)
            }
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, 4)
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
