import Foundation

public actor AccountInclusionStore {
    public static let shared = AccountInclusionStore()

    private let fileName = "feature_account_inclusions.json"
    private var cached: [FeatureAccountInclusion] = []
    private var didLoad = false

    public func allInclusions() async -> [FeatureAccountInclusion] {
        await ensureLoaded()
        return cached.sorted { $0.accountEmail.lowercased() < $1.accountEmail.lowercased() }
    }

    public func refreshFromConnectedAccounts() async {
        await ensureLoaded()
        let connectedEmails = GmailAPIService.shared.getAllAccounts().map { $0.email }
        var updated = cached.filter { inclusion in
            connectedEmails.contains(where: { $0.caseInsensitiveCompare(inclusion.accountEmail) == .orderedSame })
        }

        for email in connectedEmails {
            if !updated.contains(where: { $0.accountEmail.caseInsensitiveCompare(email) == .orderedSame }) {
                updated.append(
                    FeatureAccountInclusion(
                        accountEmail: email,
                        includeInDailyBriefing: true,
                        includeInNewsletterInsights: true,
                        includeInQuickReply: true,
                        isPrimaryNewsletterAddress: false
                    )
                )
            }
        }

        if !updated.contains(where: { $0.isPrimaryNewsletterAddress }),
           let first = updated.indices.first {
            updated[first].isPrimaryNewsletterAddress = true
        }

        cached = updated
        await persist()
    }

    public func setIncludeInDailyBriefing(accountEmail: String, isIncluded: Bool) async {
        await ensureLoaded()
        guard let index = indexOf(email: accountEmail) else { return }
        cached[index].includeInDailyBriefing = isIncluded
        await persist()
    }

    public func setIncludeInNewsletterInsights(accountEmail: String, isIncluded: Bool) async {
        await ensureLoaded()
        guard let index = indexOf(email: accountEmail) else { return }
        cached[index].includeInNewsletterInsights = isIncluded
        await persist()
    }

    public func setIncludeInQuickReply(accountEmail: String, isIncluded: Bool) async {
        await ensureLoaded()
        guard let index = indexOf(email: accountEmail) else { return }
        cached[index].includeInQuickReply = isIncluded
        await persist()
    }

    public func setPrimaryNewsletterAddress(accountEmail: String) async {
        await ensureLoaded()
        for idx in cached.indices {
            cached[idx].isPrimaryNewsletterAddress = cached[idx].accountEmail.caseInsensitiveCompare(accountEmail) == .orderedSame
        }
        await persist()
    }

    public func isIncludedInDailyBriefing(accountEmail: String) async -> Bool {
        await ensureLoaded()
        return cached.first(where: { $0.accountEmail.caseInsensitiveCompare(accountEmail) == .orderedSame })?.includeInDailyBriefing ?? true
    }

    public func isIncludedInNewsletterInsights(accountEmail: String) async -> Bool {
        await ensureLoaded()
        return cached.first(where: { $0.accountEmail.caseInsensitiveCompare(accountEmail) == .orderedSame })?.includeInNewsletterInsights ?? true
    }

    public func isIncludedInQuickReply(accountEmail: String) async -> Bool {
        await ensureLoaded()
        return cached.first(where: { $0.accountEmail.caseInsensitiveCompare(accountEmail) == .orderedSame })?.includeInQuickReply ?? true
    }

    public func primaryNewsletterAddress() async -> String? {
        await ensureLoaded()
        return cached.first(where: { $0.isPrimaryNewsletterAddress })?.accountEmail
    }

    private func indexOf(email: String) -> Int? {
        cached.firstIndex(where: { $0.accountEmail.caseInsensitiveCompare(email) == .orderedSame })
    }

    public func invalidateAfterExternalFileChange() {
        didLoad = false
    }

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true
        cached = await loadFromDisk()
        await refreshFromConnectedAccounts()
    }

    private func loadFromDisk() async -> [FeatureAccountInclusion] {
        let fileURL = appSupportURL().appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        return (try? JSONDecoder().decode([FeatureAccountInclusion].self, from: data)) ?? []
    }

    private func persist() async {
        let fileURL = appSupportURL().appendingPathComponent(fileName)
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logError("Failed to persist account inclusion settings: \(error)", category: "Settings")
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
