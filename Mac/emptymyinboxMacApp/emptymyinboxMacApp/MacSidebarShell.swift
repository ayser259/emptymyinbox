//
//  MacSidebarShell.swift
//  emptymyinboxMacApp
//
//  Shared sidebar chrome: scrollable `List` + pinned **Refresh** + **Settings** (matches Mail row styling).
//

import SwiftUI

/// One row in the sidebar **Shortcuts** panel (keyboard hints for the current screen).
struct MacSidebarContextualShortcut: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// Human-readable shortcut, e.g. `E`, `⌘R`, `⌘⇧U`.
    let shortcutDisplay: String

    init(title: String, shortcutDisplay: String) {
        self.title = title
        self.shortcutDisplay = shortcutDisplay
        self.id = "\(title)-\(shortcutDisplay)"
    }
}

/// Feature-specific shortcuts shown **above** the global block in the sidebar (e.g. Catch Up, Calendar, Action Items).
struct MacSidebarFeatureShortcutSection: Equatable, Sendable {
    let title: String
    let shortcuts: [MacSidebarContextualShortcut]
}

/// Asset names in `Assets.xcassets` for Action Items **Categories** parent rows (Priority, Urgency, Labels, Projects).
enum MacActionItemsCategorySidebarAsset {
    static let priority = "ActionItemsCategoryPriority"
    static let urgency = "ActionItemsCategoryUrgency"
    static let labels = "ActionItemsCategoryLabels"
    static let projects = "ActionItemsCategoryProjects"
}

/// Leading icon for `MacSidebarListRowButton`: SF Symbol or catalog image.
enum MacSidebarListRowIcon: Equatable, Sendable {
    case system(String)
    case asset(String)
}

/// Leading label + optional inset, shared by sidebar rows and custom category rows with menus.
struct MacSidebarRowLeadingContent: View {
    var leadingInset: CGFloat = 0
    let title: String
    let icon: MacSidebarListRowIcon

    var body: some View {
        HStack(spacing: 8) {
            if leadingInset > 0 {
                Color.clear.frame(width: leadingInset)
            }
            switch icon {
            case .system(let name):
                Label(title, systemImage: name)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .asset(let name):
                HStack(spacing: 8) {
                    Image(name)
                        .renderingMode(.original)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 17, height: 17)
                    Text(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Primary-tab sidebar: scrollable sections plus optional **pinned** accessory (e.g. mini calendar), then Refresh + Settings.
struct MacSidebarShell<Content: View>: View {
    var minColumnWidth: CGFloat = 220
    var idealColumnWidth: CGFloat = 240
    var maxColumnWidth: CGFloat = 280
    /// Optional feature-specific shortcuts (Catch Up, Calendar modes, Action Items syntax, …). Shown **above** global shortcuts.
    var featureShortcutSection: MacSidebarFeatureShortcutSection? = nil
    /// App-wide shortcuts (navigation, refresh, next tab). Shown **below** feature shortcuts.
    var globalShortcuts: [MacSidebarContextualShortcut] = MacSidebarShortcutLibrary.global
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void
    /// Pinned between the scrolling list and the Refresh/Settings footer (e.g. mini month).
    var bottomAccessory: (() -> AnyView)?
    @ViewBuilder var content: () -> Content

    @AppStorage("MacSidebarContextualShortcutsExpanded") private var shortcutsSectionExpanded = true

    init(
        minColumnWidth: CGFloat = 220,
        idealColumnWidth: CGFloat = 240,
        maxColumnWidth: CGFloat = 280,
        featureShortcutSection: MacSidebarFeatureShortcutSection? = nil,
        globalShortcuts: [MacSidebarContextualShortcut] = MacSidebarShortcutLibrary.global,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        bottomAccessory: (() -> AnyView)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.minColumnWidth = minColumnWidth
        self.idealColumnWidth = idealColumnWidth
        self.maxColumnWidth = maxColumnWidth
        self.featureShortcutSection = featureShortcutSection
        self.globalShortcuts = globalShortcuts
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        self.bottomAccessory = bottomAccessory
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                content()
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(MacAppTheme.primaryBackground)

            if let bottomAccessory {
                bottomAccessory()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacAppTheme.primaryBackground)
            }

            Divider()
                .opacity(0.35)

            if !globalShortcuts.isEmpty || !(featureShortcutSection?.shortcuts.isEmpty ?? true) {
                MacSidebarShortcutsPanel(
                    featureSection: featureShortcutSection,
                    globalShortcuts: globalShortcuts,
                    isExpanded: $shortcutsSectionExpanded
                )
                Divider()
                    .opacity(0.35)
            }

            VStack(spacing: 0) {
                MacSidebarFooterButton(
                    title: "Refresh",
                    systemImage: "arrow.clockwise",
                    shortcutHint: "⌘R",
                    action: onRefresh
                )
                MacSidebarFooterButton(title: "Settings", systemImage: "gearshape.fill", action: onOpenSettings)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MacAppTheme.secondaryBackground.opacity(0.55))
        }
        .navigationSplitViewColumnWidth(min: minColumnWidth, ideal: idealColumnWidth, max: maxColumnWidth)
    }
}

private struct MacSidebarShortcutsPanel: View {
    let featureSection: MacSidebarFeatureShortcutSection?
    let globalShortcuts: [MacSidebarContextualShortcut]
    @Binding var isExpanded: Bool

    private var showsFeatureBlock: Bool {
        guard let featureSection else { return false }
        return !featureSection.shortcuts.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MacAppTheme.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("Shortcuts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MacAppTheme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let featureSection, !featureSection.shortcuts.isEmpty {
                    subsectionTitle(featureSection.title)
                        .padding(.top, 4)
                    ForEach(featureSection.shortcuts) { item in
                        shortcutRow(item)
                    }
                }

                subsectionTitle("Global")
                    .padding(.top, showsFeatureBlock ? 10 : 4)
                ForEach(globalShortcuts) { item in
                    shortcutRow(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacAppTheme.primaryBackground)
    }

    private func subsectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MacAppTheme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
    }

    private func shortcutRow(_ item: MacSidebarContextualShortcut) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item.title)
                .font(.caption)
                .foregroundStyle(MacAppTheme.primaryText)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(item.shortcutDisplay)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(MacAppTheme.secondaryText.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

/// A Mail-style selectable row inside a sidebar `List` (accent when selected, neutral selection background).
struct MacSidebarListRowButton: View {
    var leadingInset: CGFloat = 0
    /// When `false`, selected row uses primary text + semibold instead of accent (quieter Calendar Tools strip).
    var accentWhenSelected: Bool = true
    let title: String
    let icon: MacSidebarListRowIcon
    let isSelected: Bool
    /// Optional count badge shown on the trailing edge (hidden when nil or 0).
    var badge: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                MacSidebarRowLeadingContent(leadingInset: leadingInset, title: title, icon: icon)
                if let count = badge, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? MacAppTheme.accent : MacAppTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected
                                      ? MacAppTheme.accent.opacity(0.15)
                                      : MacAppTheme.secondaryText.opacity(0.12))
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundForSelection)
        .fontWeight(fontWeightForSelection)
        .listRowBackground(isSelected ? MacAppTheme.sidebarSelectionBackground : Color.clear)
    }

    private var foregroundForSelection: Color {
        if isSelected {
            return accentWhenSelected ? MacAppTheme.accent : MacAppTheme.primaryText
        }
        return MacAppTheme.primaryText
    }

    private var fontWeightForSelection: Font.Weight {
        if isSelected && !accentWhenSelected { return .semibold }
        return .regular
    }
}

private struct MacSidebarFooterButton: View {
    let title: String
    let systemImage: String
    var shortcutHint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let shortcutHint {
                    Text(shortcutHint)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(MacAppTheme.secondaryText.opacity(0.45))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(MacAppTheme.primaryText)
    }
}
