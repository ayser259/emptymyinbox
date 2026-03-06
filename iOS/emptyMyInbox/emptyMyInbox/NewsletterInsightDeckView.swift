import SwiftUI
import UIKit

struct NewsletterInsightDeckView: View {
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

    private let impact = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            AppTheme.primaryBackground
                .ignoresSafeArea()

            if isLoading {
                ProgressView("Building stories...")
                    .tint(AppTheme.accent)
            } else if !hasKey {
                LLMUpsellView(
                    title: "Unlock Stories",
                    subtitle: "Add your OpenAI API key to generate personalized stories from newsletters.",
                    actionTitle: "Add API Key",
                    onAction: onOpenLLMSettings
                )
            } else if cards.isEmpty {
                VStack(spacing: AppTheme.spacingMedium) {
                    Text("No stories right now")
                        .font(AppTheme.title3)
                        .primaryText()
                    Text("No new newsletter stories since your last visit.")
                        .font(AppTheme.body)
                        .secondaryText()
                    if let aiStatusMessage {
                        Text(aiStatusMessage)
                            .font(AppTheme.caption)
                            .foregroundColor(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.spacingLarge)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: AppTheme.spacingMedium) {
                        HStack {
                            Text("\(cards.count) stories")
                                .font(AppTheme.headline)
                                .foregroundColor(AppTheme.accent)
                            if isRefreshingStories {
                                Text("Generating...")
                                    .font(AppTheme.caption)
                                    .foregroundColor(AppTheme.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(.top, AppTheme.spacingSmall)
                        if let aiStatusMessage {
                            Text(aiStatusMessage)
                                .font(AppTheme.caption)
                                .foregroundColor(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ForEach(cards) { card in
                            insightCard(card)
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingMedium)
                }
                .padding(.bottom, AppTheme.spacingLarge)
            }
        }
        .navigationTitle("Stories")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            scheduleRefreshContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .llmAPIKeyChanged)) { _ in
            scheduleRefreshContent()
        }
    }

    private func insightCard(_ card: InsightCard) -> some View {
        return VStack(alignment: .leading, spacing: AppTheme.spacingMedium) {
            HStack {
                Text("#\(card.theme.tag)")
                    .font(AppTheme.caption)
                    .foregroundColor(AppTheme.accent)
                Text(card.senderName ?? card.sender)
                    .font(AppTheme.caption)
                    .secondaryText()
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
                        .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }

            Text(card.subject)
                .font(AppTheme.title3)
                .primaryText()

            Text(card.summary)
                .font(AppTheme.body)
                .secondaryText()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(card.keyPoints.prefix(3), id: \.self) { point in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .secondaryText()
                        Text(point)
                            .font(AppTheme.caption)
                            .secondaryText()
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: AppTheme.spacingSmall) {
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
                .tint(AppTheme.accent)
            }
        }
        .padding(AppTheme.spacingMedium)
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(AppTheme.secondaryBackground)
        .cornerRadius(AppTheme.cornerRadiusLarge)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
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

        await MainActor.run {
            impact.impactOccurred()
        }
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
        impact.prepare()

        // Show persisted stories immediately to avoid blocking UX on re-entry.
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

            // If there is nothing new, skip LLM calls entirely.
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
