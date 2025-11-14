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
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL
    
    private init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        fileURL = directory.appendingPathComponent("dashboard_snapshot.json")
    }
    
    func loadSnapshot() -> DashboardDataSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(DashboardDataSnapshot.self, from: data)
        } catch {
            print("DashboardCache load error: \(error)")
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
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("DashboardCache save error: \(error)")
        }
    }
    
    func clear() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("DashboardCache clear error: \(error)")
        }
    }
}

