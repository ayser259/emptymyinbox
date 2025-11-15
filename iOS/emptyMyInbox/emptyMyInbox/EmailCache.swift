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
    
    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        baseDirectoryURL = directory.appendingPathComponent("EmailCache", isDirectory: true)
        defaultUnreadEmailsURL = baseDirectoryURL.appendingPathComponent("unread_emails.json")
        
        if !FileManager.default.fileExists(atPath: baseDirectoryURL.path) {
            try? FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Unread Emails
    
    func loadUnreadEmails(accountId: Int? = nil) -> [EmailListItem] {
        let url = unreadEmailsURL(for: accountId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([EmailListItem].self, from: data)
        } catch {
            print("EmailCache loadUnreadEmails error: \(error)")
            return []
        }
    }
    
    func saveUnreadEmails(_ emails: [EmailListItem], accountId: Int? = nil) {
        do {
            let data = try encoder.encode(emails)
            try data.write(to: unreadEmailsURL(for: accountId), options: .atomic)
        } catch {
            print("EmailCache saveUnreadEmails error: \(error)")
        }
    }
    
    func upsertUnreadEmail(_ email: EmailListItem, accountId: Int? = nil) {
        var storedEmails = loadUnreadEmails(accountId: accountId)
        
        if let index = storedEmails.firstIndex(where: { $0.id == email.id }) {
            storedEmails[index] = email
        } else {
            storedEmails.append(email)
            storedEmails.sort { $0.received_at > $1.received_at }
        }
        
        saveUnreadEmails(storedEmails, accountId: accountId)
    }
    
    func removeUnreadEmail(emailId: Int, accountId: Int? = nil) {
        var storedEmails = loadUnreadEmails(accountId: accountId)
        if let index = storedEmails.firstIndex(where: { $0.id == emailId }) {
            storedEmails.remove(at: index)
            saveUnreadEmails(storedEmails, accountId: accountId)
        }
    }
    
    // MARK: - Email Details
    
    private func detailURL(for emailId: Int) -> URL {
        baseDirectoryURL.appendingPathComponent("email_\(emailId).json")
    }
    
    func loadEmailDetail(emailId: Int) -> EmailDetail? {
        let url = detailURL(for: emailId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(EmailDetail.self, from: data)
        } catch {
            print("EmailCache loadEmailDetail error: \(error)")
            return nil
        }
    }
    
    func saveEmailDetail(_ detail: EmailDetail) {
        let url = detailURL(for: detail.id)
        
        do {
            let data = try encoder.encode(detail)
            try data.write(to: url, options: .atomic)
        } catch {
            print("EmailCache saveEmailDetail error: \(error)")
        }
    }
    
    func deleteEmailDetail(emailId: Int) {
        let url = detailURL(for: emailId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("EmailCache deleteEmailDetail error: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func unreadEmailsURL(for accountId: Int?) -> URL {
        guard let accountId = accountId else {
            return defaultUnreadEmailsURL
        }
        return baseDirectoryURL.appendingPathComponent("unread_emails_account_\(accountId).json")
    }
}


