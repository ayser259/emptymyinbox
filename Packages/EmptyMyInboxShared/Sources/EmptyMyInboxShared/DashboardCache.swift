//
//  DashboardCache.swift
//  emptyMyInbox
//
//  Persists dashboard data (accounts, emails, labels, starred) locally.
//

import Foundation

public struct DashboardDataSnapshot: Codable {
    public let timestamp: Date
    public let accounts: [EmailAccount]
    public let emails: [EmailListItem]
    public let allEmails: [EmailListItem]
    public let starredEmails: [EmailListItem]
    public let sentEmails: [EmailListItem]
    public let labels: [GmailLabel]
    
    public init(
        timestamp: Date,
        accounts: [EmailAccount],
        emails: [EmailListItem],
        allEmails: [EmailListItem],
        starredEmails: [EmailListItem],
        sentEmails: [EmailListItem] = [],
        labels: [GmailLabel]
    ) {
        self.timestamp = timestamp
        self.accounts = accounts
        self.emails = emails
        self.allEmails = allEmails
        self.starredEmails = starredEmails
        self.sentEmails = sentEmails
        self.labels = labels
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp, accounts, emails, allEmails, starredEmails, sentEmails, labels
    }

    // Custom decoder so snapshots saved before `allEmails` was introduced still load correctly.
    // Falls back to the unread-only `emails` list when the key is absent.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        accounts = try c.decode([EmailAccount].self, forKey: .accounts)
        emails = try c.decode([EmailListItem].self, forKey: .emails)
        allEmails = (try? c.decode([EmailListItem].self, forKey: .allEmails)) ?? emails
        starredEmails = (try? c.decode([EmailListItem].self, forKey: .starredEmails)) ?? []
        sentEmails = (try? c.decode([EmailListItem].self, forKey: .sentEmails)) ?? []
        labels = (try? c.decode([GmailLabel].self, forKey: .labels)) ?? []
    }
}

public actor DashboardCache {
    public static let shared = DashboardCache()
    private nonisolated static let stableIdMigrationKey = "DashboardCacheStableIdMigrationV1"
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL
    private var pendingSnapshot: DashboardDataSnapshot?
    private var saveTask: Task<Void, Never>?
    private let saveDebounceNanoseconds: UInt64 = 200_000_000
    
    private init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        fileURL = directory.appendingPathComponent("dashboard_snapshot.json")
        Self.migrateSnapshotIfNeeded(fileURL: fileURL)
    }
    
    public func loadSnapshot() -> DashboardDataSnapshot? {
        if let pendingSnapshot {
            return pendingSnapshot
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(DashboardDataSnapshot.self, from: data)
        } catch {
            logError("DashboardCache load error: \(error)", category: "Cache")
            return nil
        }
    }
    
    public func saveSnapshot(accounts: [EmailAccount],
                      emails: [EmailListItem],
                      allEmails: [EmailListItem],
                      starredEmails: [EmailListItem],
                      sentEmails: [EmailListItem] = [],
                      labels: [GmailLabel]) {
        let snapshot = DashboardDataSnapshot(
            timestamp: Date(),
            accounts: accounts,
            emails: emails,
            allEmails: allEmails,
            starredEmails: starredEmails,
            sentEmails: sentEmails,
            labels: labels
        )
        saveSnapshot(snapshot)
    }
    
    public func saveSnapshot(_ snapshot: DashboardDataSnapshot) {
        pendingSnapshot = snapshot
        scheduleSave()
    }
    
    public func clear() {
        saveTask?.cancel()
        saveTask = nil
        pendingSnapshot = nil
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            logError("DashboardCache clear error: \(error)", category: "Cache")
        }
    }
    
    func flushPendingSaveForTests() async {
        await flushPendingSnapshot()
    }
    
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: saveDebounceNanoseconds)
            await self.flushPendingSnapshot()
        }
    }
    
    private func flushPendingSnapshot() {
        guard let snapshot = pendingSnapshot else { return }
        
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            pendingSnapshot = nil
        } catch {
            logError("DashboardCache save error: \(error)", category: "Cache")
        }
    }
    
    private nonisolated static func migrateSnapshotIfNeeded(fileURL: URL) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: stableIdMigrationKey) else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            defaults.set(true, forKey: stableIdMigrationKey)
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(DashboardDataSnapshot.self, from: data)
            let migrated = DashboardDataSnapshot(
                timestamp: snapshot.timestamp,
                accounts: snapshot.accounts.map { account in
                    EmailAccount(
                        id: StableID.accountId(email: account.email),
                        email: account.email,
                        is_active: account.is_active,
                        last_sync: account.last_sync,
                        created_at: account.created_at,
                        email_count: account.email_count
                    )
                },
                emails: snapshot.emails.map(migratedEmail),
                allEmails: snapshot.allEmails.map(migratedEmail),
                starredEmails: snapshot.starredEmails.map(migratedEmail),
                sentEmails: snapshot.sentEmails.map(migratedEmail),
                labels: snapshot.labels
            )
            
            let migratedData = try JSONEncoder().encode(migrated)
            try migratedData.write(to: fileURL, options: .atomic)
            defaults.set(true, forKey: stableIdMigrationKey)
            logSuccess("DashboardCache: Stable ID migration completed", category: "Cache")
        } catch {
            logError("DashboardCache stable ID migration failed: \(error)", category: "Cache")
        }
    }
    
    private nonisolated static func migratedEmail(_ email: EmailListItem) -> EmailListItem {
        EmailListItem(
            id: StableID.emailId(gmailId: email.gmail_id),
            gmail_id: email.gmail_id,
            thread_id: email.thread_id,
            subject: email.subject,
            sender: email.sender,
            sender_name: email.sender_name,
            snippet: email.snippet,
            is_read: email.is_read,
            is_starred: email.is_starred,
            labels: email.labels,
            received_at: email.received_at,
            account_email: email.account_email,
            marked_read_at: email.marked_read_at
        )
    }
}

