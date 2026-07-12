import SwiftUI

/// Read-only keyboard shortcut reference (Mac + iPad; iPhone shows a short note).
public struct SettingsShortcutsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init() {}

    public var body: some View {
        List {
            #if os(macOS)
            shortcutSection(title: "Global", items: SettingsShortcutsReference.global)
            shortcutSection(title: "Mail", items: SettingsShortcutsReference.mailTools)
            shortcutSection(title: "Mail — Inbox", items: SettingsShortcutsReference.mailMailboxDetail)
            shortcutSection(title: "Mail — Catch Up", items: SettingsShortcutsReference.mailCatchUp)
            shortcutSection(title: "Mail — Reply composer", items: SettingsShortcutsReference.mailReplyComposer)
            shortcutSection(title: "Mail — Reply sent", items: SettingsShortcutsReference.mailReplySentOutcome)
            shortcutSection(title: "Calendar", items: SettingsShortcutsReference.calendarModes)
            shortcutSection(title: "Action Items", items: SettingsShortcutsReference.actionItems)
            #else
            if horizontalSizeClass == .compact {
                Section {
                    Text("Keyboard shortcuts are listed for iPad (with an external keyboard) and Mac. On iPhone, use the on-screen controls in each tab.")
                        .foregroundStyle(SharedAppTheme.secondaryText)
                }
            } else {
                shortcutSection(title: "Global", items: SettingsShortcutsReference.global)
                shortcutSection(title: "Mail", items: SettingsShortcutsReference.mailTools)
                shortcutSection(title: "Mail — Inbox", items: SettingsShortcutsReference.mailMailboxDetail)
                shortcutSection(title: "Mail — Catch Up", items: SettingsShortcutsReference.mailCatchUp)
                shortcutSection(title: "Mail — Reply composer", items: SettingsShortcutsReference.mailReplyComposer)
            shortcutSection(title: "Mail — Reply sent", items: SettingsShortcutsReference.mailReplySentOutcome)
                shortcutSection(title: "Calendar", items: SettingsShortcutsReference.calendarModes)
                shortcutSection(title: "Action Items", items: SettingsShortcutsReference.actionItems)
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        #if os(macOS)
        .listStyle(.inset(alternatesRowBackgrounds: false))
        #endif
        .navigationTitle("Shortcuts")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func shortcutSection(title: String, items: [SettingsShortcutReference]) -> some View {
        Section(title) {
            ForEach(items) { ref in
                HStack {
                    Text(ref.title)
                    Spacer()
                    Text(ref.shortcutDisplay)
                        .font(.body.monospaced())
                        .foregroundStyle(SharedAppTheme.secondaryText)
                }
            }
        }
    }
}
