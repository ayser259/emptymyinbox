import Foundation
import SwiftUI

private enum BriefVaultNudge {
    static let userDefaultsKey = "vaultNudgeBriefShown"
}

/// Inline Brief tab: loads cached briefing, runs LLM once per day (or on refresh), persists to UserDefaults and vault.
public struct DailyBriefingTabView: View {
    let allEmails: [EmailListItem]
    let onItemTap: (DailyBriefingItem) -> Void
    let onOpenLLMSettings: () -> Void

    @State private var payload: DailyBriefingPayload?
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var hasLLMKey = false
    @State private var showVaultNudgeAlert = false

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
            } else if !hasLLMKey {
                LLMUpsellView(
                    title: "Unlock AI Summary",
                    subtitle: "Add your selected provider API key to enable the Daily Executive Summary.",
                    actionTitle: "Add API Key",
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
                .disabled(isRefreshing || !hasLLMKey)
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
        .alert("Back up Brief", isPresented: $showVaultNudgeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a Vault in Settings to sync your Daily Briefing to Google Drive or a folder.")
        }
    }

    private func loadOrGenerate(forceRefresh: Bool) async {
        let hasKey = await LLMProviderRouter.shared.hasSelectedProviderAPIKey()
        await MainActor.run {
            hasLLMKey = hasKey
        }

        guard hasKey else {
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

        let ranToday = payload.map { Calendar.current.isDateInToday($0.generatedAt) } ?? false
        if !forceRefresh, ranToday {
            return
        }

        await MainActor.run { isRefreshing = true }
        let built = await DailyBriefingEngine.shared.buildPayload(from: allEmails, sinceDate: nil)
        await persistEverywhere(built)
        await MainActor.run {
            payload = built
            isRefreshing = false
        }
        await maybeVaultNudge()
    }

    private func persistEverywhere(_ p: DailyBriefingPayload) async {
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: DailyBriefingDefaults.persistedPayloadKey)
        }
        UserDefaults.standard.set(Date(), forKey: DailyBriefingDefaults.lastCheckDateKey)
        NotificationCenter.default.post(name: .briefingPayloadDidPersist, object: nil)
        let ready = await MainActor.run { VaultManager.shared.isVaultReady }
        guard ready else { return }
        do {
            try await VaultManager.shared.saveDailyBriefToVault(p)
        } catch {
            logError("Brief: vault save failed: \(error)", category: "Vault")
        }
    }

    private func maybeVaultNudge() async {
        let ready = await MainActor.run { VaultManager.shared.isVaultReady }
        guard !ready else { return }
        let shown = UserDefaults.standard.bool(forKey: BriefVaultNudge.userDefaultsKey)
        guard !shown else { return }
        UserDefaults.standard.set(true, forKey: BriefVaultNudge.userDefaultsKey)
        await MainActor.run {
            showVaultNudgeAlert = true
        }
    }
}
