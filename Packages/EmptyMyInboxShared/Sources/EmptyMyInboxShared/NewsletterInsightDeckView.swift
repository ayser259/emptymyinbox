import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct NewsletterInsightDeckView: View {
    let emails: [EmailListItem]
    let onDiveDeeper: (Int) -> Void
    let onOpenLLMSettings: () -> Void

    @State private var cards: [InsightCard] = []
    @State private var isLoading = true
    @State private var hasKey = false
    @State private var isRefreshingStories = false
    @State private var refreshGeneration = 0
    @State private var refreshTask: Task<Void, Never>?
    @State private var aiStatusMessage: String?

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
                    subtitle: "Add your OpenAI API key to generate personalized stories from newsletters.",
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
        .task {
            scheduleRefreshContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .llmAPIKeyChanged)) { _ in
            scheduleRefreshContent()
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
                        await StoriesFeedStore.shared.dismissStory(storyId: card.id)
                        await MainActor.run {
                            scheduleRefreshContent()
                        }
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

    @MainActor
    private func scheduleRefreshContent() {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task {
            await refreshContent(generation: generation)
        }
    }

    private func refreshContent(generation: Int) async {
        #if os(iOS)
        impact.prepare()
        #endif

        let persistedStories = await StoriesFeedStore.shared.stories()
        guard !Task.isCancelled, isLatestRefresh(generation) else { return }
        await MainActor.run {
            cards = persistedStories
            isLoading = persistedStories.isEmpty
            isRefreshingStories = false
            aiStatusMessage = nil
        }

        let hasAPIKey = await LLMSettingsStore.shared.hasAPIKey()
        var loadedStories: [InsightCard] = persistedStories
        if hasAPIKey {
            let promptStates = await StoriesFeedStore.shared.promptStates()
            let candidates = await InsightEngine.shared.selectUnpromptedCandidates(
                from: emails,
                promptStates: promptStates
            )
            guard !Task.isCancelled, isLatestRefresh(generation) else { return }

            if !candidates.isEmpty {
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

    private func isLatestRefresh(_ generation: Int) -> Bool {
        generation == refreshGeneration
    }
}
