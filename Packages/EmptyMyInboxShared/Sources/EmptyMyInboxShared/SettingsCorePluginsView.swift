import SwiftUI

/// Core Plugins: Brief, Stories, Quick Reply — per-feature model/prompt/account controls.
public struct SettingsCorePluginsView: View {
    @ObservedObject private var flags = FeatureFlagsStore.shared

    public init() {}

    public var body: some View {
        Group {
            #if os(macOS)
            Form {
                corePluginsSections
            }
            .formStyle(.grouped)
            #else
            List {
                corePluginsSections
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        .navigationTitle("Core Plugins")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var corePluginsSections: some View {
        Section {
            Toggle(isOn: $flags.isStoriesEnabled) {
                Label("Newsletter Insights", systemImage: "newspaper")
            }
            NavigationLink {
                SettingsPluginModelSettingsView(kind: .stories)
            } label: {
                Label("Model settings", systemImage: "cpu")
            }
            NavigationLink {
                SettingsStoriesInclusionDetailView()
            } label: {
                Label("Mail accounts", systemImage: "person.crop.circle")
            }
            NavigationLink {
                SettingsPluginPromptEditorView(kind: .stories)
            } label: {
                Label("Prompt", systemImage: "text.quote")
            }
        } header: {
            Text("Stories")
        } footer: {
            Text("Story cards from newsletters: pick accounts and edit the generation prompt.")
        }

        Section {
            Toggle(isOn: $flags.isBriefEnabled) {
                Label("Daily Executive Briefing", systemImage: "sun.horizon")
            }
            NavigationLink {
                SettingsPluginModelSettingsView(kind: .brief)
            } label: {
                Label("Model settings", systemImage: "cpu")
            }
            NavigationLink {
                SettingsBriefInclusionDetailView()
            } label: {
                Label("Mail accounts", systemImage: "person.crop.circle")
            }
            NavigationLink {
                SettingsPluginPromptEditorView(kind: .brief)
            } label: {
                Label("Prompt", systemImage: "text.quote")
            }
        } header: {
            Text("Brief")
        } footer: {
            Text("Classifies inbox items for the briefing: pick accounts and adjust the prompt.")
        }

        Section {
            Toggle(isOn: $flags.isQuickReplyEnabled) {
                Label("Quick Reply", systemImage: "arrowshape.turn.up.left")
            }
            NavigationLink {
                SettingsPluginModelSettingsView(kind: .quickReply)
            } label: {
                Label("Model settings", systemImage: "cpu")
            }
            NavigationLink {
                SettingsQuickReplyInclusionDetailView()
            } label: {
                Label("Mail accounts", systemImage: "person.crop.circle")
            }
            NavigationLink {
                SettingsPluginPromptEditorView(kind: .quickReply)
            } label: {
                Label("Prompt", systemImage: "text.quote")
            }
        } header: {
            Text("Quick Reply")
        } footer: {
            Text("Generates suggested email replies. Configure model, eligible accounts, and prompt. API keys are managed under Settings → Keys.")
        }
    }
}

// MARK: - Plugin prompt editor (Brief / Stories)

struct SettingsPluginModelSettingsView: View {
    enum Kind {
        case brief
        case stories
        case quickReply

        var navigationTitle: String {
            switch self {
            case .brief:
                return "Brief · Model Settings"
            case .stories:
                return "Stories · Model Settings"
            case .quickReply:
                return "Quick Reply · Model Settings"
            }
        }

        var description: String {
            switch self {
            case .brief:
                return "Pick the model used when classifying daily briefing items."
            case .stories:
                return "Pick the model used when generating newsletter insight cards."
            case .quickReply:
                return "Pick the model used when generating AI quick-reply drafts."
            }
        }
    }

    let kind: Kind

    @State private var settings: LLMSettings = .default
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isTestingConnection = false
    @State private var statusMessage: String?

    var body: some View {
        Group {
            #if os(macOS)
            Form {
                modelSettingsSections
            }
            .formStyle(.grouped)
            #else
            List {
                modelSettingsSections
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        .navigationTitle(kind.navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var modelSettingsSections: some View {
        Section {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                Picker("Model", selection: selectedModelBinding) {
                    ForEach(modelOptionsIncludingCurrent(selectedModel), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }
        } header: {
            Text("Provider & Model")
        } footer: {
            Text(kind.description)
        }

        Section {
            Button(isSaving ? "Saving..." : "Save Model") {
                Task { await save() }
            }
            .disabled(isLoading || isSaving)

            Button(isTestingConnection ? "Testing..." : "Test Connection") {
                Task { await testConnection() }
            }
            .disabled(isLoading || isTestingConnection)
        }

        if let statusMessage {
            Section("Status") {
                Text(statusMessage)
                    .font(SharedAppTheme.caption)
            }
        }
    }

    private var selectedModel: String {
        switch kind {
        case .brief:
            return settings.briefModel
        case .stories:
            return settings.storiesModel
        case .quickReply:
            return settings.quickReplyModel
        }
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: {
                let defaults = LLMModelCatalog.defaults(for: settings.provider)
                let fallback: String
                switch kind {
                case .brief, .stories:
                    fallback = defaults.initialPassModel
                case .quickReply:
                    fallback = defaults.defaultModel
                }
                return LLMModelCatalog.contains(selectedModel, provider: settings.provider) ? selectedModel : fallback
            },
            set: { newValue in
                switch kind {
                case .brief:
                    settings.briefModel = newValue
                case .stories:
                    settings.storiesModel = newValue
                case .quickReply:
                    settings.quickReplyModel = newValue
                }
            }
        )
    }

    private func modelOptionsIncludingCurrent(_ current: String) -> [String] {
        let options = LLMModelCatalog.models(for: settings.provider)
        if options.contains(current) {
            return options
        }
        return [current] + options
    }

    private func load() async {
        let loaded = await LLMSettingsStore.shared.currentSettings()
        await MainActor.run {
            settings = loaded
            isLoading = false
        }
    }

    private func save() async {
        await MainActor.run {
            isSaving = true
            statusMessage = nil
        }
        await LLMSettingsStore.shared.updateSettings(settings)
        let loaded = await LLMSettingsStore.shared.currentSettings()
        await MainActor.run {
            settings = loaded
            isSaving = false
            statusMessage = "Model saved."
        }
    }

    private func testConnection() async {
        await MainActor.run {
            isTestingConnection = true
            statusMessage = nil
        }

        // Persist current picker selection so the request uses the exact feature model.
        await LLMSettingsStore.shared.updateSettings(settings)
        let hasKey = await LLMProviderRouter.shared.hasSelectedProviderAPIKey()
        guard hasKey else {
            await MainActor.run {
                statusMessage = "Add a \(settings.provider.displayName) API key under Settings → Keys first."
                isTestingConnection = false
            }
            return
        }

        do {
            switch kind {
            case .brief:
                _ = try await LLMProviderRouter.shared.classifyBriefingItem(
                    subject: "Leadership sync tomorrow 10am",
                    snippet: "Calendar invite attached",
                    sender: "calendar@company.com"
                )
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
                statusMessage = "Connection successful."
                isTestingConnection = false
            }
        } catch {
            await MainActor.run {
                statusMessage = "Connection failed: \(error.localizedDescription)"
                isTestingConnection = false
            }
        }
    }
}

struct SettingsPluginPromptEditorView: View {
    enum Kind {
        case brief
        case stories
        case quickReply

        var navigationTitle: String {
            switch self {
            case .brief: return "Brief · Prompt"
            case .stories: return "Stories · Prompt"
            case .quickReply: return "Quick Reply · Prompt"
            }
        }

        var systemPromptDescription: String {
            switch self {
            case .brief:
                return "Sets behavior for the assistant when classifying a single email (JSON output, safety rules)."
            case .stories:
                return "Sets behavior when turning newsletter content into story cards (JSON output, safety rules)."
            case .quickReply:
                return "Sets behavior when drafting short suggested email replies."
            }
        }
    }

    let kind: Kind

    @State private var systemPrompt = ""
    @State private var userPrompt = ""
    @State private var showMissingPlaceholderAlert = false
    @State private var showResetConfirm = false

    var body: some View {
        Group {
            #if os(macOS)
            Form {
                promptEditorSections
            }
            .formStyle(.grouped)
            #else
            List {
                promptEditorSections
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        .navigationTitle(kind.navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
            }
        }
        .task {
            await load()
        }
        .alert("Missing placeholder", isPresented: $showMissingPlaceholderAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add \(PluginPromptPlaceholder.inputJSON) to the user message template so the app can inject email data.")
        }
        .confirmationDialog("Reset prompts to the built-in defaults?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                Task { await resetToDefaults() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var promptEditorSections: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "gearshape.2")
                        .foregroundStyle(SharedAppTheme.secondaryText)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System prompt")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SharedAppTheme.primaryText)
                        Text("Sets assistant behavior, constraints, and output style.")
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(SharedAppTheme.secondaryText)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("User message template")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SharedAppTheme.primaryText)
                        Text("Task instructions + \(PluginPromptPlaceholder.inputJSON) payload placeholder.")
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Text("Prompt Components")
        } footer: {
            Text("Both prompts are editable below and saved per feature.")
        }

        Section {
            TextEditor(text: $systemPrompt)
                .font(SharedAppTheme.body)
                .foregroundStyle(SharedAppTheme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(SharedAppTheme.secondaryBackground.opacity(0.45))
                .frame(minHeight: 88)
                .clipShape(RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusSmall, style: .continuous))
        } header: {
            Text("System prompt")
        } footer: {
            Text(systemPromptDescription)
        }

        Section {
            TextEditor(text: $userPrompt)
                .font(SharedAppTheme.body)
                .foregroundStyle(SharedAppTheme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(SharedAppTheme.secondaryBackground.opacity(0.45))
                .frame(minHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusSmall, style: .continuous))
        } header: {
            Text("User message template")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Include exactly one \(PluginPromptPlaceholder.inputJSON) where the app should insert the email JSON payload. If it is missing, the app appends a JSON block at the end."
                )
                Button("Reset to defaults", role: .destructive) {
                    showResetConfirm = true
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var systemPromptDescription: String {
        kind.systemPromptDescription
    }

    private func load() async {
        let pair: (String, String)
        switch kind {
        case .brief:
            pair = await PluginPromptStore.shared.briefPromptsForEditing()
        case .stories:
            pair = await PluginPromptStore.shared.storiesPromptsForEditing()
        case .quickReply:
            pair = await PluginPromptStore.shared.quickReplyPromptsForEditing()
        }
        await MainActor.run {
            systemPrompt = pair.0
            userPrompt = pair.1
        }
    }

    private func save() {
        guard userPrompt.contains(PluginPromptPlaceholder.inputJSON) else {
            showMissingPlaceholderAlert = true
            return
        }
        Task {
            switch kind {
            case .brief:
                await PluginPromptStore.shared.saveBriefPrompts(system: systemPrompt, userTemplate: userPrompt)
            case .stories:
                await PluginPromptStore.shared.saveStoriesPrompts(system: systemPrompt, userTemplate: userPrompt)
            case .quickReply:
                await PluginPromptStore.shared.saveQuickReplyPrompts(system: systemPrompt, userTemplate: userPrompt)
            }
        }
    }

    private func resetToDefaults() async {
        switch kind {
        case .brief:
            await PluginPromptStore.shared.resetBriefPromptsToDefaults()
        case .stories:
            await PluginPromptStore.shared.resetStoriesPromptsToDefaults()
        case .quickReply:
            await PluginPromptStore.shared.resetQuickReplyPromptsToDefaults()
        }
        await load()
    }
}

// MARK: - Stories — Newsletter Insights only

struct SettingsStoriesInclusionDetailView: View {
    @State private var inclusions: [FeatureAccountInclusion] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            #if os(macOS)
            Form {
                storiesInclusionSections
            }
            .formStyle(.grouped)
            #else
            List {
                storiesInclusionSections
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        .navigationTitle("Newsletter accounts")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var storiesInclusionSections: some View {
        if isLoading {
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        } else if inclusions.isEmpty {
            Section {
                Text("No connected accounts.")
                    .foregroundStyle(SharedAppTheme.secondaryText)
            }
        } else {
            ForEach(inclusions) { inclusion in
                Section(inclusion.accountEmail) {
                    Toggle(
                        "Include in Newsletter Insights",
                        isOn: bindingForInsights(email: inclusion.accountEmail)
                    )

                    Button {
                        Task {
                            await AccountInclusionStore.shared.setPrimaryNewsletterAddress(accountEmail: inclusion.accountEmail)
                            await load()
                        }
                    } label: {
                        HStack {
                            Text("Set as Newsletter Address")
                            Spacer()
                            if inclusion.isPrimaryNewsletterAddress {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SharedAppTheme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        await AccountInclusionStore.shared.refreshFromConnectedAccounts()
        let loaded = await AccountInclusionStore.shared.allInclusions()
        await MainActor.run {
            inclusions = loaded
            isLoading = false
        }
    }

    private func bindingForInsights(email: String) -> Binding<Bool> {
        Binding(
            get: {
                inclusions.first(where: { $0.accountEmail.caseInsensitiveCompare(email) == .orderedSame })?.includeInNewsletterInsights ?? true
            },
            set: { newValue in
                Task {
                    await AccountInclusionStore.shared.setIncludeInNewsletterInsights(accountEmail: email, isIncluded: newValue)
                    await load()
                }
            }
        )
    }
}

// MARK: - Brief — Daily Briefing only

struct SettingsBriefInclusionDetailView: View {
    @State private var inclusions: [FeatureAccountInclusion] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            #if os(macOS)
            Form {
                briefInclusionSections
            }
            .formStyle(.grouped)
            #else
            List {
                briefInclusionSections
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        .navigationTitle("Briefing accounts")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var briefInclusionSections: some View {
        if isLoading {
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        } else if inclusions.isEmpty {
            Section {
                Text("No connected accounts.")
                    .foregroundStyle(SharedAppTheme.secondaryText)
            }
        } else {
            ForEach(inclusions) { inclusion in
                Section(inclusion.accountEmail) {
                    Toggle(
                        "Include in Daily Briefing",
                        isOn: bindingForDailyBriefing(email: inclusion.accountEmail)
                    )
                }
            }
        }
    }

    private func load() async {
        await AccountInclusionStore.shared.refreshFromConnectedAccounts()
        let loaded = await AccountInclusionStore.shared.allInclusions()
        await MainActor.run {
            inclusions = loaded
            isLoading = false
        }
    }

    private func bindingForDailyBriefing(email: String) -> Binding<Bool> {
        Binding(
            get: {
                inclusions.first(where: { $0.accountEmail.caseInsensitiveCompare(email) == .orderedSame })?.includeInDailyBriefing ?? true
            },
            set: { newValue in
                Task {
                    await AccountInclusionStore.shared.setIncludeInDailyBriefing(accountEmail: email, isIncluded: newValue)
                    await load()
                }
            }
        )
    }
}

struct SettingsQuickReplyInclusionDetailView: View {
    @State private var inclusions: [FeatureAccountInclusion] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            #if os(macOS)
            Form {
                quickReplyInclusionSections
            }
            .formStyle(.grouped)
            #else
            List {
                quickReplyInclusionSections
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        .navigationTitle("Quick Reply accounts")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var quickReplyInclusionSections: some View {
        if isLoading {
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        } else if inclusions.isEmpty {
            Section {
                Text("No connected accounts.")
                    .foregroundStyle(SharedAppTheme.secondaryText)
            }
        } else {
            ForEach(inclusions) { inclusion in
                Section(inclusion.accountEmail) {
                    Toggle(
                        "Enable Quick Reply",
                        isOn: bindingForQuickReply(email: inclusion.accountEmail)
                    )
                }
            }
        }
    }

    private func load() async {
        await AccountInclusionStore.shared.refreshFromConnectedAccounts()
        let loaded = await AccountInclusionStore.shared.allInclusions()
        await MainActor.run {
            inclusions = loaded
            isLoading = false
        }
    }

    private func bindingForQuickReply(email: String) -> Binding<Bool> {
        Binding(
            get: {
                inclusions.first(where: { $0.accountEmail.caseInsensitiveCompare(email) == .orderedSame })?.includeInQuickReply ?? true
            },
            set: { newValue in
                Task {
                    await AccountInclusionStore.shared.setIncludeInQuickReply(accountEmail: email, isIncluded: newValue)
                    await load()
                }
            }
        )
    }
}
