import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum StoriesSubRoute: Hashable {
    case bookmarked
}

private enum StoriesVaultNudge {
    static let userDefaultsKey = "vaultNudgeStoriesShown"
}

public struct NewsletterInsightDeckView: View {
    let emails: [EmailListItem]
    let onDiveDeeper: (Int) -> Void
    let onOpenLLMSettings: () -> Void

    @State private var cards: [InsightCard] = []
    @State private var bookmarkedIds: Set<Int> = []
    @State private var isLoading = true
    @State private var hasKey = false
    @State private var isRefreshingStories = false
    @State private var refreshGeneration = 0
    @State private var refreshTask: Task<Void, Never>?
    @State private var aiStatusMessage: String?
    @State private var showVaultNudgeAlert = false

    #if os(iOS)
    private let impact = UIImpactFeedbackGenerator(style: .light)
    #endif

    public init(
        emails: [EmailListItem],
        onDiveDeeper: @escaping (Int) -> Void,
        onOpenLLMSettings: @escaping () -> Void
    ) {
        self.emails = emails
        self.onDiveDeeper = onDiveDeeper
        self.onOpenLLMSettings = onOpenLLMSettings
    }

    public var body: some View {
        ZStack {
            SharedAppTheme.primaryBackground
                #if os(iOS)
                .ignoresSafeArea()
                #endif

            if isLoading {
                ProgressView("Building stories...")
                    .tint(SharedAppTheme.accent)
            } else if !hasKey {
                LLMUpsellView(
                    title: "Unlock Stories",
                    subtitle: "Add your selected provider API key to generate personalized stories from newsletters.",
                    actionTitle: "Add API Key",
                    onAction: onOpenLLMSettings
                )
            } else if cards.isEmpty {
                VStack(spacing: SharedAppTheme.spacingMedium) {
                    Text("No stories right now")
                        .font(SharedAppTheme.title3)
                        .foregroundStyle(SharedAppTheme.primaryText)
                    Text("No new newsletter stories since your last visit.")
                        .font(SharedAppTheme.body)
                        .foregroundStyle(SharedAppTheme.secondaryText)
                    if let aiStatusMessage {
                        Text(aiStatusMessage)
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, SharedAppTheme.spacingLarge)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: SharedAppTheme.spacingMedium) {
                        HStack {
                            Text("\(cards.count) stories")
                                .font(SharedAppTheme.headline)
                                .foregroundStyle(SharedAppTheme.accent)
                            if isRefreshingStories {
                                Text("Generating...")
                                    .font(SharedAppTheme.caption)
                                    .foregroundStyle(SharedAppTheme.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(.top, SharedAppTheme.spacingSmall)
                        if let aiStatusMessage {
                            Text(aiStatusMessage)
                                .font(SharedAppTheme.caption)
                                .foregroundStyle(SharedAppTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ForEach(cards) { card in
                            insightCard(card)
                        }
                    }
                    .padding(.horizontal, SharedAppTheme.spacingMedium)
                }
                .padding(.bottom, SharedAppTheme.spacingLarge)
            }
        }
        .navigationTitle("Stories")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    scheduleRefreshContent(forceRefresh: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isRefreshingStories || !hasKey)
                NavigationLink(value: StoriesSubRoute.bookmarked) {
                    Image(systemName: "bookmark.fill")
                }
            }
        }
        .navigationDestination(for: StoriesSubRoute.self) { route in
            switch route {
            case .bookmarked:
                StoriesBookmarkedDeckView(onDiveDeeper: onDiveDeeper)
            }
        }
        .task {
            scheduleRefreshContent(forceRefresh: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .llmAPIKeyChanged)) { _ in
            scheduleRefreshContent(forceRefresh: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .claudeAPIKeyChanged)) { _ in
            scheduleRefreshContent(forceRefresh: false)
        }
        .alert("Back up Stories", isPresented: $showVaultNudgeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a Vault in Settings to sync your Stories to Google Drive or a folder.")
        }
    }

    private func insightCard(_ card: InsightCard) -> some View {
        VStack(alignment: .leading, spacing: SharedAppTheme.spacingMedium) {
            HStack {
                Text("#\(card.theme.tag)")
                    .font(SharedAppTheme.caption)
                    .foregroundStyle(SharedAppTheme.accent)
                Text(card.senderName ?? card.sender)
                    .font(SharedAppTheme.caption)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                Spacer()
                Button {
                    Task {
                        let isBm = await StoriesFeedStore.shared.isBookmarked(storyId: card.id)
                        if isBm {
                            await StoriesFeedStore.shared.unbookmarkStory(storyId: card.id)
                        } else {
                            await StoriesFeedStore.shared.bookmarkStory(storyId: card.id)
                        }
                        await reloadBookmarkIds()
                        let s = await StoriesFeedStore.shared.stories()
                        await MainActor.run { cards = s }
                    }
                } label: {
                    Image(systemName: bookmarkedIds.contains(card.id) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SharedAppTheme.accent)
                }
                .buttonStyle(.plain)
                Button {
                    Task {
                        await StoriesFeedStore.shared.markReviewed(storyId: card.id)
                        let s = await StoriesFeedStore.shared.stories()
                        await MainActor.run { cards = s }
                    }
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SharedAppTheme.accent)
                }
                .buttonStyle(.plain)
            }

            Text(card.subject)
                .font(SharedAppTheme.title3)
                .foregroundStyle(SharedAppTheme.primaryText)

            Text(card.summary)
                .font(SharedAppTheme.body)
                .foregroundStyle(SharedAppTheme.secondaryText)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(card.keyPoints.prefix(3), id: \.self) { point in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundStyle(SharedAppTheme.secondaryText)
                        Text(point)
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: SharedAppTheme.spacingSmall) {
                Button("See Less (-)") {
                    Task { await applyFeedback(.less, for: card) }
                }
                .buttonStyle(.bordered)

                Button("See More (+)") {
                    Task { await applyFeedback(.more, for: card) }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Dive Deeper") {
                    onDiveDeeper(card.emailId)
                }
                .buttonStyle(.borderedProminent)
                .tint(SharedAppTheme.accent)
            }
        }
        .padding(SharedAppTheme.spacingMedium)
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(SharedAppTheme.secondaryBackground)
        .cornerRadius(SharedAppTheme.cornerRadiusLarge)
        .overlay(
            RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusLarge)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func applyFeedback(_ type: InterestSignalType, for card: InsightCard) async {
        let signal = InterestSignal(
            timestamp: Date(),
            signalType: type,
            themeTag: card.theme.tag,
            sender: card.sender
        )
        await InterestProfileStore.shared.applySignal(signal)

        #if os(iOS)
        await MainActor.run {
            impact.impactOccurred()
        }
        #endif
    }

    private func reloadBookmarkIds() async {
        let ids = await StoriesFeedStore.shared.bookmarkedStoryIdSet()
        await MainActor.run {
            bookmarkedIds = ids
        }
    }

    @MainActor
    private func scheduleRefreshContent(forceRefresh: Bool) {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task {
            await refreshContent(generation: generation, forceRefresh: forceRefresh)
        }
    }

    private func refreshContent(generation: Int, forceRefresh: Bool) async {
        #if os(iOS)
        impact.prepare()
        #endif

        let persistedStories = await StoriesFeedStore.shared.stories()
        await reloadBookmarkIds()
        guard !Task.isCancelled, isLatestRefresh(generation) else { return }
        await MainActor.run {
            cards = persistedStories
            isLoading = persistedStories.isEmpty
            isRefreshingStories = false
            aiStatusMessage = nil
        }

        let hasAPIKey = await LLMProviderRouter.shared.hasSelectedProviderAPIKey()
        var loadedStories: [InsightCard] = persistedStories
        if hasAPIKey {
            let promptStates = await StoriesFeedStore.shared.promptStates()
            let candidates = await InsightEngine.shared.selectUnpromptedCandidates(
                from: emails,
                promptStates: promptStates
            )
            guard !Task.isCancelled, isLatestRefresh(generation) else { return }

            let lastGen = await StoriesFeedStore.shared.lastGeneratedAt()
            let ranToday = lastGen.map { Calendar.current.isDateInToday($0) } ?? false
            let shouldRunLLM = !candidates.isEmpty && (forceRefresh || !ranToday)

            if shouldRunLLM {
                await MainActor.run {
                    isRefreshingStories = true
                }
                let batch = await InsightEngine.shared.generateBatch(from: candidates)
                guard !Task.isCancelled, isLatestRefresh(generation) else { return }
                for outcome in batch.outcomes {
                    await StoriesFeedStore.shared.applyPromptOutcome(outcome)
                }
                if !batch.cards.isEmpty {
                    await StoriesFeedStore.shared.appendStories(batch.cards)
                    loadedStories = await StoriesFeedStore.shared.stories()
                }
                let anyNonFailure = batch.outcomes.contains { outcome in
                    switch outcome.result {
                    case .failed:
                        return false
                    case .success, .empty:
                        return true
                    }
                }
                if anyNonFailure {
                    await StoriesFeedStore.shared.setLastGeneratedAt(Date())
                    await maybeOfferVaultNudgeAfterGeneration()
                }
                await MainActor.run {
                    isRefreshingStories = false
                    if batch.fallbackCount > 0 {
                        aiStatusMessage = "AI was unavailable for some newsletters. Showing quick fallback summaries."
                    } else {
                        aiStatusMessage = nil
                    }
                }
            }
        }
        await MainActor.run {
            hasKey = hasAPIKey
            cards = loadedStories
            isLoading = false
            isRefreshingStories = false
        }
    }

    private func maybeOfferVaultNudgeAfterGeneration() async {
        let ready = await MainActor.run { VaultManager.shared.isVaultReady }
        guard !ready else { return }
        let shown = UserDefaults.standard.bool(forKey: StoriesVaultNudge.userDefaultsKey)
        guard !shown else { return }
        UserDefaults.standard.set(true, forKey: StoriesVaultNudge.userDefaultsKey)
        await MainActor.run {
            showVaultNudgeAlert = true
        }
    }

    private func isLatestRefresh(_ generation: Int) -> Bool {
        generation == refreshGeneration
    }
}

// MARK: - Bookmarked

public struct StoriesBookmarkedDeckView: View {
    let onDiveDeeper: (Int) -> Void

    @State private var cards: [InsightCard] = []

    public init(onDiveDeeper: @escaping (Int) -> Void) {
        self.onDiveDeeper = onDiveDeeper
    }

    public var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView(
                    "No bookmarks",
                    systemImage: "bookmark",
                    description: Text("Bookmark stories from the main feed to keep them here.")
                )
            } else {
                ScrollView {
                    VStack(spacing: SharedAppTheme.spacingMedium) {
                        ForEach(cards) { card in
                            bookmarkedCard(card)
                        }
                    }
                    .padding(.horizontal, SharedAppTheme.spacingMedium)
                }
            }
        }
        .navigationTitle("Bookmarked")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await load()
        }
    }

    private func bookmarkedCard(_ card: InsightCard) -> some View {
        VStack(alignment: .leading, spacing: SharedAppTheme.spacingMedium) {
            HStack {
                Text("#\(card.theme.tag)")
                    .font(SharedAppTheme.caption)
                    .foregroundStyle(SharedAppTheme.accent)
                Spacer()
                Button {
                    Task {
                        await StoriesFeedStore.shared.unbookmarkStory(storyId: card.id)
                        await load()
                    }
                } label: {
                    Image(systemName: "bookmark.slash")
                        .foregroundStyle(SharedAppTheme.accent)
                }
                .buttonStyle(.plain)
            }
            Text(card.subject)
                .font(SharedAppTheme.title3)
                .foregroundStyle(SharedAppTheme.primaryText)
            Text(card.summary)
                .font(SharedAppTheme.body)
                .foregroundStyle(SharedAppTheme.secondaryText)
            Button("Dive Deeper") {
                onDiveDeeper(card.emailId)
            }
            .buttonStyle(.borderedProminent)
            .tint(SharedAppTheme.accent)
        }
        .padding(SharedAppTheme.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SharedAppTheme.secondaryBackground)
        .cornerRadius(SharedAppTheme.cornerRadiusLarge)
    }

    private func load() async {
        let list = await StoriesFeedStore.shared.bookmarkedStories()
        await MainActor.run {
            cards = list
        }
    }
}
