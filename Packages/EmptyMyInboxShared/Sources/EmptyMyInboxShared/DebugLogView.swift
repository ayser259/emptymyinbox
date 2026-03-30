//
//  DebugLogView.swift
//  emptyMyInbox
//
//  Debug log viewer with filtering and copy functionality
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct DebugLogView: View {
    @StateObject private var logger = DebugLogger.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var selectedLevel: LogLevel? = nil
    @State private var selectedCategory: String? = nil
    @State private var showCopiedAlert = false
    @State private var autoScrollEnabled = true
    @State private var showFilters = false

    public init() {}
    
    var filteredEntries: [LogEntry] {
        logger.filteredEntries(level: selectedLevel, category: selectedCategory, searchText: searchText)
    }

    private var debugLogsOverflowMenu: some View {
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
                .foregroundColor(SharedAppTheme.accent)
        }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                SharedAppTheme.primaryBackground
                    #if os(iOS)
                    .ignoresSafeArea()
                    #endif
                
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(SharedAppTheme.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    debugLogsOverflowMenu
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(SharedAppTheme.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    debugLogsOverflowMenu
                }
                #endif
            }
            .alert("Copied!", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Debug logs copied to clipboard")
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: SharedAppTheme.spacingSmall) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(SharedAppTheme.secondaryText)
                
                TextField("Search logs...", text: $searchText)
                    .foregroundStyle(SharedAppTheme.primaryText)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(SharedAppTheme.secondaryText)
                    }
                }
            }
            .padding(SharedAppTheme.spacingSmall)
            .background(SharedAppTheme.secondaryBackground)
            .cornerRadius(SharedAppTheme.cornerRadiusSmall)
            
            Button {
                withAnimation {
                    showFilters.toggle()
                }
            } label: {
                Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 22))
                    .foregroundColor(hasActiveFilters ? SharedAppTheme.accent : SharedAppTheme.secondaryText)
            }
        }
        .padding(.horizontal, SharedAppTheme.spacingMedium)
        .padding(.vertical, SharedAppTheme.spacingSmall)
    }
    
    private var hasActiveFilters: Bool {
        selectedLevel != nil || selectedCategory != nil
    }
    
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: SharedAppTheme.spacingSmall) {
            // Level filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SharedAppTheme.spacingSmall) {
                    Text("Level:")
                        .font(SharedAppTheme.caption)
                        .foregroundStyle(SharedAppTheme.secondaryText)
                    
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
                .padding(.horizontal, SharedAppTheme.spacingMedium)
            }
            
            // Category filters (if any)
            if !logger.categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SharedAppTheme.spacingSmall) {
                        Text("Category:")
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                        
                        FilterChip(title: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        
                        ForEach(logger.categories, id: \.self) { category in
                            FilterChip(title: category, isSelected: selectedCategory == category) {
                                selectedCategory = category
                            }
                        }
                    }
                    .padding(.horizontal, SharedAppTheme.spacingMedium)
                }
            }
        }
        .padding(.vertical, SharedAppTheme.spacingSmall)
        .background(SharedAppTheme.secondaryBackground.opacity(0.5))
    }
    
    private var emptyState: some View {
        VStack(spacing: SharedAppTheme.spacingMedium) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(SharedAppTheme.secondaryText)
            
            Text("No logs found")
                .font(SharedAppTheme.headline)
                .foregroundStyle(SharedAppTheme.primaryText)
            
            if hasActiveFilters || !searchText.isEmpty {
                Text("Try adjusting your filters")
                    .font(SharedAppTheme.body)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                
                Button {
                    searchText = ""
                    selectedLevel = nil
                    selectedCategory = nil
                } label: {
                    Text("Clear Filters")
                        .font(SharedAppTheme.subheadline)
                        .foregroundColor(SharedAppTheme.accent)
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
                            .background(SharedAppTheme.secondaryText.opacity(0.2))
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
                .font(SharedAppTheme.caption)
                .foregroundStyle(SharedAppTheme.secondaryText)
            
            Spacer()
            
            // Auto-scroll toggle
            Button {
                autoScrollEnabled.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: autoScrollEnabled ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 14))
                    Text("Auto-scroll")
                        .font(SharedAppTheme.caption)
                }
                .foregroundColor(autoScrollEnabled ? SharedAppTheme.accent : SharedAppTheme.secondaryText)
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
                        .font(SharedAppTheme.caption)
                }
                .foregroundColor(SharedAppTheme.accent)
            }
        }
        .padding(.horizontal, SharedAppTheme.spacingMedium)
        .padding(.vertical, SharedAppTheme.spacingSmall)
        .background(SharedAppTheme.secondaryBackground)
    }
    
    private func copyLogs() {
        copyStringToPasteboard(logger.exportAsText())
        showCopiedAlert = true
    }
    
    private func shareLogs() {
        let text = logger.exportAsText()
        #if os(iOS)
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
        #elseif os(macOS)
        copyStringToPasteboard(text)
        showCopiedAlert = true
        #endif
    }

    private func copyStringToPasteboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

struct LogEntryRow: View {
    let entry: LogEntry
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: SharedAppTheme.spacingSmall) {
                // Level indicator
                Text(entry.level.emoji)
                    .font(.system(size: 14))
                
                // Timestamp
                Text(entry.formattedTimestamp)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(SharedAppTheme.secondaryText)
                
                // Category badge
                if let category = entry.category {
                    Text(category)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(SharedAppTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SharedAppTheme.accent.opacity(0.2))
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
        .padding(.horizontal, SharedAppTheme.spacingMedium)
        .padding(.vertical, SharedAppTheme.spacingSmall)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
        .contextMenu {
            Button {
                #if os(iOS)
                UIPasteboard.general.string = entry.message
                #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.message, forType: .string)
                #endif
            } label: {
                SwiftUI.Label("Copy Message", systemImage: "doc.on.doc")
            }
            
            Button {
                let full = "[\(entry.fullTimestamp)] [\(entry.level.rawValue)] \(entry.message)"
                #if os(iOS)
                UIPasteboard.general.string = full
                #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(full, forType: .string)
                #endif
            } label: {
                SwiftUI.Label("Copy with Timestamp", systemImage: "doc.on.doc.fill")
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = SharedAppTheme.accent
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : SharedAppTheme.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? color : SharedAppTheme.secondaryBackground)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? color : SharedAppTheme.secondaryText.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    DebugLogView()
}




