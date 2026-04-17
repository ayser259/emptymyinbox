import Combine
import Foundation

/// User-facing feature toggles for Core Plugins (persisted in `UserDefaults`).
@MainActor
public final class FeatureFlagsStore: ObservableObject {
    public static let shared = FeatureFlagsStore()

    private enum Keys {
        static let llm = "settings.feature.llmEnabled"
        static let stories = "settings.feature.storiesEnabled"
        static let brief = "settings.feature.briefEnabled"
        static let quickReply = "settings.feature.quickReplyEnabled"
    }

    private let defaults: UserDefaults

    @Published public var isLLMEnabled: Bool {
        didSet { defaults.set(isLLMEnabled, forKey: Keys.llm) }
    }

    @Published public var isStoriesEnabled: Bool {
        didSet { defaults.set(isStoriesEnabled, forKey: Keys.stories) }
    }

    @Published public var isBriefEnabled: Bool {
        didSet { defaults.set(isBriefEnabled, forKey: Keys.brief) }
    }

    @Published public var isQuickReplyEnabled: Bool {
        didSet { defaults.set(isQuickReplyEnabled, forKey: Keys.quickReply) }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        self.isLLMEnabled = userDefaults.object(forKey: Keys.llm) as? Bool ?? true
        self.isStoriesEnabled = userDefaults.object(forKey: Keys.stories) as? Bool ?? true
        self.isBriefEnabled = userDefaults.object(forKey: Keys.brief) as? Bool ?? true
        self.isQuickReplyEnabled = userDefaults.object(forKey: Keys.quickReply) as? Bool ?? true
    }
}
