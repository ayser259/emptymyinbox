import SwiftUI

/// Local cache stats + vault management (shared iOS + macOS).
public struct SettingsStorageView<Vault: View>: View {
    @State private var cachedEmailCount: Int = 0
    @State private var showClearedAlert = false

    private let vaultSettings: () -> Vault
    private let accentColor: Color

    public init(
        vaultSettings: @escaping () -> Vault,
        accentColor: Color = SharedAppTheme.accent
    ) {
        self.vaultSettings = vaultSettings
        self.accentColor = accentColor
    }

    public var body: some View {
        List {
            Section {
                HStack {
                    SwiftUI.Label("Cached Emails", systemImage: "internaldrive")
                    Spacer()
                    Text("\(cachedEmailCount) emails")
                        .font(SharedAppTheme.caption)
                        .foregroundStyle(SharedAppTheme.secondaryText)
                }

                Button {
                    Task {
                        await DashboardCache.shared.clear()
                        await EmailCache.shared.clearAll()
                        await MainActor.run {
                            cachedEmailCount = 0
                            NotificationCenter.default.post(name: .cacheCleared, object: nil)
                            showClearedAlert = true
                        }
                    }
                } label: {
                    SwiftUI.Label("Clear Cache", systemImage: "trash")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Local Cache")
            } footer: {
                Text("Email content is stored locally for fast access and offline viewing.")
            }

            Section {
                NavigationLink {
                    vaultSettings()
                } label: {
                    HStack {
                        Image(systemName: "shippingbox")
                            .foregroundStyle(accentColor)
                        Text("Vault")
                    }
                }
            } header: {
                Text("Vault")
            } footer: {
                Text("Store Calendar and Action Items as files in Inbox, Calendar, and Action Items folders—locally, in a synced folder, or on Google Drive.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        #if os(macOS)
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .tint(accentColor)
        #endif
        .navigationTitle("Storage")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Cache cleared", isPresented: $showClearedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Local cache was removed.")
        }
        .task {
            cachedEmailCount = await EmailCache.shared.cachedEmailCount()
        }
    }
}
