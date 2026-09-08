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
                    ForEach(LLMProvider.cloudProviders, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: settings.provider) { _, _ in
                    applyCloudProviderModelDefaultsIfNeeded()
                }
            }

            Section("Model Selection") {
                Picker("Default Model", selection: defaultModelBinding) {
                    ForEach(modelOptionsIncludingCurrent(settings.defaultModel, provider: settings.provider), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Picker("Initial Pass Model", selection: initialPassModelBinding) {
                    ForEach(modelOptionsIncludingCurrent(settings.initialPassModel, provider: settings.provider), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Picker("Pro Model", selection: proModelBinding) {
                    ForEach(modelOptionsIncludingCurrent(settings.proModel, provider: settings.provider), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

            }

            Section {
                pluginProviderSection(
                    title: "Brief Provider",
                    provider: $settings.briefProvider,
                    model: $settings.briefModel
                )
                pluginProviderSection(
                    title: "Stories Provider",
                    provider: $settings.storiesProvider,
                    model: $settings.storiesModel
                )
                pluginProviderSection(
                    title: "Quick Reply Provider",
                    provider: $settings.quickReplyProvider,
                    model: $settings.quickReplyModel
                )
            } header: {
                Text("Plugin Models")
            } footer: {
                Text("Brief, Stories, and Quick Reply default to On Device (Apple Intelligence). Switch to a cloud provider if you prefer BYO models.")
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

                Button("Test Brief Connection") {
                    Task { await testPluginConnection(kind: .brief) }
                }
                Button("Test Stories Connection") {
                    Task { await testPluginConnection(kind: .stories) }
                }
                Button("Test Quick Reply Connection") {
                    Task { await testPluginConnection(kind: .quickReply) }
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

    @ViewBuilder
    private func pluginProviderSection(
        title: String,
        provider: Binding<LLMProvider>,
        model: Binding<String>
    ) -> some View {
        Picker(title, selection: provider) {
            ForEach(LLMProvider.briefProviders, id: \.self) { option in
                Text(option.displayName).tag(option)
            }
        }
        .onChange(of: provider.wrappedValue) { _, newProvider in
            let defaults = LLMModelCatalog.defaults(for: newProvider)
            model.wrappedValue = defaults.defaultModel
        }

        if provider.wrappedValue == .onDevice {
            LabeledContent("\(title) Model") {
                Text("Apple Intelligence")
                    .foregroundStyle(SharedAppTheme.secondaryText)
            }
        } else {
            Picker("\(title) Model", selection: model) {
                ForEach(modelOptionsIncludingCurrent(model.wrappedValue, provider: provider.wrappedValue), id: \.self) { option in
                    Text(LLMModelCatalog.displayName(for: option, provider: provider.wrappedValue)).tag(option)
                }
            }
        }
    }

    private enum PluginTestKind {
        case brief
        case stories
        case quickReply
    }

    private func load() async {
        let loaded = await LLMSettingsStore.shared.currentSettings()
        await MainActor.run {
            settings = loaded
            applyCloudProviderModelDefaultsIfNeeded()
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

    private func testPluginConnection(kind: PluginTestKind) async {
        await LLMSettingsStore.shared.updateSettings(settings)

        let provider: LLMProvider
        switch kind {
        case .brief:
            provider = settings.briefProvider
        case .stories:
            provider = settings.storiesProvider
        case .quickReply:
            provider = settings.quickReplyProvider
        }

        if provider == .onDevice {
            do {
                switch kind {
                case .brief:
                    _ = try await OnDeviceAIService.shared.generateDailyBrief(candidates: briefSample)
                case .stories:
                    _ = try await OnDeviceAIService.shared.summarizeNewsletterStories(
                        subject: "Weekly Product Digest",
                        snippet: "Top product and AI stories this week.",
                        sender: "newsletter@example.com",
                        body: nil,
                        preferenceContext: "preferredThemes=AI,Product"
                    )
                case .quickReply:
                    _ = try await OnDeviceAIService.shared.quickReply(
                        subject: "Can we move this meeting?",
                        sender: "teammate@example.com",
                        snippet: "Would Thursday work for you instead?",
                        body: "Hey, can we move our meeting to Thursday afternoon?",
                        userAsk: "Say yes and offer 2pm as an option."
                    )
                }
                await MainActor.run {
                    testResult = "Apple Intelligence is available for \(kindLabel(kind))."
                }
            } catch {
                await MainActor.run {
                    testResult = error.localizedDescription
                }
            }
            return
        }

        let hasKey = await LLMProviderRouter.shared.hasAPIKey(for: provider)
        guard hasKey else {
            await MainActor.run {
                testResult = "Add a \(provider.displayName) API key under Settings → Keys first."
            }
            return
        }

        do {
            switch kind {
            case .brief:
                _ = try await LLMProviderRouter.shared.generateDailyBrief(candidates: briefSample)
            case .stories:
                _ = try await LLMProviderRouter.shared.summarizeNewsletterStories(
                    subject: "Weekly Product Digest",
                    snippet: "Top product and AI stories this week.",
                    sender: "newsletter@example.com",
                    body: nil,
                    preferenceContext: "preferredThemes=AI,Product"
                )
            case .quickReply:
                _ = try await LLMProviderRouter.shared.quickReply(
                    subject: "Can we move this meeting?",
                    sender: "teammate@example.com",
                    snippet: "Would Thursday work for you instead?",
                    body: "Hey, can we move our meeting to Thursday afternoon?",
                    userAsk: "Say yes and offer 2pm as an option."
                )
            }
            await MainActor.run {
                testResult = "\(provider.displayName) \(kindLabel(kind)) connection successful."
            }
        } catch {
            await MainActor.run {
                testResult = "\(provider.displayName) \(kindLabel(kind)) connection failed: \(error.localizedDescription)"
            }
        }
    }

    private var briefSample: DailyBriefCandidates {
        DailyBriefCandidates(
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
    }

    private func kindLabel(_ kind: PluginTestKind) -> String {
        switch kind {
        case .brief: return "Brief"
        case .stories: return "Stories"
        case .quickReply: return "Quick Reply"
        }
    }

    private var defaultModelBinding: Binding<String> {
        Binding(
            get: { validModelSelection(for: settings.defaultModel, provider: settings.provider, fallback: LLMModelCatalog.defaults(for: settings.provider).defaultModel) },
            set: { settings.defaultModel = $0 }
        )
    }

    private var initialPassModelBinding: Binding<String> {
        Binding(
            get: { validModelSelection(for: settings.initialPassModel, provider: settings.provider, fallback: LLMModelCatalog.defaults(for: settings.provider).initialPassModel) },
            set: { settings.initialPassModel = $0 }
        )
    }

    private var proModelBinding: Binding<String> {
        Binding(
            get: { validModelSelection(for: settings.proModel, provider: settings.provider, fallback: LLMModelCatalog.defaults(for: settings.provider).proModel) },
            set: { settings.proModel = $0 }
        )
    }

    private func validModelSelection(for model: String, provider: LLMProvider, fallback: String) -> String {
        LLMModelCatalog.contains(model, provider: provider) ? model : fallback
    }

    private func modelOptionsIncludingCurrent(_ current: String, provider: LLMProvider) -> [String] {
        let models = LLMModelCatalog.models(for: provider)
        if models.contains(current) {
            return models
        }
        return [current] + models
    }

    private func applyCloudProviderModelDefaultsIfNeeded() {
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
    }
}
