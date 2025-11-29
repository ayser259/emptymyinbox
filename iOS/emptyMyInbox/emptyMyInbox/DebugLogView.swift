//
//  DebugLogView.swift
//  emptyMyInbox
//
//  Debug log viewer with filtering and copy functionality
//

import SwiftUI

struct DebugLogView: View {
    @StateObject private var logger = DebugLogger.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var selectedLevel: LogLevel? = nil
    @State private var selectedCategory: String? = nil
    @State private var showCopiedAlert = false
    @State private var autoScrollEnabled = true
    @State private var showFilters = false
    
    var filteredEntries: [LogEntry] {
        logger.filteredEntries(level: selectedLevel, category: selectedCategory, searchText: searchText)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.primaryBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search and filter bar
                    searchBar
                    
                    // Filter chips (when expanded)
                    if showFilters {
                        filterSection
                    }
                    
                    // Log entries
                    if filteredEntries.isEmpty {
                        emptyState
                    } else {
                        logList
                    }
                    
                    // Bottom toolbar
                    bottomToolbar
                }
            }
            .navigationTitle("Debug Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .textButton()
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            copyLogs()
                        } label: {
                            SwiftUI.Label("Copy All Logs", systemImage: "doc.on.doc")
                        }
                        
                        Button {
                            shareLogs()
                        } label: {
                            SwiftUI.Label("Share Logs", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            logger.clear()
                        } label: {
                            SwiftUI.Label("Clear Logs", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundColor(AppTheme.accent)
                    }
                }
            }
            .alert("Copied!", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Debug logs copied to clipboard")
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: AppTheme.spacingSmall) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.secondaryText)
                
                TextField("Search logs...", text: $searchText)
                    .primaryText()
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.secondaryText)
                    }
                }
            }
            .padding(AppTheme.spacingSmall)
            .background(AppTheme.secondaryBackground)
            .cornerRadius(AppTheme.cornerRadiusSmall)
            
            Button {
                withAnimation {
                    showFilters.toggle()
                }
            } label: {
                Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 22))
                    .foregroundColor(hasActiveFilters ? AppTheme.accent : AppTheme.secondaryText)
            }
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, AppTheme.spacingSmall)
    }
    
    private var hasActiveFilters: Bool {
        selectedLevel != nil || selectedCategory != nil
    }
    
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
            // Level filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacingSmall) {
                    Text("Level:")
                        .font(AppTheme.caption)
                        .secondaryText()
                    
                    FilterChip(title: "All", isSelected: selectedLevel == nil) {
                        selectedLevel = nil
                    }
                    
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        FilterChip(
                            title: "\(level.emoji) \(level.rawValue)",
                            isSelected: selectedLevel == level,
                            color: level.color
                        ) {
                            selectedLevel = level
                        }
                    }
                }
                .padding(.horizontal, AppTheme.spacingMedium)
            }
            
            // Category filters (if any)
            if !logger.categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacingSmall) {
                        Text("Category:")
                            .font(AppTheme.caption)
                            .secondaryText()
                        
                        FilterChip(title: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        
                        ForEach(logger.categories, id: \.self) { category in
                            FilterChip(title: category, isSelected: selectedCategory == category) {
                                selectedCategory = category
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingMedium)
                }
            }
        }
        .padding(.vertical, AppTheme.spacingSmall)
        .background(AppTheme.secondaryBackground.opacity(0.5))
    }
    
    private var emptyState: some View {
        VStack(spacing: AppTheme.spacingMedium) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.secondaryText)
            
            Text("No logs found")
                .font(AppTheme.headline)
                .primaryText()
            
            if hasActiveFilters || !searchText.isEmpty {
                Text("Try adjusting your filters")
                    .font(AppTheme.body)
                    .secondaryText()
                
                Button {
                    searchText = ""
                    selectedLevel = nil
                    selectedCategory = nil
                } label: {
                    Text("Clear Filters")
                        .font(AppTheme.subheadline)
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                        
                        Divider()
                            .background(AppTheme.secondaryText.opacity(0.2))
                    }
                }
            }
            .onChange(of: logger.entries.count) { _, _ in
                if autoScrollEnabled, let lastEntry = filteredEntries.last {
                    withAnimation {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var bottomToolbar: some View {
        HStack {
            // Entry count
            Text("\(filteredEntries.count) entries")
                .font(AppTheme.caption)
                .secondaryText()
            
            Spacer()
            
            // Auto-scroll toggle
            Button {
                autoScrollEnabled.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: autoScrollEnabled ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 14))
                    Text("Auto-scroll")
                        .font(AppTheme.caption)
                }
                .foregroundColor(autoScrollEnabled ? AppTheme.accent : AppTheme.secondaryText)
            }
            
            Spacer()
            
            // Quick copy button
            Button {
                copyLogs()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                    Text("Copy")
                        .font(AppTheme.caption)
                }
                .foregroundColor(AppTheme.accent)
            }
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, AppTheme.spacingSmall)
        .background(AppTheme.secondaryBackground)
    }
    
    private func copyLogs() {
        UIPasteboard.general.string = logger.exportAsText()
        showCopiedAlert = true
    }
    
    private func shareLogs() {
        let text = logger.exportAsText()
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}

struct LogEntryRow: View {
    let entry: LogEntry
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: AppTheme.spacingSmall) {
                // Level indicator
                Text(entry.level.emoji)
                    .font(.system(size: 14))
                
                // Timestamp
                Text(entry.formattedTimestamp)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.secondaryText)
                
                // Category badge
                if let category = entry.category {
                    Text(category)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.accent.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Spacer()
            }
            
            // Message
            Text(entry.message)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(entry.level.color.opacity(0.9))
                .lineLimit(isExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppTheme.spacingMedium)
        .padding(.vertical, AppTheme.spacingSmall)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.message
            } label: {
                SwiftUI.Label("Copy Message", systemImage: "doc.on.doc")
            }
            
            Button {
                UIPasteboard.general.string = "[\(entry.fullTimestamp)] [\(entry.level.rawValue)] \(entry.message)"
            } label: {
                SwiftUI.Label("Copy with Timestamp", systemImage: "doc.on.doc.fill")
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = AppTheme.accent
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : AppTheme.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? color : AppTheme.secondaryBackground)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? color : AppTheme.secondaryText.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    DebugLogView()
}


