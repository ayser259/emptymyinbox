import SwiftUI

/// Provider model selection and runtime settings (API keys live under Settings → Keys).
public struct LLMManagementView: View {
    @State private var settings: LLMSettings = .default
    @State private var isSaving = false
    @State private var testResult: String?

    public init() {}

    public var body: some View {
        Form {
            Section {
                Text("Add or update your provider API key under Settings → Keys.")
                    .font(SharedAppTheme.caption)
                    .foregroundStyle(SharedAppTheme.secondaryText)
            } header: {
                Text("API Key")
            }

            Section("Provider") {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: settings.provider) { _, _ in
                    applyProviderModelDefaultsIfNeeded()
                }
            }

            Section("Model Selection") {
                Picker("Default Model", selection: defaultModelBinding) {
                    ForEach(modelOptionsIncludingCurrent(settings.defaultModel), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Picker("Initial Pass Model", selection: initialPassModelBinding) {
                    ForEach(modelOptionsIncludingCurrent(settings.initialPassModel), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Picker("Pro Model", selection: proModelBinding) {
                    ForEach(modelOptionsIncludingCurrent(settings.proModel), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

            }

            Section("Plugin Models") {
                Picker("Brief", selection: briefModelBinding) {
                    ForEach(modelOptionsIncludingCurrent(settings.briefModel), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Picker("Stories", selection: storiesModelBinding) {
                    ForEach(modelOptionsIncludingCurrent(settings.storiesModel), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Picker("Quick Reply", selection: quickReplyModelBinding) {
                    ForEach(modelOptionsIncludingCurrent(settings.quickReplyModel), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }

            Section("Runtime") {
                Stepper(
                    "Request timeout: \(Int(settings.requestTimeoutSeconds))s",
                    value: $settings.requestTimeoutSeconds,
                    in: 10...90,
                    step: 5
                )
                Stepper("Retry attempts: \(settings.maxRetries)", value: $settings.maxRetries, in: 0...4)
            }

            Section {
                Button(isSaving ? "Saving..." : "Save Settings") {
                    Task { await saveSettings() }
                }
                .disabled(isSaving)

                Button("Test Connection") {
                    Task { await testConnection() }
                }
            }

            if let testResult {
                Section("Status") {
                    Text(testResult)
                        .font(SharedAppTheme.caption)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        #endif
        .navigationTitle("LLM Management")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await load()
        }
    }

    private func load() async {
        let loaded = await LLMSettingsStore.shared.currentSettings()
        await MainActor.run {
            settings = loaded
            applyProviderModelDefaultsIfNeeded()
        }
    }

    private func saveSettings() async {
        await MainActor.run { isSaving = true }
        await LLMSettingsStore.shared.updateSettings(settings)
        await load()
        await MainActor.run {
            isSaving = false
            testResult = "Settings saved."
        }
    }

    private func testConnection() async {
        let hasKey: Bool
        switch settings.provider {
        case .openAI:
            hasKey = await LLMSettingsStore.shared.hasAPIKey()
        case .claude:
            hasKey = await ClaudeAPIKeyStore.shared.hasAPIKey()
        }
        guard hasKey else {
            await MainActor.run {
                testResult = "Add a \(settings.provider.displayName) API key under Settings → Keys first."
            }
            return
        }

        let sample = DailyBriefCandidates(
            todayDate: "2026-05-18",
            yesterdayDate: "2026-05-17",
            urgentToday: [
                DailyBriefEmailCandidate(
                    emailId: 1,
                    sender: "calendar@google.com",
                    senderName: "Calendar",
                    subject: "Team sync tomorrow 10am",
                    snippet: "Calendar invite attached",
                    receivedAt: "2026-05-18T09:00:00Z",
                    isRead: false,
                    labels: ["INBOX", "UNREAD"]
                )
            ],
            criticalReminders: [],
            unreadFromYesterday: [],
            receiptsAndTransactions: []
        )
        do {
            switch settings.provider {
            case .openAI:
                _ = try await OpenAIService.shared.generateDailyBrief(candidates: sample)
            case .claude:
                _ = try await ClaudeService.shared.generateDailyBrief(candidates: sample)
            }
            await MainActor.run {
                testResult = "\(settings.provider.displayName) connection successful."
            }
        } catch {
            await MainActor.run {
                testResult = "\(settings.provider.displayName) connection failed: \(error.localizedDescription)"
            }
        }
    }

    private var modelOptions: [String] {
        LLMModelCatalog.models(for: settings.provider)
    }

    private var defaultModelBinding: Binding<String> {
        Binding(
            get: { validModelSelection(for: settings.defaultModel, fallback: LLMModelCatalog.defaults(for: settings.provider).defaultModel) },
            set: { settings.defaultModel = $0 }
        )
    }

    private var initialPassModelBinding: Binding<String> {
        Binding(
            get: { validModelSelection(for: settings.initialPassModel, fallback: LLMModelCatalog.defaults(for: settings.provider).initialPassModel) },
            set: { settings.initialPassModel = $0 }
        )
    }

    private var proModelBinding: Binding<String> {
        Binding(
            get: { validModelSelection(for: settings.proModel, fallback: LLMModelCatalog.defaults(for: settings.provider).proModel) },
            set: { settings.proModel = $0 }
        )
    }

    private var briefModelBinding: Binding<String> {
        Binding(
            get: { validModelSelection(for: settings.briefModel, fallback: LLMModelCatalog.defaults(for: settings.provider).initialPassModel) },
            set: { settings.briefModel = $0 }
        )
    }

    private var storiesModelBinding: Binding<String> {
        Binding(
            get: { validModelSelection(for: settings.storiesModel, fallback: LLMModelCatalog.defaults(for: settings.provider).initialPassModel) },
            set: { settings.storiesModel = $0 }
        )
    }

    private var quickReplyModelBinding: Binding<String> {
        Binding(
            get: { validModelSelection(for: settings.quickReplyModel, fallback: LLMModelCatalog.defaults(for: settings.provider).defaultModel) },
            set: { settings.quickReplyModel = $0 }
        )
    }

    private func validModelSelection(for model: String, fallback: String) -> String {
        LLMModelCatalog.contains(model, provider: settings.provider) ? model : fallback
    }

    private func modelOptionsIncludingCurrent(_ current: String) -> [String] {
        let models = modelOptions
        if models.contains(current) {
            return models
        }
        return [current] + models
    }

    private func applyProviderModelDefaultsIfNeeded() {
        let defaults = LLMModelCatalog.defaults(for: settings.provider)
        if !LLMModelCatalog.contains(settings.defaultModel, provider: settings.provider) {
            settings.defaultModel = defaults.defaultModel
        }
        if !LLMModelCatalog.contains(settings.initialPassModel, provider: settings.provider) {
            settings.initialPassModel = defaults.initialPassModel
        }
        if !LLMModelCatalog.contains(settings.proModel, provider: settings.provider) {
            settings.proModel = defaults.proModel
        }
        if !LLMModelCatalog.contains(settings.briefModel, provider: settings.provider) {
            settings.briefModel = defaults.initialPassModel
        }
        if !LLMModelCatalog.contains(settings.storiesModel, provider: settings.provider) {
            settings.storiesModel = defaults.initialPassModel
        }
        if !LLMModelCatalog.contains(settings.quickReplyModel, provider: settings.provider) {
            settings.quickReplyModel = defaults.defaultModel
        }
    }
}
