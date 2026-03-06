//
//  DashboardCache.swift
//  emptyMyInbox
//
//  Persists dashboard data (accounts, emails, labels, starred) locally.
//

import Foundation

struct DashboardDataSnapshot: Codable {
    let timestamp: Date
    let accounts: [EmailAccount]
    let emails: [EmailListItem]
    let allEmails: [EmailListItem]
    let starredEmails: [EmailListItem]
    let labels: [Label]
}

actor DashboardCache {
    static let shared = DashboardCache()
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
    
    func loadSnapshot() -> DashboardDataSnapshot? {
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
    
    func saveSnapshot(accounts: [EmailAccount],
                      emails: [EmailListItem],
                      allEmails: [EmailListItem],
                      starredEmails: [EmailListItem],
                      labels: [Label]) {
        let snapshot = DashboardDataSnapshot(
            timestamp: Date(),
            accounts: accounts,
            emails: emails,
            allEmails: allEmails,
            starredEmails: starredEmails,
            labels: labels
        )
        saveSnapshot(snapshot)
    }
    
    func saveSnapshot(_ snapshot: DashboardDataSnapshot) {
        pendingSnapshot = snapshot
        scheduleSave()
    }
    
    func clear() {
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

