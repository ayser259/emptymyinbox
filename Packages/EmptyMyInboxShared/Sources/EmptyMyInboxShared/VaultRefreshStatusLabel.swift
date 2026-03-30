//
//  VaultRefreshStatusLabel.swift
//  EmptyMyInboxShared
//

import SwiftUI

/// Shows when the vault last completed a full lifecycle sync (Drive: pull+push; other backends: local refresh + bookkeeping).
public struct VaultRefreshStatusLabel: View {
    @ObservedObject private var vaultManager = VaultManager.shared
    private let font: Font

    public init(font: Font = .caption) {
        self.font = font
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let t = vaultManager.lastSuccessfulSyncAt {
                Text("Vault last refreshed \(t.formatted(date: .abbreviated, time: .shortened))")
                    .font(font)
                    .foregroundStyle(.secondary)
            } else {
                Text("Vault not refreshed yet")
                    .font(font)
                    .foregroundStyle(.secondary)
            }
            if let err = vaultManager.lastSyncErrorMessage {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
