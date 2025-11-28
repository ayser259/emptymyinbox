//
//  EmailActionSynchronizer.swift
//  emptyMyInbox
//
//  Handles background synchronization of email side-effect actions,
//  supporting offline queuing and retry behaviour.
//

import Foundation

actor EmailActionSynchronizer {
    static let shared = EmailActionSynchronizer()
    
    struct PendingAction: Codable, Identifiable {
        enum Kind: String, Codable {
            case star
            case unstar
            case markRead
            case markUnread
        }
        
        let id: UUID
        let emailId: Int
        let gmailId: String
        let accountEmail: String
        let kind: Kind
        let createdAt: Date
        
        init(emailId: Int, gmailId: String, accountEmail: String, kind: Kind, createdAt: Date = Date()) {
            self.id = UUID()
            self.emailId = emailId
            self.gmailId = gmailId
            self.accountEmail = accountEmail
            self.kind = kind
            self.createdAt = createdAt
        }
    }
    
    private let queueFileURL: URL
    
    private var pendingActions: [PendingAction] = []
    private var isProcessing = false
    private let retryDelayNanoseconds: UInt64 = 5 * 1_000_000_000 // 5 seconds
    
    private init() {
        let fileManager = FileManager.default
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let actionDirectory = directory.appendingPathComponent("EmailCache", isDirectory: true)
        
        if !fileManager.fileExists(atPath: actionDirectory.path) {
            try? fileManager.createDirectory(at: actionDirectory, withIntermediateDirectories: true)
        }
        
        queueFileURL = actionDirectory.appendingPathComponent("pending_actions.json")
        pendingActions = Self.loadQueueFromDisk(from: queueFileURL)
        if !pendingActions.isEmpty {
            Task {
                await self.scheduleProcessingIfNeeded()
            }
        }
    }
    
    func enqueueStar(emailId: Int, gmailId: String, accountEmail: String, shouldStar: Bool) {
        let kind: PendingAction.Kind = shouldStar ? .star : .unstar
        enqueue(PendingAction(emailId: emailId, gmailId: gmailId, accountEmail: accountEmail, kind: kind))
    }
    
    func enqueueMarkRead(emailId: Int, gmailId: String, accountEmail: String) {
        enqueue(PendingAction(emailId: emailId, gmailId: gmailId, accountEmail: accountEmail, kind: .markRead))
    }
    
    func enqueueMarkUnread(emailId: Int, gmailId: String, accountEmail: String) {
        enqueue(PendingAction(emailId: emailId, gmailId: gmailId, accountEmail: accountEmail, kind: .markUnread))
    }
    
    func resumePendingActions() {
        scheduleProcessingIfNeeded()
    }
    
    // MARK: - Private Helpers
    
    private func enqueue(_ action: PendingAction) {
        pendingActions.append(action)
        persistQueue()
        scheduleProcessingIfNeeded()
    }
    
    private func scheduleProcessingIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            await self.processQueue()
        }
    }
    
    private func processQueue() async {
        defer { isProcessing = false }
        
        while !pendingActions.isEmpty {
            let action = pendingActions[0]
            
            do {
                try await perform(action)
                pendingActions.removeFirst()
                persistQueue()
            } catch {
                print("EmailActionSynchronizer failed to process action \(action.id): \(error)")
                persistQueue()
                try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            }
        }
    }
    
    private func perform(_ action: PendingAction) async throws {
        let gmailService = GmailAPIService.shared
        guard let account = gmailService.getAccount(byEmail: action.accountEmail) else {
            throw NSError(domain: "EmailActionSynchronizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Account not found"])
        }
        
        switch action.kind {
        case .star:
            try await gmailService.starMessage(for: account, messageId: action.gmailId)
        case .unstar:
            try await gmailService.unstarMessage(for: account, messageId: action.gmailId)
        case .markRead:
            try await gmailService.markAsRead(for: account, messageId: action.gmailId)
        case .markUnread:
            try await gmailService.markAsUnread(for: account, messageId: action.gmailId)
        }
    }
    
    private func persistQueue() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(pendingActions)
            try data.write(to: queueFileURL, options: .atomic)
        } catch {
            print("EmailActionSynchronizer persistQueue error: \(error)")
        }
    }
    
    private static func loadQueueFromDisk(from url: URL) -> [PendingAction] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([PendingAction].self, from: data)
        } catch {
            print("EmailActionSynchronizer loadQueueFromDisk error: \(error)")
            return []
        }
    }
}



