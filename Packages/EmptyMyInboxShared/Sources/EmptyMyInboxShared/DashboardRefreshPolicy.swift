//
//  DashboardRefreshPolicy.swift
//  EmptyMyInboxShared
//
//  Universal mail auto-refresh policy: show cache immediately, sync only when stale or missing.
//

import Foundation

/// Shared rules for when the mail shell should auto-sync Gmail into the dashboard snapshot.
public enum DashboardRefreshPolicy {
    /// Auto-sync when the cached snapshot is older than this interval.
    public static let mailAutoRefreshInterval: TimeInterval = 15 * 60

    /// Returns `true` when there is no snapshot or it is older than `mailAutoRefreshInterval`.
    public static func shouldAutoSync(snapshot: DashboardDataSnapshot?, now: Date = Date()) -> Bool {
        guard let snapshot else { return true }
        return now.timeIntervalSince(snapshot.timestamp) >= mailAutoRefreshInterval
    }
}
