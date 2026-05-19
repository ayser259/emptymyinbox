//
//  MailboxListChrome.swift
//  EmptyMyInboxShared
//
//  Shared empty, refresh, and filter chrome for mailbox lists.
//

import SwiftUI

// MARK: - Refresh status

public struct MailboxRefreshStatusView: View {
    let lastRefreshTime: Date
    let mostRecentEmailTime: Date?

    public init(lastRefreshTime: Date, mostRecentEmailTime: Date?) {
        self.lastRefreshTime = lastRefreshTime
        self.mostRecentEmailTime = mostRecentEmailTime
    }

    public var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.7))
                Text("Last refreshed: \(MailboxRefreshStatusView.formatRefreshTime(lastRefreshTime))")
                    .font(.caption)
                    .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.7))
                Spacer()
            }

            if let mostRecentEmailTime {
                HStack {
                    Image(systemName: "envelope")
                        .font(.caption)
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.7))
                    Text("Most recent: \(MailboxRefreshStatusView.formatEmailTime(mostRecentEmailTime))")
                        .font(.caption)
                        .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.7))
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }

    static func formatRefreshTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        if calendar.dateComponents([.second], from: date, to: now).second ?? 0 < 60 {
            return "just now"
        }
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Today at \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Yesterday at \(timeFormatter.string(from: date))"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: date)
    }

    static func formatEmailTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Today at \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Yesterday at \(timeFormatter.string(from: date))"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: date)
    }
}

// MARK: - Empty state

public struct MailboxEmptyStateView: View {
    let config: MailboxDisplayConfig

    public init(config: MailboxDisplayConfig) {
        self.config = config
    }

    public var body: some View {
        VStack(spacing: SharedAppTheme.spacingMedium) {
            Image(systemName: config.emptyIconSystemName)
                .font(.system(size: 48))
                .foregroundStyle(SharedAppTheme.secondaryText)
            Text(config.emptyTitle)
                .font(SharedAppTheme.title3)
                .primaryText()
            Text(config.emptySubtitle)
                .font(SharedAppTheme.body)
                .secondaryText()
                .multilineTextAlignment(.center)
                .padding(.horizontal, SharedAppTheme.spacingLarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Read filter chips

public struct MailboxReadFilterBar: View {
    @Binding var selection: MailboxReadFilter
    var onSelectionChange: ((MailboxReadFilter) -> Void)?

    public init(
        selection: Binding<MailboxReadFilter>,
        onSelectionChange: ((MailboxReadFilter) -> Void)? = nil
    ) {
        _selection = selection
        self.onSelectionChange = onSelectionChange
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MailboxReadFilter.allCases, id: \.self) { filter in
                    MailboxReadFilterChip(
                        title: filter.rawValue,
                        isSelected: selection == filter,
                        action: {
                            selection = filter
                            onSelectionChange?(filter)
                        }
                    )
                }
            }
            .padding(.horizontal, SharedAppTheme.spacingMedium)
            .padding(.vertical, SharedAppTheme.spacingSmall)
        }
    }
}

public struct MailboxReadFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    #if os(macOS)
    @State private var isHovered = false
    #endif

    public init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.black : SharedAppTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(chipBackground)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        #else
        .buttonStyle(.plain)
        #endif
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    @ViewBuilder
    private var chipBackground: some View {
        #if os(macOS)
        Capsule()
            .fill(
                isSelected
                    ? SharedAppTheme.accent
                    : (isHovered
                       ? SharedAppTheme.secondaryText.opacity(0.15)
                       : SharedAppTheme.secondaryBackground)
            )
        #else
        Capsule()
            .fill(isSelected ? SharedAppTheme.accent : SharedAppTheme.secondaryBackground)
        #endif
    }
}

// MARK: - Unread count header

public struct MailboxUnreadCountHeader: View {
    let count: Int

    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        if count > 0 {
            HStack {
                Text("\(count) unread")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SharedAppTheme.accent)
                Spacer()
            }
            .padding(.horizontal, SharedAppTheme.spacingMedium)
            .padding(.vertical, SharedAppTheme.spacingSmall)
        }
    }
}
