import Foundation

private struct StoriesFeedState: Codable {
    var schemaVersion: Int
    var stories: [InsightCard]
    /// Story cards marked read; bookmarked cards stay in `stories` and are listed here too.
    var reviewedStoryIds: [Int]
    var bookmarkedStoryIds: [Int]
    var lastGeneratedAt: Date?
    var promptStates: [Int: StoryPromptState]

    enum CodingKeys: String, CodingKey {
        case schemaVersion, stories, reviewedStoryIds, bookmarkedStoryIds, lastGeneratedAt, promptStates
    }

    init(
        schemaVersion: Int,
        stories: [InsightCard],
        reviewedStoryIds: [Int],
        bookmarkedStoryIds: [Int],
        lastGeneratedAt: Date?,
        promptStates: [Int: StoryPromptState]
    ) {
        self.schemaVersion = schemaVersion
        self.stories = stories
        self.reviewedStoryIds = reviewedStoryIds
        self.bookmarkedStoryIds = bookmarkedStoryIds
        self.lastGeneratedAt = lastGeneratedAt
        self.promptStates = promptStates
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        stories = try c.decode([InsightCard].self, forKey: .stories)
        reviewedStoryIds = try c.decodeIfPresent([Int].self, forKey: .reviewedStoryIds) ?? []
        bookmarkedStoryIds = try c.decodeIfPresent([Int].self, forKey: .bookmarkedStoryIds) ?? []
        lastGeneratedAt = try c.decodeIfPresent(Date.self, forKey: .lastGeneratedAt)
        promptStates = try c.decode([Int: StoryPromptState].self, forKey: .promptStates)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(stories, forKey: .stories)
        try c.encode(reviewedStoryIds, forKey: .reviewedStoryIds)
        try c.encode(bookmarkedStoryIds, forKey: .bookmarkedStoryIds)
        try c.encodeIfPresent(lastGeneratedAt, forKey: .lastGeneratedAt)
        try c.encode(promptStates, forKey: .promptStates)
    }
}

private struct LegacyStoriesFeedState: Codable {
    var stories: [InsightCard]
    var promptedEmailIds: Set<Int>
}

/// Legacy schema 2 (no review/bookmark fields).
private struct StoriesFeedStateV2: Codable {
    var schemaVersion: Int
    var stories: [InsightCard]
    var promptStates: [Int: StoryPromptState]
}

public actor StoriesFeedStore {
    public static let shared = StoriesFeedStore()

    private static let schemaVersion = 3
    private static let maxStories = 200
    private static let successRetentionDays = 45
    private static let failureRetentionDays = 14

    private let fileName: String
    private let appSupportFolderName: String
    private var state = StoriesFeedState(
        schemaVersion: schemaVersion,
        stories: [],
        reviewedStoryIds: [],
        bookmarkedStoryIds: [],
        lastGeneratedAt: nil,
        promptStates: [:]
    )
    private var didLoad = false

    public init(
        fileName: String = "stories_feed_state.json",
        appSupportFolderName: String = "emptyMyInbox"
    ) {
        self.fileName = fileName
        self.appSupportFolderName = appSupportFolderName
    }

    /// Main feed: unreviewed stories (bookmark state does not hide from main until reviewed).
    public func stories() async -> [InsightCard] {
        await ensureLoaded()
        let reviewed = Set(state.reviewedStoryIds)
        return state.stories.filter { !reviewed.contains($0.id) }
    }

    /// All bookmarked cards (including reviewed+bookmarked).
    public func bookmarkedStories() async -> [InsightCard] {
        await ensureLoaded()
        let ids = Set(state.bookmarkedStoryIds)
        return state.stories.filter { ids.contains($0.id) }
    }

    public func isBookmarked(storyId: Int) async -> Bool {
        await ensureLoaded()
        return state.bookmarkedStoryIds.contains(storyId)
    }

    public func bookmarkedStoryIdSet() async -> Set<Int> {
        await ensureLoaded()
        return Set(state.bookmarkedStoryIds)
    }

    public func lastGeneratedAt() async -> Date? {
        await ensureLoaded()
        return state.lastGeneratedAt
    }

    public func setLastGeneratedAt(_ date: Date?) async {
        await ensureLoaded()
        state.lastGeneratedAt = date
        pruneState(now: Date())
        await persistCacheAndMirrorVault()
    }

    public func promptStates() async -> [Int: StoryPromptState] {
        await ensureLoaded()
        return state.promptStates
    }

    public func appendStories(_ newStories: [InsightCard]) async {
        await ensureLoaded()

        let existingStoryIDs = Set(state.stories.map { $0.id })
        let appendable = newStories.filter { !existingStoryIDs.contains($0.id) }
        state.stories.append(contentsOf: appendable)
        pruneState(now: Date())
        await persistCacheAndMirrorVault()
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
        await persistCacheAndMirrorVault()
    }

    /// Mark story as read. Bookmarked stories stay in storage for the Bookmarked list; others are removed.
    public func markReviewed(storyId: Int) async {
        await ensureLoaded()
        if state.bookmarkedStoryIds.contains(storyId) {
            if !state.reviewedStoryIds.contains(storyId) {
                state.reviewedStoryIds.append(storyId)
            }
        } else {
            state.stories.removeAll { $0.id == storyId }
        }
        pruneState(now: Date())
        await persistCacheAndMirrorVault()
    }

    public func bookmarkStory(storyId: Int) async {
        await ensureLoaded()
        if !state.bookmarkedStoryIds.contains(storyId) {
            state.bookmarkedStoryIds.append(storyId)
        }
        pruneState(now: Date())
        await persistCacheAndMirrorVault()
    }

    public func unbookmarkStory(storyId: Int) async {
        await ensureLoaded()
        state.bookmarkedStoryIds.removeAll { $0 == storyId }
        if state.reviewedStoryIds.contains(storyId) {
            state.reviewedStoryIds.removeAll { $0 == storyId }
            state.stories.removeAll { $0.id == storyId }
        }
        pruneState(now: Date())
        await persistCacheAndMirrorVault()
    }

    /// Legacy name — forwards to `markReviewed`.
    public func dismissStory(storyId: Int) async {
        await markReviewed(storyId: storyId)
    }

    public func invalidateAfterExternalFileChange() {
        didLoad = false
    }

    /// Removes persisted stories feed (e.g. full sign-out).
    public func clear() async {
        let url = appSupportURL().appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        state = StoriesFeedState(
            schemaVersion: Self.schemaVersion,
            stories: [],
            reviewedStoryIds: [],
            bookmarkedStoryIds: [],
            lastGeneratedAt: nil,
            promptStates: [:]
        )
        didLoad = false
    }

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true
        state = await loadFromDisk() ?? StoriesFeedState(
            schemaVersion: Self.schemaVersion,
            stories: [],
            reviewedStoryIds: [],
            bookmarkedStoryIds: [],
            lastGeneratedAt: nil,
            promptStates: [:]
        )
        await mergeFromVaultIfAvailable()
        pruneState(now: Date())
    }

    private func loadFromDisk() async -> StoriesFeedState? {
        let url = appSupportURL().appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        if let decoded = try? JSONDecoder().decode(StoriesFeedState.self, from: data) {
            var s = decoded
            if s.schemaVersion < Self.schemaVersion {
                s.schemaVersion = Self.schemaVersion
            }
            return s
        }
        if let v2 = try? JSONDecoder().decode(StoriesFeedStateV2.self, from: data) {
            return StoriesFeedState(
                schemaVersion: Self.schemaVersion,
                stories: v2.stories,
                reviewedStoryIds: [],
                bookmarkedStoryIds: [],
                lastGeneratedAt: nil,
                promptStates: v2.promptStates
            )
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
            return StoriesFeedState(
                schemaVersion: Self.schemaVersion,
                stories: legacy.stories,
                reviewedStoryIds: [],
                bookmarkedStoryIds: [],
                lastGeneratedAt: nil,
                promptStates: migrated
            )
        }
        return nil
    }

    /// When a vault file exists, it wins over local cache (Drive sync / explicit mirror).
    private func mergeFromVaultIfAvailable() async {
        let ready = await MainActor.run { VaultManager.shared.isVaultReady }
        guard ready else { return }
        do {
            guard let payload = try await VaultManager.shared.loadStoriesFeedFromVault() else { return }
            state.stories = payload.stories
            state.bookmarkedStoryIds = payload.bookmarkedStoryIds
            state.reviewedStoryIds = payload.reviewedStoryIds
            state.lastGeneratedAt = payload.lastGeneratedAt
            state.promptStates = payload.promptStates
            state.schemaVersion = Self.schemaVersion
            await persistCacheOnly()
        } catch {
            logError("Stories: vault merge failed: \(error)", category: "Vault")
        }
    }

    private func persistCacheOnly() async {
        let url = appSupportURL().appendingPathComponent(fileName)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            logError("Failed to persist stories feed: \(error)", category: "Settings")
        }
    }

    private func persistCacheAndMirrorVault() async {
        await persistCacheOnly()
        await mirrorToVaultIfPossible()
    }

    private func mirrorToVaultIfPossible() async {
        let ready = await MainActor.run { VaultManager.shared.isVaultReady }
        guard ready else { return }
        let payload = VaultStoriesFeedPayload(
            stories: state.stories,
            bookmarkedStoryIds: state.bookmarkedStoryIds,
            reviewedStoryIds: state.reviewedStoryIds,
            lastGeneratedAt: state.lastGeneratedAt,
            promptStates: state.promptStates
        )
        let bookmarkedCards = await bookmarkedStories()
        do {
            try await VaultManager.shared.saveStoriesFeedToVault(payload)
            try await VaultManager.shared.saveBookmarkedStoriesMirrorToVault(
                VaultStoriesBookmarkedPayload(stories: bookmarkedCards)
            )
        } catch {
            logError("Stories: vault mirror failed: \(error)", category: "Vault")
        }
    }

    private func pruneState(now: Date) {
        let bookmarkedIds = Set(state.bookmarkedStoryIds)
        let rest = state.stories.filter { !bookmarkedIds.contains($0.id) }
        let bookmarked = state.stories.filter { bookmarkedIds.contains($0.id) }
        let cappedRest = rest.count > Self.maxStories ? Array(rest.suffix(Self.maxStories)) : rest
        state.stories = cappedRest + bookmarked

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
