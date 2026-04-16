import Foundation

private struct StoriesFeedState: Codable {
    var schemaVersion: Int
    var stories: [InsightCard]
    var promptStates: [Int: StoryPromptState]
}

private struct LegacyStoriesFeedState: Codable {
    var stories: [InsightCard]
    var promptedEmailIds: Set<Int>
}

public actor StoriesFeedStore {
    public static let shared = StoriesFeedStore()

    private static let schemaVersion = 2
    private static let maxStories = 200
    private static let successRetentionDays = 45
    private static let failureRetentionDays = 14

    private let fileName: String
    private let appSupportFolderName: String
    private var state = StoriesFeedState(schemaVersion: schemaVersion, stories: [], promptStates: [:])
    private var didLoad = false

    public init(
        fileName: String = "stories_feed_state.json",
        appSupportFolderName: String = "emptyMyInbox"
    ) {
        self.fileName = fileName
        self.appSupportFolderName = appSupportFolderName
    }

    public func stories() async -> [InsightCard] {
        await ensureLoaded()
        return state.stories
    }

    public func promptStates() async -> [Int: StoryPromptState] {
        await ensureLoaded()
        return state.promptStates
    }

    public func appendStories(_ newStories: [InsightCard]) async {
        await ensureLoaded()

        // Append only new story IDs to preserve existing feed order.
        let existingStoryIDs = Set(state.stories.map { $0.id })
        let appendable = newStories.filter { !existingStoryIDs.contains($0.id) }
        state.stories.append(contentsOf: appendable)
        pruneState(now: Date())
        await persist()
    }

    public func applyPromptOutcome(_ outcome: StoryPromptOutcome) async {
        await ensureLoaded()
        var promptState = state.promptStates[outcome.emailId] ?? StoryPromptState()
        let now = Date()
        promptState.attempts += 1
        promptState.lastAttemptAt = now

        switch outcome.result {
        case .success:
            promptState.status = .succeeded
            promptState.lastSuccessAt = now
            promptState.lastError = nil
            promptState.cooldownUntil = nil
        case .failed(let reason):
            promptState.status = .failed
            promptState.lastError = reason
            let exponent = max(promptState.attempts - 1, 0)
            let backoffMinutes = min(pow(2.0, Double(exponent)) * 15.0, 24.0 * 60.0)
            promptState.cooldownUntil = now.addingTimeInterval(backoffMinutes * 60.0)
        case .empty:
            promptState.status = .failed
            promptState.lastError = "No matching insights."
            promptState.cooldownUntil = now.addingTimeInterval(6 * 60 * 60)
        }

        state.promptStates[outcome.emailId] = promptState
        pruneState(now: now)
        await persist()
    }

    public func dismissStory(storyId: Int) async {
        await ensureLoaded()
        state.stories.removeAll { $0.id == storyId }
        pruneState(now: Date())
        await persist()
    }

    public func invalidateAfterExternalFileChange() {
        didLoad = false
    }

    /// Removes persisted stories feed (e.g. full sign-out).
    public func clear() async {
        let url = appSupportURL().appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        state = StoriesFeedState(schemaVersion: Self.schemaVersion, stories: [], promptStates: [:])
        didLoad = false
    }

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true
        state = await loadFromDisk() ?? StoriesFeedState(schemaVersion: Self.schemaVersion, stories: [], promptStates: [:])
        pruneState(now: Date())
    }

    private func loadFromDisk() async -> StoriesFeedState? {
        let url = appSupportURL().appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        if let state = try? JSONDecoder().decode(StoriesFeedState.self, from: data) {
            return state
        }
        if let legacy = try? JSONDecoder().decode(LegacyStoriesFeedState.self, from: data) {
            let now = Date()
            var migrated: [Int: StoryPromptState] = [:]
            for emailId in legacy.promptedEmailIds {
                migrated[emailId] = StoryPromptState(
                    status: .succeeded,
                    attempts: 1,
                    lastAttemptAt: now,
                    lastSuccessAt: now,
                    lastError: nil,
                    cooldownUntil: nil
                )
            }
            return StoriesFeedState(schemaVersion: Self.schemaVersion, stories: legacy.stories, promptStates: migrated)
        }
        return nil
    }

    private func persist() async {
        let url = appSupportURL().appendingPathComponent(fileName)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            logError("Failed to persist stories feed: \(error)", category: "Settings")
        }
    }

    private func pruneState(now: Date) {
        let maxStories = Self.maxStories
        if state.stories.count > maxStories {
            state.stories = Array(state.stories.suffix(maxStories))
        }

        let successCutoff = Calendar.current.date(byAdding: .day, value: -Self.successRetentionDays, to: now) ?? now
        let failureCutoff = Calendar.current.date(byAdding: .day, value: -Self.failureRetentionDays, to: now) ?? now
        state.promptStates = state.promptStates.filter { _, promptState in
            switch promptState.status {
            case .succeeded:
                guard let lastSuccessAt = promptState.lastSuccessAt else { return false }
                return lastSuccessAt >= successCutoff
            case .attempted, .failed:
                return promptState.lastAttemptAt >= failureCutoff
            }
        }
    }

    private func appSupportURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(appSupportFolderName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
