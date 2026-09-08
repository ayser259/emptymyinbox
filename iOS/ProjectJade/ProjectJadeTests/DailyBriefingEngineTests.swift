import Foundation
import Testing
import ProjectJadeShared

struct DailyBriefingEngineTests {
    @Test("On-device brief can generate without a cloud API key")
    func testOnDeviceBriefDoesNotRequireCloudKey() async {
        let settings = await LLMSettingsStore.shared.currentSettings()
        guard settings.briefProvider == .onDevice else { return }
        guard OnDeviceAIService.isAvailable() else { return }

        let canGenerate = await LLMProviderRouter.shared.canGenerateBrief()
        #expect(canGenerate == true)
    }

    @Test("Unavailable on-device brief returns setup guidance")
    func testOnDeviceUnavailableIntro() async {
        let capability = await LLMProviderRouter.shared.briefGenerationCapability()
        guard capability == .onDeviceUnavailable else { return }

        let payload = await DailyBriefingEngine.shared.buildPayload(from: [], sinceDate: nil)
        #expect(payload.items.isEmpty)
        #expect(payload.introText.contains("Apple Intelligence"))
    }

    @Test("Cloud brief without API key returns key setup guidance")
    func testCloudBriefMissingKeyIntro() async {
        let settings = await LLMSettingsStore.shared.currentSettings()
        guard settings.briefProvider == .openAI || settings.briefProvider == .claude else { return }

        let capability = await LLMProviderRouter.shared.briefGenerationCapability()
        guard case .missingAPIKey = capability else { return }

        let payload = await DailyBriefingEngine.shared.buildPayload(from: [], sinceDate: nil)
        #expect(payload.items.isEmpty)
        #expect(payload.introText.contains("API key"))
    }
}

struct OnDeviceAICapabilityTests {
    @Test("On-device stories can generate without a cloud API key")
    func testOnDeviceStoriesCapability() async {
        let settings = await LLMSettingsStore.shared.currentSettings()
        guard settings.storiesProvider == .onDevice else { return }
        guard OnDeviceAIService.isAvailable() else { return }

        let canGenerate = await LLMProviderRouter.shared.canGenerateStories()
        #expect(canGenerate == true)
    }

    @Test("On-device quick reply can generate without a cloud API key")
    func testOnDeviceQuickReplyCapability() async {
        let settings = await LLMSettingsStore.shared.currentSettings()
        guard settings.quickReplyProvider == .onDevice else { return }
        guard OnDeviceAIService.isAvailable() else { return }

        let canGenerate = await LLMProviderRouter.shared.canGenerateQuickReply()
        #expect(canGenerate == true)
    }
}
