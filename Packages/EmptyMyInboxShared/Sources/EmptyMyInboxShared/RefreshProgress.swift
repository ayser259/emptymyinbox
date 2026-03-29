//
//  RefreshProgress.swift
//  emptyMyInbox
//
//  Progress tracking for refresh operations
//

import Foundation
import SwiftUI

public enum RefreshStage: String, Identifiable, CaseIterable {
    case initializing = "Initializing refresh"
    case loadingCache = "Loading existing cache"
    case syncingAccounts = "Syncing accounts"
    case fetchingUnread = "Fetching unread emails"
    case fetchingStarred = "Fetching starred emails"
    case processingData = "Processing data"
    case mergingEmails = "Merging with existing emails"
    case filteringOld = "Filtering old emails"
    case countingLabels = "Counting labels"
    case savingCache = "Saving to cache"
    case savingSnapshot = "Saving snapshot"
    case complete = "Complete"
    
    public var id: String { rawValue }
    
    public var description: String {
        switch self {
        case .initializing:
            return "Preparing refresh operation"
        case .loadingCache:
            return "Loading existing email data from cache"
        case .syncingAccounts:
            return "Syncing with Gmail accounts"
        case .fetchingUnread:
            return "Fetching unread emails from Gmail"
        case .fetchingStarred:
            return "Fetching starred emails from Gmail"
        case .processingData:
            return "Processing fetched data"
        case .mergingEmails:
            return "Merging new emails with existing data"
        case .filteringOld:
            return "Removing emails older than 10 days"
        case .countingLabels:
            return "Counting emails per label"
        case .savingCache:
            return "Saving emails to local cache"
        case .savingSnapshot:
            return "Saving final snapshot"
        case .complete:
            return "Refresh completed successfully"
        }
    }
}

public struct RefreshProgressItem: Identifiable {
    public let id: UUID
    public let stage: RefreshStage
    public var status: ProgressStatus
    public var detail: String?
    public var accountEmail: String?
    public var currentCount: Int?
    public var totalCount: Int?
    
    public init(stage: RefreshStage, status: ProgressStatus = .pending, detail: String? = nil, accountEmail: String? = nil, currentCount: Int? = nil, totalCount: Int? = nil) {
        self.id = UUID()
        self.stage = stage
        self.status = status
        self.detail = detail
        self.accountEmail = accountEmail
        self.currentCount = currentCount
        self.totalCount = totalCount
    }
}

public enum ProgressStatus {
    case pending
    case inProgress
    case completed
    case failed(String)
    
    public var isCompleted: Bool {
        if case .completed = self {
            return true
        }
        return false
    }
    
    public var isInProgress: Bool {
        if case .inProgress = self {
            return true
        }
        return false
    }
    
    public var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}

@MainActor
public class RefreshProgressTracker: ObservableObject {
    @Published public var items: [RefreshProgressItem] = []
    @Published public var isVisible = false
    @Published public var overallProgress: Double = 0.0
    
    private var stageMap: [RefreshStage: RefreshProgressItem] = [:]
    
    public init() {
        // Initialize all stages as pending
        for stage in RefreshStage.allCases {
            let item = RefreshProgressItem(stage: stage, status: .pending)
            items.append(item)
            stageMap[stage] = item
        }
    }
    
    public func updateStage(_ stage: RefreshStage, status: ProgressStatus, detail: String? = nil, accountEmail: String? = nil, currentCount: Int? = nil, totalCount: Int? = nil) {
        if let index = items.firstIndex(where: { $0.stage == stage }) {
            var updatedItem = items[index]
            updatedItem.status = status
            updatedItem.detail = detail
            updatedItem.accountEmail = accountEmail
            updatedItem.currentCount = currentCount
            updatedItem.totalCount = totalCount
            items[index] = updatedItem
            stageMap[stage] = updatedItem
        }
        updateOverallProgress()
    }
    
    public func reset() {
        items = RefreshStage.allCases.map { RefreshProgressItem(stage: $0, status: .pending) }
        stageMap = Dictionary(uniqueKeysWithValues: items.map { ($0.stage, $0) })
        overallProgress = 0.0
    }
    
    private func updateOverallProgress() {
        let completedCount = items.filter { $0.status.isCompleted }.count
        let totalCount = items.count
        overallProgress = Double(completedCount) / Double(totalCount)
    }
    
    public func show() {
        isVisible = true
    }
    
    public func hide() {
        isVisible = false
    }
}

