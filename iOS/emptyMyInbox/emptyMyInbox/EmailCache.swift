//
//  EmailCache.swift
//  emptyMyInbox
//
//  Local caching layer for email data used by Catch Up.
//

import Foundation

actor EmailCache {
    static let shared = EmailCache()
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private let baseDirectoryURL: URL
    private let defaultUnreadEmailsURL: URL
    private let defaultNextPageTokenURL: URL
    
    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        baseDirectoryURL = directory.appendingPathComponent("EmailCache", isDirectory: true)
        defaultUnreadEmailsURL = baseDirectoryURL.appendingPathComponent("unread_emails.json")
        defaultNextPageTokenURL = baseDirectoryURL.appendingPathComponent("next_page_token.json")
        
        if !FileManager.default.fileExists(atPath: baseDirectoryURL.path) {
            try? FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Clear All
    
    func clearAll() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: baseDirectoryURL, includingPropertiesForKeys: nil, options: []) else {
            return
        }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }
    
    // MARK: - Unread Emails
    
    func loadUnreadEmails(accountId: Int? = nil) async -> [EmailListItem] {
        let url = unreadEmailsURL(for: accountId)
        return await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return []
            }
            
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([EmailListItem].self, from: data)
            } catch {
                print("EmailCache loadUnreadEmails error: \(error)")
                return []
            }
        }.value
    }
    
    func saveUnreadEmails(_ emails: [EmailListItem], accountId: Int? = nil) async {
        let url = unreadEmailsURL(for: accountId)
        await Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(emails)
                try data.write(to: url, options: .atomic)
            } catch {
                print("EmailCache saveUnreadEmails error: \(error)")
            }
        }.value
    }
    
    func upsertUnreadEmail(_ email: EmailListItem, accountId: Int? = nil) async {
        var storedEmails = await loadUnreadEmails(accountId: accountId)
        
        if let index = storedEmails.firstIndex(where: { $0.id == email.id }) {
            storedEmails[index] = email
        } else {
            storedEmails.append(email)
            storedEmails.sort { $0.received_at > $1.received_at }
        }
        
        await saveUnreadEmails(storedEmails, accountId: accountId)
    }
    
    func removeUnreadEmail(emailId: Int, accountId: Int? = nil) async {
        var storedEmails = await loadUnreadEmails(accountId: accountId)
        if let index = storedEmails.firstIndex(where: { $0.id == emailId }) {
            storedEmails.remove(at: index)
            await saveUnreadEmails(storedEmails, accountId: accountId)
        }
    }
    
    // MARK: - Pagination Token
    
    func loadNextPageToken(accountId: Int? = nil) async -> String? {
        let url = nextPageTokenURL(for: accountId)
        return await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(String.self, from: data)
            } catch {
                print("EmailCache loadNextPageToken error: \(error)")
                return nil
            }
        }.value
    }
    
    func saveNextPageToken(_ token: String?, accountId: Int? = nil) async {
        let url = nextPageTokenURL(for: accountId)
        
        await Task.detached(priority: .utility) {
            if let token = token {
                do {
                    let data = try JSONEncoder().encode(token)
                    try data.write(to: url, options: .atomic)
                } catch {
                    print("EmailCache saveNextPageToken error: \(error)")
                }
            } else {
                // Remove file if token is nil
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }.value
    }
    
    func clearNextPageToken(accountId: Int? = nil) async {
        await saveNextPageToken(nil, accountId: accountId)
    }
    
    // MARK: - Email Details
    
    private func detailURL(for emailId: Int) -> URL {
        baseDirectoryURL.appendingPathComponent("email_\(emailId).json")
    }
    
    func loadEmailDetail(emailId: Int) async -> EmailDetail? {
        let url = detailURL(for: emailId)
        return await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(EmailDetail.self, from: data)
            } catch {
                print("EmailCache loadEmailDetail error: \(error)")
                return nil
            }
        }.value
    }
    
    func saveEmailDetail(_ detail: EmailDetail) async {
        let url = detailURL(for: detail.id)
        
        await Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(detail)
                try data.write(to: url, options: .atomic)
            } catch {
                print("EmailCache saveEmailDetail error: \(error)")
            }
        }.value
    }
    
    func deleteEmailDetail(emailId: Int) async {
        let url = detailURL(for: emailId)
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }
            
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("EmailCache deleteEmailDetail error: \(error)")
            }
        }.value
    }
    
    // MARK: - Helpers
    
    private func unreadEmailsURL(for accountId: Int?) -> URL {
        guard let accountId = accountId else {
            return defaultUnreadEmailsURL
        }
        return baseDirectoryURL.appendingPathComponent("unread_emails_account_\(accountId).json")
    }
    
    private func nextPageTokenURL(for accountId: Int?) -> URL {
        guard let accountId = accountId else {
            return defaultNextPageTokenURL
        }
        return baseDirectoryURL.appendingPathComponent("next_page_token_account_\(accountId).json")
    }
}


