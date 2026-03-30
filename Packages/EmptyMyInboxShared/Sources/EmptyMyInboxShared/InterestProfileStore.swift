import Foundation

public actor InterestProfileStore {
    public static let shared = InterestProfileStore()

    private let fileName = "interest_profile.json"
    private var profile = InterestProfile.empty
    private var didLoad = false
    private let minScore = -1.0
    private let maxScore = 1.0

    public func currentProfile() async -> InterestProfile {
        await ensureLoaded()
        return profile
    }

    public func applySignal(_ signal: InterestSignal) async {
        await ensureLoaded()
        let delta = signal.signalType == .more ? 0.2 : -0.2
        let normalizedTheme = signal.themeTag.lowercased()
        let normalizedSender = signal.sender.lowercased()

        profile.themeScores[normalizedTheme] = clamped((profile.themeScores[normalizedTheme] ?? 0) + delta)
        profile.senderScores[normalizedSender] = clamped((profile.senderScores[normalizedSender] ?? 0) + delta)

        profile.recentSignals.append(signal)
        profile.recentSignals = Array(profile.recentSignals.suffix(200))
        profile.updatedAt = Date()
        await persist()
    }

    public func shouldProcessNewsletter(themeTag: String, sender: String) async -> Bool {
        await ensureLoaded()
        let themeScore = profile.themeScores[themeTag.lowercased()] ?? 0
        let senderScore = profile.senderScores[sender.lowercased()] ?? 0
        return (themeScore + senderScore) > -0.8
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, minScore), maxScore)
    }

    /// Call after an external process replaces `interest_profile.json` on disk (e.g. future sync).
    public func invalidateAfterExternalFileChange() {
        didLoad = false
    }

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true
        profile = await loadFromDisk() ?? .empty
    }

    private func loadFromDisk() async -> InterestProfile? {
        let fileURL = appSupportURL().appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(InterestProfile.self, from: data)
    }

    private func persist() async {
        let fileURL = appSupportURL().appendingPathComponent(fileName)
        do {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logError("Failed to persist interest profile: \(error)", category: "Settings")
        }
    }

    private func appSupportURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("emptyMyInbox", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
