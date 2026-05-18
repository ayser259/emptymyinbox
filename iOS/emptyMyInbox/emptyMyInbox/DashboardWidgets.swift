//
//  DashboardWidgets.swift
//  emptyMyInbox
//
//  Dashboard widget components: greeting, daily brief card, action items card,
//  account updates card, and stories feed card.
//

import SwiftUI
import EmptyMyInboxShared

// MARK: - Notification names (iOS-local)

extension Notification.Name {
    static let switchToActionItemsTab = Notification.Name("SwitchToActionItemsTab")
}

// MARK: - Greeting

struct DashboardGreetingSection: View {
    let name: String?

    private var timeLabel: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0..<12: return "GOOD MORNING"
        case 12..<17: return "GOOD AFTERNOON"
        default: return "GOOD EVENING"
        }
    }

    private var dateLabel: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeLabel)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(AppTheme.accent)

            Text(name?.isEmpty == false ? name! : "Welcome back")
                .font(AppTheme.title3)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.primaryText)

            Text(dateLabel)
                .font(AppTheme.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Card shell

struct DashboardCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(AppTheme.spacingMedium)
            .frame(maxWidth: .infinity)
            .background(AppTheme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

// MARK: - Card header row

private struct CardHeaderRow: View {
    let icon: String
    let title: String
    var count: Int? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(AppTheme.secondaryText)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
            }
            Spacer()
            if let trailing {
                trailing
            }
        }
    }
}

// MARK: - Empty state

private struct CardEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.3))
            Text(title)
                .font(AppTheme.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.6))
            Text(subtitle)
                .font(AppTheme.caption)
                .foregroundStyle(AppTheme.secondaryText.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacingMedium)
    }
}

// MARK: - View more row

private struct ViewMoreRow: View {
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Spacer()
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.top, 6)
    }
}

// MARK: - Daily Brief Card

struct DashboardDailyBriefCard: View {
    let payload: DailyBriefingPayload?
    let hasLLMKey: Bool
    let isGenerating: Bool
    let onRefresh: () -> Void
    let onOpenLLMSettings: () -> Void

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                CardHeaderRow(
                    icon: "sparkles",
                    title: "DAILY BRIEF",
                    count: payload?.items.count,
                    trailing: AnyView(refreshButton)
                )

                Divider().opacity(0.15)

                briefContent
                    .animation(.easeOut(duration: 0.2), value: payload == nil)
            }
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button {
            onRefresh()
        } label: {
            if isGenerating {
                ProgressView()
                    .scaleEffect(0.65)
                    .tint(AppTheme.accent)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hasLLMKey ? AppTheme.accent : AppTheme.secondaryText.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
        .disabled(isGenerating || !hasLLMKey)
        .animation(.easeOut(duration: 0.15), value: isGenerating)
    }

    @ViewBuilder
    private var briefContent: some View {
        if !hasLLMKey {
            VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                CardEmptyState(
                    icon: "lock.fill",
                    title: "Set up AI",
                    subtitle: "Add an API key to enable your daily brief"
                )
                Button("Configure") {
                    onOpenLLMSettings()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)
            }
        } else if let payload {
            NavigationLink(value: "daily_brief") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(payload.introText)
                        .font(AppTheme.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    let previewItems = Array(payload.items.prefix(2))
                    if !previewItems.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(previewItems) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: item.section.iconName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppTheme.accent)
                                        .padding(.top, 1.5)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.subject)
                                            .font(AppTheme.caption)
                                            .foregroundStyle(AppTheme.primaryText)
                                            .lineLimit(1)
                                        if let summary = item.summary, !summary.isEmpty {
                                            Text(summary)
                                                .font(.system(size: 10))
                                                .foregroundStyle(AppTheme.secondaryText)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    ViewMoreRow(label: "View full brief")
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: "daily_brief") {
                CardEmptyState(
                    icon: "sparkles",
                    title: "No brief yet",
                    subtitle: "Tap to generate or use the refresh button"
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Action Items Card

struct DashboardActionItemsCard: View {
    let items: [VaultActionItemRecord]
    let isVaultReady: Bool

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                CardHeaderRow(
                    icon: "checklist",
                    title: "ACTION ITEMS",
                    count: items.isEmpty ? nil : items.count
                )

                Divider().opacity(0.15)

                actionContent
                    .animation(.easeOut(duration: 0.2), value: isVaultReady)
            }
        }
    }

    @ViewBuilder
    private var actionContent: some View {
        if !isVaultReady {
            CardEmptyState(
                icon: "externaldrive.badge.xmark",
                title: "Vault not connected",
                subtitle: "Set up a vault in Settings"
            )
        } else if items.isEmpty {
            CardEmptyState(
                icon: "checkmark.circle",
                title: "All clear",
                subtitle: "No pending action items"
            )
        } else {
            let preview = Array(items.prefix(3))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(preview.enumerated()), id: \.element.id) { idx, item in
                    ActionItemPreviewRow(item: item)
                    if idx < preview.count - 1 {
                        Divider().opacity(0.1).padding(.leading, 20)
                    }
                }

                Button {
                    NotificationCenter.default.post(name: .switchToActionItemsTab, object: nil)
                } label: {
                    ViewMoreRow(label: items.count > 3 ? "View all \(items.count)" : "View all")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ActionItemPreviewRow: View {
    let item: VaultActionItemRecord

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let p = item.priority {
                    Circle()
                        .strokeBorder(ActionItemPriorityColors.color(forStoredPriority: p), lineWidth: 1.5)
                } else {
                    Circle()
                        .strokeBorder(AppTheme.secondaryText.opacity(0.35), lineWidth: 1.5)
                }
            }
            .frame(width: 11, height: 11)

            Text(item.title)
                .font(AppTheme.caption)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Account Updates Card

struct DashboardAccountUpdatesCard: View {
    let unreadCount: Int
    let starredCount: Int

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                CardHeaderRow(icon: "envelope", title: "ACCOUNT UPDATES")

                Divider().opacity(0.15)

                HStack(spacing: AppTheme.spacingSmall) {
                    StatPill(label: "Unread", count: unreadCount, filled: true)
                    StatPill(label: "Saved", count: starredCount, filled: false)
                    Spacer()
                }

                Divider().opacity(0.1)

                HStack(spacing: AppTheme.spacingSmall) {
                    NavigationLink(value: "catch_up") {
                        Text("Catch Up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: "all_emails") {
                        Text("View More")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct StatPill: View {
    let label: String
    let count: Int
    let filled: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text("\(count)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(filled ? .black : AppTheme.primaryText)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(filled ? Color.black.opacity(0.7) : AppTheme.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(filled ? AppTheme.accent : Color.white.opacity(0.07))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(filled ? Color.clear : Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Stories Feed Card

struct DashboardStoriesFeedCard: View {
    let stories: [InsightCard]

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: AppTheme.spacingSmall) {
                CardHeaderRow(
                    icon: "rectangle.stack.fill",
                    title: "STORIES",
                    count: stories.isEmpty ? nil : stories.count
                )

                Divider().opacity(0.15)

                storiesContent
            }
        }
    }

    @ViewBuilder
    private var storiesContent: some View {
        if stories.isEmpty {
            CardEmptyState(
                icon: "rectangle.stack",
                title: "No stories yet",
                subtitle: "Stories appear as your newsletters are processed"
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stories.enumerated()), id: \.element.id) { idx, story in
                    StoryPreviewRow(story: story)
                    if idx < stories.count - 1 {
                        Divider().opacity(0.1).padding(.leading, 38)
                    }
                }

                NavigationLink(value: "insights") {
                    ViewMoreRow(label: "View all stories")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct StoryPreviewRow: View {
    let story: InsightCard

    private var initial: String {
        let name = story.senderName ?? story.sender
        return String((name.first ?? "?").uppercased())
    }

    private var senderDisplay: String {
        story.senderName?.isEmpty == false ? story.senderName! : story.sender
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.14))
                    .frame(width: 28, height: 28)
                Text(initial)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(senderDisplay)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                Text(story.subject)
                    .font(AppTheme.caption)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.35))
        }
        .padding(.vertical, 6)
    }
}
