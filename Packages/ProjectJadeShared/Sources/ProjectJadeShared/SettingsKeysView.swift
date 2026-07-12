import SwiftUI

/// API keys for OpenAI, Google Gemini, and Anthropic Claude (shared iOS + macOS).
public struct SettingsKeysView: View {
    @State private var openAIKey = ""
    @State private var geminiKey = ""
    @State private var claudeKey = ""

    @State private var openAIStatus: LLMAPIKeyStatus?
    @State private var geminiStatus: LLMAPIKeyStatus?
    @State private var claudeStatus: LLMAPIKeyStatus?

    @State private var openAIMutation = false
    @State private var geminiMutation = false
    @State private var claudeMutation = false

    public init() {}

    public var body: some View {
        Group {
            #if os(iOS)
            List {
                keysSections
            }
            #else
            Form {
                keysSections
            }
            .formStyle(.grouped)
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        .navigationTitle("Keys")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await refreshAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .llmAPIKeyChanged)) { _ in
            Task { await refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .claudeAPIKeyChanged)) { _ in
            Task { await refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .geminiAPIKeyChanged)) { _ in
            Task { await refreshAll() }
        }
    }

    /// Placeholders inside `SecureField` render in the row’s leading “label” lane and clip on narrow widths;
    /// explicit labels above an empty field avoid truncation (Settings → Keys on iPhone / split view).
    @ViewBuilder
    private var keysSections: some View {
        Section {
            APIKeyPresenceIndicator(status: openAIStatus)

            apiKeyField(
                label: "Enter new key",
                accessibilityLabel: "OpenAI API key",
                hint: "Keys typically start with sk-.",
                text: $openAIKey
            )

            HStack {
                Button("Save") {
                    Task { await saveOpenAI() }
                }
                .disabled(openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || openAIMutation)

                Button("Clear", role: .destructive) {
                    Task { await clearOpenAI() }
                }
                .disabled(openAIMutation || openAIStatus == nil)
            }
        } header: {
            Text("OpenAI")
        } footer: {
            Text("Used by the app’s OpenAI integration (LLM Management, Brief, Stories, and related features). The key value is never shown after it is saved.")
        }

        Section {
            APIKeyPresenceIndicator(status: geminiStatus)

            apiKeyField(
                label: "Enter new key",
                accessibilityLabel: "Google Gemini API key",
                hint: nil,
                text: $geminiKey
            )

            HStack {
                Button("Save") {
                    Task { await saveGemini() }
                }
                .disabled(geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || geminiMutation)

                Button("Clear", role: .destructive) {
                    Task { await clearGemini() }
                }
                .disabled(geminiMutation || geminiStatus == nil)
            }
        } header: {
            Text("Google Gemini")
        } footer: {
            Text("Optional. Not used for Brief or Stories yet — choose OpenAI or Claude under LLM Management for those features.")
        }

        Section {
            APIKeyPresenceIndicator(status: claudeStatus)

            apiKeyField(
                label: "Enter new key",
                accessibilityLabel: "Anthropic Claude API key",
                hint: nil,
                text: $claudeKey
            )

            HStack {
                Button("Save") {
                    Task { await saveClaude() }
                }
                .disabled(claudeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || claudeMutation)

                Button("Clear", role: .destructive) {
                    Task { await clearClaude() }
                }
                .disabled(claudeMutation || claudeStatus == nil)
            }
        } header: {
            Text("Anthropic Claude")
        } footer: {
            Text("Used when Claude is selected as the provider in LLM Management.")
        }
    }

    @ViewBuilder
    private func apiKeyField(
        label: String,
        accessibilityLabel: String,
        hint: String?,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(SharedAppTheme.secondaryText)
            SecureField("", text: text)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .disableAutocorrection(true)
                .accessibilityLabel(accessibilityLabel)
            if let hint {
                Text(hint)
                    .font(SharedAppTheme.caption)
                    .foregroundStyle(SharedAppTheme.secondaryText.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshAll() async {
        let o = await LLMSettingsStore.shared.apiKeyStatus()
        let g = await GeminiAPIKeyStore.shared.apiKeyStatus()
        let c = await ClaudeAPIKeyStore.shared.apiKeyStatus()
        await MainActor.run {
            openAIStatus = o
            geminiStatus = g
            claudeStatus = c
        }
    }

    private func saveOpenAI() async {
        await MainActor.run { openAIMutation = true }
        let trimmed = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await LLMSettingsStore.shared.saveAPIKeyResult(trimmed)
        if result.success {
            await alignSelectedProvider(.openAI)
        }
        await refreshAll()
        await MainActor.run {
            openAIKey = ""
            openAIMutation = false
        }
    }

    private func clearOpenAI() async {
        await MainActor.run { openAIMutation = true }
        _ = await LLMSettingsStore.shared.clearAPIKeyResult()
        await refreshAll()
        await MainActor.run { openAIMutation = false }
    }

    private func saveGemini() async {
        await MainActor.run { geminiMutation = true }
        let trimmed = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = await GeminiAPIKeyStore.shared.saveAPIKeyResult(trimmed)
        await refreshAll()
        await MainActor.run {
            geminiKey = ""
            geminiMutation = false
        }
    }

    private func clearGemini() async {
        await MainActor.run { geminiMutation = true }
        _ = await GeminiAPIKeyStore.shared.clearAPIKeyResult()
        await refreshAll()
        await MainActor.run { geminiMutation = false }
    }

    private func saveClaude() async {
        await MainActor.run { claudeMutation = true }
        let trimmed = claudeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await ClaudeAPIKeyStore.shared.saveAPIKeyResult(trimmed)
        if result.success {
            await alignSelectedProvider(.claude)
        }
        await refreshAll()
        await MainActor.run {
            claudeKey = ""
            claudeMutation = false
        }
    }

    private func alignSelectedProvider(_ provider: LLMProvider) async {
        var settings = await LLMSettingsStore.shared.currentSettings()
        guard settings.provider != provider else { return }
        settings.provider = provider
        await LLMSettingsStore.shared.updateSettings(settings)
    }

    private func clearClaude() async {
        await MainActor.run { claudeMutation = true }
        _ = await ClaudeAPIKeyStore.shared.clearAPIKeyResult()
        await refreshAll()
        await MainActor.run { claudeMutation = false }
    }
}
