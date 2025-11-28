//
//  RefreshProgressModal.swift
//  emptyMyInbox
//
//  Modal view showing detailed refresh progress
//

import SwiftUI

struct RefreshProgressModal: View {
    @ObservedObject var progressTracker: RefreshProgressTracker
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Overall progress bar
                        VStack(spacing: AppTheme.spacingMedium) {
                            HStack {
                                Text("Overall Progress")
                                    .font(AppTheme.headline)
                                    .primaryText()
                                Spacer()
                                Text("\(Int(progressTracker.overallProgress * 100))%")
                                    .font(AppTheme.headline)
                                    .foregroundColor(AppTheme.accent)
                            }
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(AppTheme.secondaryBackground)
                                        .frame(height: 8)
                                    
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [AppTheme.accent, AppTheme.accent.opacity(0.7)]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geometry.size.width * progressTracker.overallProgress, height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                        .padding(AppTheme.spacingLarge)
                        .background(AppTheme.secondaryBackground)
                        
                        // Progress items list
                        VStack(spacing: 0) {
                            ForEach(progressTracker.items) { item in
                                ProgressItemRow(item: item)
                                    .padding(.horizontal, AppTheme.spacingMedium)
                                
                                if item.id != progressTracker.items.last?.id {
                                    Divider()
                                        .background(AppTheme.secondaryText.opacity(0.2))
                                        .padding(.leading, AppTheme.spacingLarge)
                                }
                            }
                        }
                        .padding(.vertical, AppTheme.spacingSmall)
                    }
                }
            }
            .navigationTitle("Refresh Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .textButton()
                }
            }
        }
    }
}

struct ProgressItemRow: View {
    let item: RefreshProgressItem
    
    var body: some View {
        HStack(spacing: AppTheme.spacingMedium) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusBackgroundColor)
                    .frame(width: 32, height: 32)
                
                statusIcon
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(statusIconColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.stage.rawValue)
                    .font(AppTheme.subheadline)
                    .primaryText()
                
                if let detail = item.detail {
                    Text(detail)
                        .font(AppTheme.caption)
                        .secondaryText()
                }
                
                if let accountEmail = item.accountEmail {
                    Text(accountEmail)
                        .font(AppTheme.caption)
                        .foregroundColor(AppTheme.accent.opacity(0.8))
                }
                
                // Progress count if available
                if let current = item.currentCount {
                    if let total = item.totalCount {
                        Text("\(current) of \(total)")
                            .font(AppTheme.caption)
                            .foregroundColor(AppTheme.accent)
                    } else {
                        Text("\(current)")
                            .font(AppTheme.caption)
                            .foregroundColor(AppTheme.accent)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, AppTheme.spacingSmall)
        .contentShape(Rectangle())
    }
    
    private var statusIcon: some View {
        Group {
            switch item.status {
            case .pending:
                Image(systemName: "circle")
            case .inProgress:
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(statusIconColor)
            case .completed:
                Image(systemName: "checkmark")
            case .failed:
                Image(systemName: "xmark")
            }
        }
    }
    
    private var statusBackgroundColor: Color {
        switch item.status {
        case .pending:
            return AppTheme.secondaryBackground
        case .inProgress:
            return AppTheme.accent.opacity(0.2)
        case .completed:
            return AppTheme.accent.opacity(0.2)
        case .failed:
            return Color.red.opacity(0.2)
        }
    }
    
    private var statusIconColor: Color {
        switch item.status {
        case .pending:
            return AppTheme.secondaryText
        case .inProgress:
            return AppTheme.accent
        case .completed:
            return AppTheme.accent
        case .failed:
            return .red
        }
    }
}

#Preview {
    RefreshProgressModal(progressTracker: RefreshProgressTracker())
}

