import Foundation
import Security
import Testing
import EmptyMyInboxShared

@Suite(.serialized)
struct LLMSettingsStoreTests {
    private func makeStore(testName: String) -> (LLMSettingsStore, UserDefaults) {
        let suffix = "\(testName)-\(UUID().uuidString)"
        let suiteName = "emptyMyInbox.tests.llm.\(suffix)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let store = LLMSettingsStore(
            settingsFileName: "llm_settings_\(suffix).json",
            keychainService: "com.emptyMyInbox.llm.tests.\(suffix)",
            keychainAccount: "openai_api_key",
            userDefaults: defaults,
            metadataNamespace: suffix
        )
        return (store, defaults)
    }

    @Test("LLM settings default to cost-efficient initial model")
    func testDefaultSettingsValues() {
        let settings = LLMSettings.default
        #expect(settings.provider == .openAI)
        #expect(settings.defaultModel == "gpt-4o-mini")
        #expect(settings.initialPassModel == "gpt-4o-mini")
        #expect(settings.quickReplyModel == "gpt-4o-mini")
        #expect(settings.proModel.contains("gpt"))
        #expect(settings.maxRetries >= 0)
    }

    @Test("LLM settings persist model updates")
    func testUpdateSettingsRoundTrip() async {
        let (store, _) = makeStore(testName: "roundtrip")
        let newSettings = LLMSettings(
            defaultModel: "gpt-4.1-mini",
            initialPassModel: "gpt-4o-mini",
            proModel: "gpt-4.1",
            useProModelForDeepAnalysis: true,
            requestTimeoutSeconds: 45,
            maxRetries: 1
        )
        await store.updateSettings(newSettings)
        let loaded = await store.currentSettings()
        #expect(loaded.defaultModel == "gpt-4.1-mini")
        #expect(loaded.briefModel == "gpt-4o-mini")
        #expect(loaded.storiesModel == "gpt-4o-mini")
        #expect(loaded.quickReplyModel == "gpt-4.1-mini")
        #expect(loaded.useProModelForDeepAnalysis == true)
        #expect(loaded.requestTimeoutSeconds == 45)
    }

    @Test("API key save and clear round-trip")
    func testAPIKeySaveAndClearRoundTrip() async {
        let (store, _) = makeStore(testName: "save-clear")
        _ = await store.clearAPIKeyResult()
        #expect(await store.hasAPIKey() == false)

        let saveResult = await store.saveAPIKeyResult("sk-test-1234567890")
        #expect(saveResult.success == true)
        #expect(saveResult.status == errSecSuccess)
        #expect(saveResult.message.contains("saved"))
        #expect(await store.hasAPIKey() == true)
        #expect(await store.getAPIKey() == "sk-test-1234567890")
        #expect(await store.apiKeyStatus() != nil)

        let clearResult = await store.clearAPIKeyResult()
        #expect(clearResult.success == true)
        #expect(clearResult.message.contains("deleted") || clearResult.message.contains("already removed"))
        #expect(await store.hasAPIKey() == false)
        #expect(await store.apiKeyStatus() == nil)
    }

    @Test("API key status self-heals missing metadata")
    func testAPIKeyStatusSelfHealing() async {
        let (store, defaults) = makeStore(testName: "status-heal")
        _ = await store.clearAPIKeyResult()
        _ = await store.saveAPIKey("sk-test-abcdef1234")

        let keys = defaults.dictionaryRepresentation().keys
        for key in keys where key.contains("llm_api_key_") {
            defaults.removeObject(forKey: key)
        }

        let status = await store.apiKeyStatus()
        #expect(status != nil)
        #expect(status?.maskedKey.contains("••••••••") == true)
    }

    @Test("Save API key result fails on empty input")
    func testSaveAPIKeyResultRejectsEmptyInput() async {
        let (store, _) = makeStore(testName: "empty")
        let result = await store.saveAPIKeyResult("   ")
        #expect(result.success == false)
        #expect(result.status == errSecParam)
        #expect(result.message.contains("cannot be empty"))
    }

    @Test("Read API key result reflects not found")
    func testReadAPIKeyResultWhenMissing() async {
        let (store, _) = makeStore(testName: "read-missing")
        _ = await store.clearAPIKeyResult()
        let result = await store.readAPIKeyResult()
        #expect(result.success == false)
        #expect(result.keyValue == nil)
        #expect(result.message.contains("No API key"))
    }

    @Test("Invalid persisted model names fall back to supported defaults")
    func testInvalidModelSettingsFallback() async {
        let (store, _) = makeStore(testName: "model-fallback")
        await store.updateSettings(
            LLMSettings(
                provider: .openAI,
                defaultModel: "unknown-model",
                initialPassModel: "gpt-4o-mini",
                proModel: "deprecated",
                useProModelForDeepAnalysis: false,
                requestTimeoutSeconds: 30,
                maxRetries: 2
            )
        )
        let loaded = await store.currentSettings()
        #expect(loaded.defaultModel == "gpt-4o-mini")
        #expect(loaded.proModel == "gpt-4.1")
        #expect(loaded.quickReplyModel == "gpt-4o-mini")
    }

    @Test("LLM settings persist provider and Claude models")
    func testProviderAndClaudeModelRoundTrip() async {
        let (store, _) = makeStore(testName: "provider-roundtrip")
        let newSettings = LLMSettings(
            provider: .claude,
            defaultModel: "claude-sonnet-4-6",
            initialPassModel: "claude-haiku-4-5",
            proModel: "claude-sonnet-4-6",
            briefModel: "claude-haiku-4-5",
            storiesModel: "claude-sonnet-4-6",
            quickReplyModel: "claude-sonnet-4-6",
            useProModelForDeepAnalysis: true,
            requestTimeoutSeconds: 35,
            maxRetries: 2
        )
        await store.updateSettings(newSettings)
        let loaded = await store.currentSettings()
        #expect(loaded.provider == .claude)
        #expect(loaded.defaultModel == "claude-sonnet-4-6")
        #expect(loaded.briefModel == "claude-haiku-4-5")
        #expect(loaded.storiesModel == "claude-sonnet-4-6")
        #expect(loaded.quickReplyModel == "claude-sonnet-4-6")
        #expect(loaded.initialPassModel == "claude-haiku-4-5")
    }

    @Test("Invalid Claude model names fall back to Claude defaults")
    func testInvalidClaudeModelSettingsFallback() async {
        let (store, _) = makeStore(testName: "claude-model-fallback")
        await store.updateSettings(
            LLMSettings(
                provider: .claude,
                defaultModel: "unknown-claude-default",
                initialPassModel: "unknown-claude-initial",
                proModel: "unknown-claude-pro",
                useProModelForDeepAnalysis: false,
                requestTimeoutSeconds: 30,
                maxRetries: 2
            )
        )
        let loaded = await store.currentSettings()
        #expect(loaded.provider == .claude)
        #expect(loaded.defaultModel == "claude-sonnet-4-6")
        #expect(loaded.initialPassModel == "claude-haiku-4-5")
        #expect(loaded.proModel == "claude-sonnet-4-6")
        #expect(loaded.briefModel == "claude-haiku-4-5")
        #expect(loaded.storiesModel == "claude-haiku-4-5")
        #expect(loaded.quickReplyModel == "claude-sonnet-4-6")
    }

    @Test("Claude legacy aliases migrate to latest supported IDs")
    func testClaudeLatestAliasMigration() async {
        let (store, _) = makeStore(testName: "claude-alias-migration")
        await store.updateSettings(
            LLMSettings(
                provider: .claude,
                defaultModel: "claude-3-5-sonnet-latest",
                initialPassModel: "claude-3-5-haiku-latest",
                proModel: "claude-3-5-sonnet-latest",
                briefModel: "claude-3-5-haiku-latest",
                storiesModel: "claude-3-5-sonnet-latest",
                quickReplyModel: "claude-3-5-sonnet-latest",
                useProModelForDeepAnalysis: false,
                requestTimeoutSeconds: 30,
                maxRetries: 2
            )
        )

        let loaded = await store.currentSettings()
        #expect(loaded.defaultModel == "claude-sonnet-4-6")
        #expect(loaded.initialPassModel == "claude-haiku-4-5")
        #expect(loaded.briefModel == "claude-haiku-4-5")
        #expect(loaded.storiesModel == "claude-sonnet-4-6")
        #expect(loaded.quickReplyModel == "claude-sonnet-4-6")
    }

    @Test("Legacy settings without provider decode as OpenAI")
    func testLegacySettingsDecodeDefaultsProvider() throws {
        let legacyJSON = """
        {
          "defaultModel": "gpt-4o-mini",
          "initialPassModel": "gpt-4o-mini",
          "proModel": "gpt-4.1",
          "useProModelForDeepAnalysis": false,
          "requestTimeoutSeconds": 30,
          "maxRetries": 2
        }
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(LLMSettings.self, from: data)
        #expect(decoded.provider == .openAI)
        #expect(decoded.quickReplyModel == "gpt-4o-mini")
    }
}
