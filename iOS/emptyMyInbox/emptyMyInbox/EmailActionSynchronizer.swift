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
        }
        
        let id: UUID
        let emailId: Int
        let kind: Kind
        let createdAt: Date
        
        init(emailId: Int, kind: Kind, createdAt: Date = Date()) {
            self.id = UUID()
            self.emailId = emailId
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
    
    func enqueueStar(emailId: Int, shouldStar: Bool) {
        let kind: PendingAction.Kind = shouldStar ? .star : .unstar
        enqueue(PendingAction(emailId: emailId, kind: kind))
    }
    
    func enqueueMarkRead(emailId: Int) {
        enqueue(PendingAction(emailId: emailId, kind: .markRead))
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
        switch action.kind {
        case .star:
            _ = try await APIService.shared.starEmail(emailId: action.emailId)
        case .unstar:
            _ = try await APIService.shared.unstarEmail(emailId: action.emailId)
        case .markRead:
            _ = try await APIService.shared.markEmailAsRead(emailId: action.emailId)
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



