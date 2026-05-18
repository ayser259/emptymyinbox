//
//  MacUnifiedDashboardView.swift
//  emptymyinboxMacApp
//
//  Dashboard: greeting + widgets (brief, action items, account updates, stories) + inbox feed.
//

import SwiftUI
import EmptyMyInboxShared

struct MacUnifiedDashboardView: View {
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject var calendarModel: GoogleCalendarViewModel
    let snapshot: DashboardDataSnapshot?
    let actionItems: [VaultActionItemRecord]
    let isRefreshing: Bool
    let refreshMessage: String?
    var onOpenMailbox: ((String) -> Void)?
    var onOpenCatchUp: (() -> Void)?
    var onOpenBrief: (() -> Void)?
    var onOpenStories: (() -> Void)?

    @State private var dailyBriefingPayload: DailyBriefingPayload?
    @State private var recentStories: [InsightCard] = []
    @State private var hasLLMKey = false
    @State private var isBriefGenerating = false

    private var calendar: Calendar { Calendar.current }

    private var openTasks: [VaultActionItemRecord] {
        ActionItemsFeatureModel.defaultSorted(actionItems.filter { !$0.isDone })
    }

    private var upcomingEvents: [GoogleCalendarDisplayEvent] {
        let now = Date()
        guard let horizon = calendar.date(byAdding: .day, value: 21, to: now) else { return [] }
        return calendarModel.events
            .filter { $0.end > now && $0.start < horizon }
            .sorted { $0.start < $1.start }
            .prefix(16)
            .map { $0 }
    }

    private var firstName: String? {
        guard let fullName = authManager.accounts.first?.name, !fullName.isEmpty else { return nil }
        return fullName.components(separatedBy: " ").first
    }

    private var totalUnread: Int {
        snapshot?.emails.count ?? 0
    }

    private var totalStarred: Int {
        snapshot?.starredEmails.count ?? 0
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            twoColumnLayout
            stackedLayout
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacAppTheme.primaryBackground)
        .navigationTitle("Dashboard")
        .task {
            await loadWidgetData()
            if calendarModel.events.isEmpty && !calendarModel.isLoading {
                await calendarModel.refresh()
            }
        }
        .onChange(of: snapshot?.timestamp) { _, _ in
            Task { await loadRecentStories() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .briefingPayloadDidPersist)) { _ in
            Task { await refreshBriefBadge() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .llmAPIKeyChanged)) { _ in
            Task { await refreshLLMKeyStatus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .claudeAPIKeyChanged)) { _ in
            Task { await refreshLLMKeyStatus() }
        }
    }

    // MARK: - Layout

    private var twoColumnLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            leftFeedColumn
                .frame(maxWidth: .infinity)
            rightCalendarColumn
                .frame(width: 300)
        }
        .padding(24)
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            leftFeedColumn
            rightCalendarColumn
                .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    // MARK: - Left column

    private var leftFeedColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Greeting
                greetingSection

                // Refresh progress
                if isRefreshing {
                    HStack {
                        Spacer(minLength: 0)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                if let refreshMessage {
                    Text(refreshMessage)
                        .font(.caption)
                        .foregroundStyle(MacAppTheme.secondaryText)
                }

                // Brief + Action Items side by side
                HStack(alignment: .top, spacing: 12) {
                    MacDailyBriefCard(
                        payload: dailyBriefingPayload,
                        hasLLMKey: hasLLMKey,
                        isGenerating: isBriefGenerating,
                        onRefresh: { refreshBrief() },
                        onOpenBrief: onOpenBrief,
                        onOpenLLMSettings: { onOpenBrief?() }
                    )
                    .frame(maxWidth: .infinity)

                    MacActionItemsCard(
                        items: openTasks,
                        isVaultReady: VaultManager.shared.isVaultReady
                    )
                    .frame(width: 220)
                }

                // Account Updates
                MacAccountUpdatesCard(
                    unreadCount: totalUnread,
                    starredCount: totalStarred,
                    onCatchUp: onOpenCatchUp,
                    onViewMore: snapshot.flatMap { snap in
                        snap.accounts.first.map { acct in { self.onOpenMailbox?(acct.email) } }
                    }
                )

                // Stories Feed
                MacStoriesFeedCard(
                    stories: recentStories,
                    onViewAll: onOpenStories
                )

                // Inbox feed
                if let snapshot, !snapshot.accounts.isEmpty {
                    MacDashboardSectionTitle("Inbox feed")
                    Text("By account")
                        .font(.caption)
                        .foregroundStyle(MacAppTheme.secondaryText.opacity(0.9))

                    accountSections(snapshot: snapshot)
                } else {
                    Text("No accounts loaded — refresh your mailbox.")
                        .font(.body)
                        .foregroundStyle(MacAppTheme.secondaryText)
                }

                MacInboxMetricsCard()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Right column

    private var rightCalendarColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MacDashboardSectionTitle("Calendar")
                MacCalendarMiniMonthView(
                    selectedDate: $calendarModel.selectedDate,
                    accentColor: MacAppTheme.accent,
                    hasEventOnDay: { day in
                        !calendarModel.eventsOverlapping(dayContaining: day).isEmpty
                    }
                )

                MacDashboardSectionTitle("Upcoming")
                Group {
                    if calendarModel.isLoading && calendarModel.events.isEmpty {
                        ProgressView("Loading calendar…")
                            .foregroundStyle(MacAppTheme.secondaryText)
                    } else if upcomingEvents.isEmpty {
                        Text("No upcoming events in the next few weeks.")
                            .font(.body)
                            .foregroundStyle(MacAppTheme.secondaryText)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(upcomingEvents) { ev in
                                MacDashboardUpcomingEventRow(event: ev)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(MacAppTheme.secondaryBackground.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(timeLabel)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(MacAppTheme.accent)
            Text(firstName ?? "Welcome back")
                .font(.title3.weight(.bold))
                .foregroundStyle(MacAppTheme.primaryText)
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.caption)
                .foregroundStyle(MacAppTheme.secondaryText)
        }
    }

    private var timeLabel: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0..<12: return "GOOD MORNING"
        case 12..<17: return "GOOD AFTERNOON"
        default: return "GOOD EVENING"
        }
    }

    // MARK: - Account sections

    @ViewBuilder
    private func accountSections(snapshot: DashboardDataSnapshot) -> some View {
        ForEach(snapshot.accounts, id: \.id) { account in
            accountRow(account: account, snapshot: snapshot)
        }
    }

    @ViewBuilder
    private func accountRow(account: EmailAccount, snapshot: DashboardDataSnapshot) -> some View {
        MacDashboardAccountSection(
            account: account,
            unread: unreadCount(for: account, snapshot: snapshot),
            starred: starredCount(for: account, snapshot: snapshot),
            total: totalCount(for: account, snapshot: snapshot),
            unreadSenderCount: unreadSenderCount(for: account, snapshot: snapshot),
            onViewMore: onOpenMailbox.map { open in { open(account.email) } },
            onCatchUp: (onOpenCatchUp != nil && unreadCount(for: account, snapshot: snapshot) > 0) ? onOpenCatchUp : nil
        )
    }

    private func unreadCount(for account: EmailAccount, snapshot: DashboardDataSnapshot) -> Int {
        snapshot.allEmails.filter {
            $0.account_email.lowercased() == account.email.lowercased() && !$0.is_read && !$0.is_starred
        }.count
    }

    private func starredCount(for account: EmailAccount, snapshot: DashboardDataSnapshot) -> Int {
        snapshot.starredEmails.filter { $0.account_email.lowercased() == account.email.lowercased() }.count
    }

    private func totalCount(for account: EmailAccount, snapshot: DashboardDataSnapshot) -> Int {
        snapshot.allEmails.filter { $0.account_email.lowercased() == account.email.lowercased() }.count
    }

    private func unreadSenderCount(for account: EmailAccount, snapshot: DashboardDataSnapshot) -> Int {
        let unread = snapshot.allEmails.filter {
            $0.account_email.lowercased() == account.email.lowercased() && !$0.is_read && !$0.is_starred
        }
        return Set(unread.map(\.sender)).count
    }

    // MARK: - Data loading

    private func loadWidgetData() async {
        await refreshBriefBadge()
        await refreshLLMKeyStatus()
        await loadRecentStories()
    }

    private func refreshBriefBadge() async {
        let hasKey = await LLMProviderRouter.shared.hasSelectedProviderAPIKey()
        guard hasKey else {
            await MainActor.run { dailyBriefingPayload = nil }
            return
        }
        guard let data = UserDefaults.standard.data(forKey: DailyBriefingDefaults.persistedPayloadKey),
              let payload = try? JSONDecoder().decode(DailyBriefingPayload.self, from: data) else {
            await MainActor.run { dailyBriefingPayload = nil }
            return
        }
        await MainActor.run { dailyBriefingPayload = payload }
    }

    private func refreshLLMKeyStatus() async {
        let hasKey = await LLMProviderRouter.shared.hasSelectedProviderAPIKey()
        await MainActor.run { hasLLMKey = hasKey }
    }

    private func loadRecentStories() async {
        let stories = await StoriesFeedStore.shared.stories()
        await MainActor.run { recentStories = Array(stories.prefix(3)) }
    }

    private func refreshBrief() {
        Task {
            guard hasLLMKey else { return }
            await MainActor.run { isBriefGenerating = true }
            let built = await DailyBriefingEngine.shared.buildPayload(
                from: snapshot?.allEmails ?? [],
                sinceDate: nil
            )
            if let data = try? JSONEncoder().encode(built) {
                UserDefaults.standard.set(data, forKey: DailyBriefingDefaults.persistedPayloadKey)
            }
            NotificationCenter.default.post(name: .briefingPayloadDidPersist, object: nil)
            await MainActor.run {
                dailyBriefingPayload = built
                isBriefGenerating = false
            }
        }
    }
}

// MARK: - Shared section title

private func MacDashboardSectionTitle(_ text: String) -> some View {
    Text(text)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(MacAppTheme.secondaryText)
}

// MARK: - Mac card shell

struct MacDashboardCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MacAppTheme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
    }
}

// MARK: - Mac card header

struct MacCardHeader: View {
    let icon: String
    let title: String
    var count: Int? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MacAppTheme.accent)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(MacAppTheme.secondaryText)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(MacAppTheme.accent)
                    .clipShape(Capsule())
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

// MARK: - Mac empty state

private struct MacCardEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(MacAppTheme.secondaryText.opacity(0.3))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MacAppTheme.secondaryText.opacity(0.6))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(MacAppTheme.secondaryText.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Daily Brief Card

private struct MacDailyBriefCard: View {
    let payload: DailyBriefingPayload?
    let hasLLMKey: Bool
    let isGenerating: Bool
    let onRefresh: () -> Void
    let onOpenBrief: (() -> Void)?
    let onOpenLLMSettings: () -> Void

    var body: some View {
        MacDashboardCard {
            VStack(alignment: .leading, spacing: 8) {
                MacCardHeader(
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
                    .scaleEffect(0.6)
                    .controlSize(.mini)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hasLLMKey ? MacAppTheme.accent : MacAppTheme.secondaryText.opacity(0.3))
            }
        }
        .buttonStyle(.plain)
        .disabled(isGenerating || !hasLLMKey)
        .help(hasLLMKey ? "Regenerate brief" : "Add an AI API key first")
        .animation(.easeOut(duration: 0.15), value: isGenerating)
    }

    @ViewBuilder
    private var briefContent: some View {
        if !hasLLMKey {
            VStack(alignment: .leading, spacing: 6) {
                MacCardEmptyState(
                    icon: "lock.fill",
                    title: "Set up AI",
                    subtitle: "Add an API key to enable your daily brief"
                )
                Button("Configure in Settings") {
                    onOpenLLMSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MacAppTheme.accent)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        } else if let payload {
            Button {
                onOpenBrief?()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(payload.introText)
                        .font(.caption)
                        .foregroundStyle(MacAppTheme.secondaryText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    let items = Array(payload.items.prefix(2))
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(items) { item in
                                HStack(alignment: .top, spacing: 5) {
                                    Image(systemName: item.section.iconName)
                                        .font(.system(size: 9))
                                        .foregroundStyle(MacAppTheme.accent)
                                        .padding(.top, 1)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.subject)
                                            .font(.caption)
                                            .foregroundStyle(MacAppTheme.primaryText)
                                            .lineLimit(1)
                                        if let summary = item.summary, !summary.isEmpty {
                                            Text(summary)
                                                .font(.system(size: 10))
                                                .foregroundStyle(MacAppTheme.secondaryText)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Text("View full brief")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MacAppTheme.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(MacAppTheme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
        } else {
            Button {
                onOpenBrief?()
            } label: {
                MacCardEmptyState(
                    icon: "sparkles",
                    title: "No brief yet",
                    subtitle: "Click to navigate to Brief or use refresh"
                )
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
        }
    }
}

// MARK: - Action Items Card

private struct MacActionItemsCard: View {
    let items: [VaultActionItemRecord]
    let isVaultReady: Bool

    var body: some View {
        MacDashboardCard {
            VStack(alignment: .leading, spacing: 8) {
                MacCardHeader(
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
            MacCardEmptyState(
                icon: "externaldrive.badge.xmark",
                title: "Vault not connected",
                subtitle: "Set up a vault in Settings"
            )
        } else if items.isEmpty {
            MacCardEmptyState(
                icon: "checkmark.circle",
                title: "All clear",
                subtitle: "No pending action items"
            )
        } else {
            let preview = Array(items.prefix(3))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(preview.enumerated()), id: \.element.id) { idx, item in
                    MacActionItemPreviewRow(item: item)
                    if idx < preview.count - 1 {
                        Divider().opacity(0.1).padding(.leading, 18)
                    }
                }

                Button {
                    NotificationCenter.default.post(
                        name: .macSelectRootTab,
                        object: MacRootTab.actionItems.rawValue
                    )
                } label: {
                    HStack(spacing: 3) {
                        Spacer()
                        Text(items.count > 3 ? "View all \(items.count)" : "View all")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MacAppTheme.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(MacAppTheme.accent)
                    }
                    .padding(.top, 6)
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }
        }
    }
}

private struct MacActionItemPreviewRow: View {
    let item: VaultActionItemRecord

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let p = item.priority {
                    Circle()
                        .strokeBorder(ActionItemPriorityColors.color(forStoredPriority: p), lineWidth: 1.5)
                } else {
                    Circle()
                        .strokeBorder(MacAppTheme.secondaryText.opacity(0.35), lineWidth: 1.5)
                }
            }
            .frame(width: 10, height: 10)

            Text(item.title)
                .font(.caption)
                .foregroundStyle(MacAppTheme.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Account Updates Card

private struct MacAccountUpdatesCard: View {
    let unreadCount: Int
    let starredCount: Int
    let onCatchUp: (() -> Void)?
    let onViewMore: (() -> Void)?

    var body: some View {
        MacDashboardCard {
            VStack(alignment: .leading, spacing: 8) {
                MacCardHeader(icon: "envelope", title: "ACCOUNT UPDATES")

                Divider().opacity(0.15)

                HStack(spacing: 8) {
                    MacStatPill(label: "Unread", count: unreadCount, filled: true)
                    MacStatPill(label: "Saved", count: starredCount, filled: false)
                    Spacer()
                }

                Divider().opacity(0.1)

                HStack(spacing: 8) {
                    if let onCatchUp {
                        Button("Catch Up") { onCatchUp() }
                            .buttonStyle(.borderedProminent)
                            .tint(MacAppTheme.accent)
                            .controlSize(.small)
                    }
                    if let onViewMore {
                        Button("View More") { onViewMore() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Spacer()
                }
            }
        }
    }
}

private struct MacStatPill: View {
    let label: String
    let count: Int
    let filled: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(filled ? .black : MacAppTheme.primaryText)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(filled ? Color.black.opacity(0.7) : MacAppTheme.secondaryText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(filled ? MacAppTheme.accent : Color.white.opacity(0.07))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(filled ? Color.clear : Color.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Stories Feed Card

private struct MacStoriesFeedCard: View {
    let stories: [InsightCard]
    let onViewAll: (() -> Void)?

    var body: some View {
        MacDashboardCard {
            VStack(alignment: .leading, spacing: 8) {
                MacCardHeader(
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
            MacCardEmptyState(
                icon: "rectangle.stack",
                title: "No stories yet",
                subtitle: "Stories appear as your newsletters are processed"
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stories.enumerated()), id: \.element.id) { idx, story in
                    MacStoryPreviewRow(story: story)
                    if idx < stories.count - 1 {
                        Divider().opacity(0.1).padding(.leading, 34)
                    }
                }

                if let onViewAll {
                    Button {
                        onViewAll()
                    } label: {
                        HStack(spacing: 3) {
                            Spacer()
                            Text("View all stories")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MacAppTheme.accent)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundStyle(MacAppTheme.accent)
                        }
                        .padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }
            }
        }
    }
}

private struct MacStoryPreviewRow: View {
    let story: InsightCard

    private var initial: String {
        String((story.senderName ?? story.sender).first.map(String.init)?.uppercased() ?? "?")
    }

    private var senderDisplay: String {
        story.senderName?.isEmpty == false ? story.senderName! : story.sender
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                Circle()
                    .fill(MacAppTheme.accent.opacity(0.14))
                    .frame(width: 24, height: 24)
                Text(initial)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MacAppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(senderDisplay)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacAppTheme.secondaryText)
                    .lineLimit(1)
                Text(story.subject)
                    .font(.caption)
                    .foregroundStyle(MacAppTheme.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 9))
                .foregroundStyle(MacAppTheme.secondaryText.opacity(0.3))
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Account section (kept from original)

private struct MacDashboardAccountSection: View {
    let account: EmailAccount
    let unread: Int
    let starred: Int
    let total: Int
    let unreadSenderCount: Int
    var onViewMore: (() -> Void)?
    var onCatchUp: (() -> Void)?

    private var summaryLine: String {
        ["\(unread) unread", "\(starred) starred", "\(total) total"].joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(account.email)
                .font(.body.weight(.semibold))
                .foregroundStyle(MacAppTheme.primaryText)
                .lineLimit(1)

            Text(summaryLine)
                .font(.subheadline)
                .foregroundStyle(MacAppTheme.secondaryText)

            if unreadSenderCount > 0 {
                Text("\(unreadSenderCount) senders with unread")
                    .font(.caption)
                    .foregroundStyle(MacAppTheme.secondaryText.opacity(0.85))
            }

            HStack(spacing: 12) {
                if let onViewMore {
                    Button("View more") { onViewMore() }
                        .buttonStyle(.borderedProminent)
                        .tint(MacAppTheme.accent)
                        .controlSize(.small)
                }

                if let onCatchUp, unread > 0 {
                    Button {
                        onCatchUp()
                    } label: {
                        Label("Catch up", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(MacAppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacAppTheme.cornerRadiusSmall))
    }
}

// MARK: - Upcoming row (kept from original)

private struct MacDashboardUpcomingEventRow: View {
    let event: GoogleCalendarDisplayEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeRange)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MacAppTheme.accent)

            Text(event.title.isEmpty ? "(No title)" : event.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MacAppTheme.primaryText)
                .lineLimit(2)

            Text(event.calendarTitle)
                .font(.caption2)
                .foregroundStyle(MacAppTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var timeRange: String {
        if event.isAllDay {
            return event.start.formatted(date: .abbreviated, time: .omitted) + " · All day"
        }
        let start = event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

// MARK: - Cursor helper

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
