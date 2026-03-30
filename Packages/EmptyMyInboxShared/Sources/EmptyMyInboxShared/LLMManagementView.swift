import Security
import SwiftUI

/// LLM API key and model settings (iOS + macOS).
public struct LLMManagementView: View {
    @State private var settings: LLMSettings = .default
    @State private var apiKey: String = ""
    @State private var keyStatus: LLMAPIKeyStatus?
    @State private var isSaving = false
    @State private var testResult: String?
    @State private var keyMutationInFlight = false
    @State private var statusNonce = 0

    private let modelOptions = ["gpt-4o-mini", "gpt-4.1-mini", "gpt-4.1", "gpt-4o"]

    public init() {}

    public var body: some View {
        Form {
            Section("OpenAI API Key") {
                SecureField("sk-...", text: $apiKey)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .disableAutocorrection(true)

                if let keyStatus {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stored Key: \(keyStatus.maskedKey)")
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                        Text("Added: \(formattedDate(keyStatus.addedAt))")
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                    }
                }

                HStack {
                    Button("Save API Key") {
                        Task { await saveAPIKey() }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .disabled(keyMutationInFlight)

                    Button("Clear Key", role: .destructive) {
                        Task {
                            let nonce = await beginStatusOperation()
                            let result = await LLMSettingsStore.shared.clearAPIKeyResult()
                            await load()
                            await setStatus(result.message, nonce: nonce)
                            await MainActor.run { keyMutationInFlight = false }
                        }
                    }
                    .disabled(keyMutationInFlight)
                }
            }

            Section("Model Selection") {
                Picker("Default Model", selection: $settings.defaultModel) {
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Picker("Initial Pass Model", selection: $settings.initialPassModel) {
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Picker("Pro Model", selection: $settings.proModel) {
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Toggle("Use Pro model for deep analysis", isOn: $settings.useProModelForDeepAnalysis)
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
        let status = await LLMSettingsStore.shared.apiKeyStatus()
        await MainActor.run {
            settings = loaded
            keyStatus = status
        }
    }

    private func saveAPIKey() async {
        let nonce = await beginStatusOperation()
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await LLMSettingsStore.shared.saveAPIKeyResult(trimmed)
        await load()
        if result.success {
            await MainActor.run { apiKey = "" }
            await setStatus(result.message, nonce: nonce)
        } else {
            await setStatus(result.message, nonce: nonce)
        }
        await MainActor.run { keyMutationInFlight = false }
    }

    private func saveSettings() async {
        await MainActor.run { isSaving = true }
        let pendingKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var keySaveResult = LLMKeychainOperationResult(success: true, status: errSecSuccess, message: "No key update.", keyValue: nil)
        if !pendingKey.isEmpty {
            keySaveResult = await LLMSettingsStore.shared.saveAPIKeyResult(pendingKey)
        }
        if keySaveResult.success {
            await LLMSettingsStore.shared.updateSettings(settings)
            await load()
        }
        await MainActor.run {
            isSaving = false
            if keySaveResult.success {
                apiKey = ""
                testResult = "Settings saved."
            } else {
                testResult = keySaveResult.message
            }
        }
    }

    private func testConnection() async {
        let hasKey = await LLMSettingsStore.shared.hasAPIKey()
        guard hasKey else {
            await MainActor.run {
                testResult = "Add and save an API key first."
            }
            return
        }

        do {
            _ = try await OpenAIService.shared.classifyBriefingItem(
                subject: "Team sync tomorrow 10am",
                snippet: "Calendar invite attached",
                sender: "calendar@google.com"
            )
            await MainActor.run {
                testResult = "Connection successful."
            }
        } catch {
            await MainActor.run {
                testResult = "Connection failed: \(error.localizedDescription)"
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @MainActor
    private func beginStatusOperation() -> Int {
        keyMutationInFlight = true
        statusNonce += 1
        return statusNonce
    }

    @MainActor
    private func setStatus(_ message: String, nonce: Int) {
        guard nonce == statusNonce else { return }
        testResult = message
    }
}
