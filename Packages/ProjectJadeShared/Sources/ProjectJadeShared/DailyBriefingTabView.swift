import Foundation
import SwiftUI

/// Inline Brief tab: loads cached briefing, runs LLM once per day (or on refresh), persists to UserDefaults.
public struct DailyBriefingTabView: View {
    let allEmails: [EmailListItem]
    let onItemTap: (DailyBriefingItem) -> Void
    let onOpenLLMSettings: () -> Void

    @State private var payload: DailyBriefingPayload?
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var briefCapability: AIGenerationCapability = .onDeviceUnavailable

    public init(
        allEmails: [EmailListItem],
        onItemTap: @escaping (DailyBriefingItem) -> Void,
        onOpenLLMSettings: @escaping () -> Void
    ) {
        self.allEmails = allEmails
        self.onItemTap = onItemTap
        self.onOpenLLMSettings = onOpenLLMSettings
    }

    public var body: some View {
        ZStack {
            SharedAppTheme.primaryBackground
                #if os(iOS)
                .ignoresSafeArea()
                #endif

            if isLoading {
                ProgressView("Loading briefing…")
                    .tint(SharedAppTheme.accent)
            } else if !briefCapability.allowsGeneration, payload == nil {
                LLMUpsellView(
                    title: briefCapability.upsellTitle,
                    subtitle: briefCapability.upsellSubtitle,
                    actionTitle: briefCapability.upsellActionTitle,
                    onAction: onOpenLLMSettings
                )
            } else if let payload {
                DailyBriefingContent(payload: payload, onItemTap: onItemTap)
            } else {
                VStack(spacing: SharedAppTheme.spacingMedium) {
                    Text("No briefing yet")
                        .font(SharedAppTheme.title3)
                        .foregroundStyle(SharedAppTheme.primaryText)
                    Text("Tap refresh to generate your briefing.")
                        .font(SharedAppTheme.body)
                        .foregroundStyle(SharedAppTheme.secondaryText)
                }
            }
        }
        .navigationTitle("Daily Briefing")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadOrGenerate(forceRefresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isRefreshing || !briefCapability.allowsGeneration)
            }
        }
        .task {
            await loadOrGenerate(forceRefresh: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .llmAPIKeyChanged)) { _ in
            Task { await loadOrGenerate(forceRefresh: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .claudeAPIKeyChanged)) { _ in
            Task { await loadOrGenerate(forceRefresh: false) }
        }
    }

    private func loadOrGenerate(forceRefresh: Bool) async {
        let capability = await LLMProviderRouter.shared.briefGenerationCapability()
        await MainActor.run {
            briefCapability = capability
        }

        if case .missingAPIKey = capability {
            UserDefaults.standard.removeObject(forKey: DailyBriefingDefaults.persistedPayloadKey)
            await MainActor.run {
                isLoading = false
                payload = nil
            }
            return
        }

        if let data = UserDefaults.standard.data(forKey: DailyBriefingDefaults.persistedPayloadKey),
           let cached = try? JSONDecoder().decode(DailyBriefingPayload.self, from: data) {
            await MainActor.run {
                payload = cached
            }
        }

        await MainActor.run {
            isLoading = false
        }

        guard capability.allowsGeneration else {
            return
        }

        let ranToday = payload.map { Calendar.current.isDateInToday($0.generatedAt) } ?? false
        if !forceRefresh, ranToday {
            return
        }

        await MainActor.run { isRefreshing = true }
        let built = await DailyBriefingEngine.shared.buildPayload(from: allEmails, sinceDate: nil)
        await persistLocal(built)
        await MainActor.run {
            payload = built
            isRefreshing = false
        }
    }

    private func persistLocal(_ p: DailyBriefingPayload) async {
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: DailyBriefingDefaults.persistedPayloadKey)
        }
        UserDefaults.standard.set(Date(), forKey: DailyBriefingDefaults.lastCheckDateKey)
        NotificationCenter.default.post(name: .briefingPayloadDidPersist, object: nil)
    }
}
