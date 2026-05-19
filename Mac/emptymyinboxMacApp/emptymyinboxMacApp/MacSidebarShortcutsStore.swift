//
//  MacSidebarShortcutsStore.swift
//  emptymyinboxMacApp
//
//  Central registry for contextual sidebar shortcuts. Views register layers for the
//  current screen; the sidebar shows all active layers, highest priority first.
//

import Combine
import SwiftUI

@MainActor
final class MacSidebarShortcutsStore: ObservableObject {

    struct Layer: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let shortcuts: [MacSidebarContextualShortcut]
        let priority: Int
    }

    @Published private var layersByID: [String: Layer] = [:]

    var orderedFeatureSections: [MacSidebarFeatureShortcutSection] {
        layersByID.values
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map { MacSidebarFeatureShortcutSection(title: $0.title, shortcuts: $0.shortcuts) }
    }

    var hasFeatureShortcuts: Bool {
        layersByID.values.contains { !$0.shortcuts.isEmpty }
    }

    func setLayer(
        id: String,
        title: String,
        shortcuts: [MacSidebarContextualShortcut],
        priority: Int = 0
    ) {
        let layer = Layer(id: id, title: title, shortcuts: shortcuts, priority: priority)
        guard layersByID[id] != layer else { return }
        layersByID[id] = layer
    }

    func removeLayer(id: String) {
        guard layersByID[id] != nil else { return }
        layersByID.removeValue(forKey: id)
    }

    func removeLayers(withPrefix prefix: String) {
        let keys = layersByID.keys.filter { $0.hasPrefix(prefix) }
        guard !keys.isEmpty else { return }
        for key in keys {
            layersByID.removeValue(forKey: key)
        }
    }

    func clearAll() {
        guard !layersByID.isEmpty else { return }
        layersByID = [:]
    }
}
