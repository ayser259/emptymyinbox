//
//  RefreshProgress.swift
//  emptyMyInbox
//
//  Progress tracking for refresh operations
//

import Foundation
import SwiftUI

enum RefreshStage: String, Identifiable, CaseIterable {
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
    
    var id: String { rawValue }
    
    var description: String {
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

struct RefreshProgressItem: Identifiable {
    let id: UUID
    let stage: RefreshStage
    var status: ProgressStatus
    var detail: String?
    var accountEmail: String?
    var currentCount: Int?
    var totalCount: Int?
    
    init(stage: RefreshStage, status: ProgressStatus = .pending, detail: String? = nil, accountEmail: String? = nil, currentCount: Int? = nil, totalCount: Int? = nil) {
        self.id = UUID()
        self.stage = stage
        self.status = status
        self.detail = detail
        self.accountEmail = accountEmail
        self.currentCount = currentCount
        self.totalCount = totalCount
    }
}

enum ProgressStatus {
    case pending
    case inProgress
    case completed
    case failed(String)
    
    var isCompleted: Bool {
        if case .completed = self {
            return true
        }
        return false
    }
    
    var isInProgress: Bool {
        if case .inProgress = self {
            return true
        }
        return false
    }
    
    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}

@MainActor
class RefreshProgressTracker: ObservableObject {
    @Published var items: [RefreshProgressItem] = []
    @Published var isVisible = false
    @Published var overallProgress: Double = 0.0
    
    private var stageMap: [RefreshStage: RefreshProgressItem] = [:]
    
    init() {
        // Initialize all stages as pending
        for stage in RefreshStage.allCases {
            let item = RefreshProgressItem(stage: stage, status: .pending)
            items.append(item)
            stageMap[stage] = item
        }
    }
    
    func updateStage(_ stage: RefreshStage, status: ProgressStatus, detail: String? = nil, accountEmail: String? = nil, currentCount: Int? = nil, totalCount: Int? = nil) {
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
    
    func reset() {
        items = RefreshStage.allCases.map { RefreshProgressItem(stage: $0, status: .pending) }
        stageMap = Dictionary(uniqueKeysWithValues: items.map { ($0.stage, $0) })
        overallProgress = 0.0
    }
    
    private func updateOverallProgress() {
        let completedCount = items.filter { $0.status.isCompleted }.count
        let totalCount = items.count
        overallProgress = Double(completedCount) / Double(totalCount)
    }
    
    func show() {
        isVisible = true
    }
    
    func hide() {
        isVisible = false
    }
}

