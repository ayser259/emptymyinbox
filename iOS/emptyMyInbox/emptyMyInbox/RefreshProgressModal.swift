//
//  RefreshProgressModal.swift
//  emptyMyInbox
//
//  Modal view showing detailed refresh progress with live logs
//

import SwiftUI

struct RefreshProgressModal: View {
    @ObservedObject var progressTracker: RefreshProgressTracker
    @StateObject private var logger = DebugLogger.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab picker
                    Picker("View", selection: $selectedTab) {
                        Text("Progress").tag(0)
                        Text("Live Logs").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, AppTheme.spacingMedium)
                    .padding(.vertical, AppTheme.spacingSmall)
                    
                    if selectedTab == 0 {
                        progressView
                    } else {
                        liveLogsView
                    }
                }
            }
            .navigationTitle("Refresh Status")
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
    
    private var progressView: some View {
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
                                .animation(.easeInOut(duration: 0.3), value: progressTracker.overallProgress)
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
    
    private var liveLogsView: some View {
        VStack(spacing: 0) {
            // Recent logs (last 50)
            let recentLogs = Array(logger.entries.suffix(50))
            
            if recentLogs.isEmpty {
                VStack(spacing: AppTheme.spacingMedium) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.secondaryText)
                    
                    Text("No logs yet")
                        .font(AppTheme.headline)
                        .primaryText()
                    
                    Text("Logs will appear here during refresh")
                        .font(AppTheme.body)
                        .secondaryText()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(recentLogs) { entry in
                                CompactLogRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .onChange(of: logger.entries.count) { _, _ in
                        if let lastLog = recentLogs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            // Bottom bar with copy button
            HStack {
                Text("\(recentLogs.count) recent logs")
                    .font(AppTheme.caption)
                    .secondaryText()
                
                Spacer()
                
                Button {
                    UIPasteboard.general.string = logger.exportAsText()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                        Text("Copy All")
                            .font(AppTheme.caption)
                    }
                    .foregroundColor(AppTheme.accent)
                }
            }
            .padding(.horizontal, AppTheme.spacingMedium)
            .padding(.vertical, AppTheme.spacingSmall)
            .background(AppTheme.secondaryBackground)
        }
    }
}

struct CompactLogRow: View {
    let entry: LogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.level.emoji)
                .font(.system(size: 12))
            
            Text(entry.formattedTimestamp)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(AppTheme.secondaryText)
            
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(entry.level.color)
                .lineLimit(2)
        }
        .padding(.horizontal, AppTheme.spacingSmall)
        .padding(.vertical, 4)
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

