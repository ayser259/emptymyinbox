import SwiftUI

/// Obsidian-style settings: sidebar + detail (shared iOS + macOS).
public struct SettingsContainerView<Vault: View>: View {
    @EnvironmentObject public var authManager: AuthManager

    @Binding public var isAddingAccount: Bool
    @State private var selectedPane: SettingsSidebarItem = .general
    @State private var showClearCacheConfirm = false
    @State private var showSignOutConfirm = false
    @State private var showCacheClearedAlert = false
    @State private var configuredAPIKeyCount = 0

    private let vaultSettings: () -> Vault
    private let onAddGmailAccount: () -> Void
    private let onDismiss: () -> Void
    private let accentColor: Color

    public init(
        vaultSettings: @escaping () -> Vault,
        isAddingAccount: Binding<Bool>,
        onAddGmailAccount: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        accentColor: Color = SharedAppTheme.accent
    ) {
        self.vaultSettings = vaultSettings
        self._isAddingAccount = isAddingAccount
        self.onAddGmailAccount = onAddGmailAccount
        self.onDismiss = onDismiss
        self.accentColor = accentColor
    }

    public var body: some View {
        VStack(spacing: 0) {
            settingsChromeBar
            NavigationSplitView {
                NavigationStack {
                    sidebar
                }
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 300)
                #endif
            } detail: {
                NavigationStack {
                    detailView(for: selectedPane)
                        .id(selectedPane)
                }
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 420, ideal: 560, max: 900)
                #endif
            }
        }
        .background(SharedAppTheme.primaryBackground)
        .tint(accentColor)
        #if os(macOS)
        .onExitCommand {
            onDismiss()
        }
        #endif
        .alert("Clear local cache?", isPresented: $showClearCacheConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Cache", role: .destructive) {
                Task {
                    await DashboardCache.shared.clear()
                    await EmailCache.shared.clearAll()
                    await MainActor.run {
                        NotificationCenter.default.post(name: .cacheCleared, object: nil)
                        showCacheClearedAlert = true
                    }
                }
            }
        } message: {
            Text("Removes cached dashboard data and downloaded email bodies from this device.")
        }
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                authManager.logout()
                onDismiss()
            }
        } message: {
            Text("This will disconnect all accounts and clear local session data.")
        }
        .alert("Cache cleared", isPresented: $showCacheClearedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Local cache was removed.")
        }
        .task {
            await refreshConfiguredAPIKeyCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .llmAPIKeyChanged)) { _ in
            Task { await refreshConfiguredAPIKeyCount() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .claudeAPIKeyChanged)) { _ in
            Task { await refreshConfiguredAPIKeyCount() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .geminiAPIKeyChanged)) { _ in
            Task { await refreshConfiguredAPIKeyCount() }
        }
    }

    /// Sheet toolbars on `NavigationSplitView` are often invisible on macOS; this bar is always visible.
    private var settingsChromeBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Settings")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SharedAppTheme.primaryText)
                Spacer(minLength: 0)
                Button {
                    onDismiss()
                } label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .tint(accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(SharedAppTheme.secondaryBackground.opacity(0.55))

            Divider()
                .opacity(0.35)
        }
    }

    /// Explicit buttons (not `List(selection:)`) so iOS/macOS both get reliable taps + selection styling.
    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(SettingsSidebarItem.allCases) { item in
                        sidebarRow(item)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            sidebarFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharedAppTheme.primaryBackground)
    }

    private func sidebarRow(_ item: SettingsSidebarItem) -> some View {
        let isSelected = selectedPane == item
        return Button {
            selectedPane = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? accentColor : SharedAppTheme.secondaryText)
                    .frame(width: 22, alignment: .center)
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(SharedAppTheme.primaryText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if item == .keys, configuredAPIKeyCount > 0 {
                    Text(keysSidebarBadge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(accentColor.opacity(0.18))
                        )
                        .accessibilityLabel("\(configuredAPIKeyCount) API keys saved")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.07) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                        .padding(.leading, 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Pinned to the bottom of the sidebar; native bordered buttons (not list rows).
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .opacity(0.35)
            Button {
                showClearCacheConfirm = true
            } label: {
                Label("Clear Cache", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Label("Sign Out", systemImage: "arrow.right.square")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SharedAppTheme.secondaryBackground.opacity(0.92))
    }

    private var keysSidebarBadge: String {
        configuredAPIKeyCount == 1 ? "1 added" : "\(configuredAPIKeyCount) added"
    }

    private func refreshConfiguredAPIKeyCount() async {
        var count = 0
        if await LLMSettingsStore.shared.hasAPIKey() { count += 1 }
        if await GeminiAPIKeyStore.shared.hasAPIKey() { count += 1 }
        if await ClaudeAPIKeyStore.shared.hasAPIKey() { count += 1 }
        await MainActor.run {
            configuredAPIKeyCount = count
        }
    }

    @ViewBuilder
    private func detailView(for item: SettingsSidebarItem) -> some View {
        switch item {
        case .general:
            SettingsGeneralView()
        case .connectedAccounts:
            SettingsConnectedAccountsView(
                isAddingAccount: $isAddingAccount,
                accentColor: accentColor,
                onAddGmailAccount: onAddGmailAccount
            )
        case .shortcuts:
            SettingsShortcutsView()
        case .storage:
            SettingsStorageView(vaultSettings: vaultSettings, accentColor: accentColor)
        case .keys:
            SettingsKeysView()
        case .corePlugins:
            SettingsCorePluginsView()
        }
    }
}
