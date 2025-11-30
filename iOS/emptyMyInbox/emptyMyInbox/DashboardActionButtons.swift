//
//  DashboardActionButtons.swift
//  emptyMyInbox
//
//  Action buttons for the dashboard
//

import SwiftUI

struct ActionButton: View {
    let title: String
    let count: Int
    let icon: String
    
    var body: some View {
        VStack(spacing: AppTheme.spacingSmall) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(AppTheme.accent)
            
            Text(title)
                .font(AppTheme.subheadline)
                .primaryText()
            
            Text("\(count)")
                .font(AppTheme.caption)
                .secondaryText()
        }
        .frame(width: 100, height: 100)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Catch Up Action Button (Featured with yellow border)

struct CatchUpActionButton: View {
    let title: String
    let count: Int
    
    var body: some View {
        VStack(spacing: AppTheme.spacingSmall) {
            // Use Caughtup image when count is 0, otherwise use Catchup
            if count == 0 {
                Image("Caughtup")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image("Catchup")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            }
            
            // Show "Inbox 0!" when count is 0, otherwise show title
            Text(count == 0 ? "Inbox 0!" : title)
                .font(.system(size: 14, weight: .semibold))
                .primaryText()
            
            // Show count only if not zero
            if count > 0 {
                Text("\(count)")
                    .font(AppTheme.caption)
                    .secondaryText()
            }
        }
        .frame(width: 100, height: 100)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(AppTheme.accent, lineWidth: 2)
        )
        .shadow(color: AppTheme.accent.opacity(0.2), radius: 6, x: 0, y: 2)
    }
}
