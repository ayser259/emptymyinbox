//
//  CatchUpAccountOrderStore.swift
//  emptymyinboxMacApp
//
//  Persists the user-defined account order for the Catch Up deck.
//  Order is stored as an array of account email strings in UserDefaults.
//

import Combine
import Foundation
import SwiftUI

final class CatchUpAccountOrderStore: ObservableObject {

    @Published private(set) var orderedAccounts: [String] = []

    private let defaultsKey = "catchup.account.order"

    init() {
        orderedAccounts = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    /// Synchronise the store against the live set of known accounts.
    /// - New accounts not yet in the list are appended at the end.
    /// - Accounts that no longer exist are removed.
    /// - Existing order is preserved.
    func sync(allAccounts: [String]) {
        var result = orderedAccounts.filter { allAccounts.contains($0) }
        for account in allAccounts where !result.contains(account) {
            result.append(account)
        }
        if result != orderedAccounts {
            orderedAccounts = result
            persist()
        }
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        orderedAccounts.move(fromOffsets: fromOffsets, toOffset: toOffset)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(orderedAccounts, forKey: defaultsKey)
    }
}
