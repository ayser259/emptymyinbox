import SwiftUI

/// About, debug mode, and debug logs (shared iOS + macOS).
public struct SettingsGeneralView: View {
    @ObservedObject private var debugSettings = DebugSettings.shared

    public init() {}

    public var body: some View {
        #if os(macOS)
        Form {
            Section {
                LabeledContent("Version", value: appVersionString)
                LabeledContent("Build", value: "Alpha")
            } header: {
                Text("About")
            }

            Section {
                Toggle(isOn: $debugSettings.isDebugModeEnabled) {
                    HStack {
                        Image(systemName: "hammer.fill")
                            .foregroundStyle(debugSettings.isDebugModeEnabled ? .purple : SharedAppTheme.secondaryText)
                        Text("Debug Mode")
                    }
                }
                .tint(.purple)

                NavigationLink {
                    DebugLogView()
                } label: {
                    HStack {
                        SwiftUI.Label("Debug Logs", systemImage: "ladybug")
                        Spacer()
                        Text("\(DebugLogger.shared.entries.count)")
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                    }
                }
            } header: {
                Text("Developer")
            } footer: {
                if debugSettings.isDebugModeEnabled {
                    Text("Debug mode is ON. Copy buttons will appear in email views.")
                        .foregroundStyle(.purple)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        .navigationTitle("General")
        #else
        List {
            Section {
                LabeledContent("Version", value: appVersionString)
                LabeledContent("Build", value: "Alpha")
            } header: {
                Text("About")
            }

            Section {
                Toggle(isOn: $debugSettings.isDebugModeEnabled) {
                    HStack {
                        Image(systemName: "hammer.fill")
                            .foregroundStyle(debugSettings.isDebugModeEnabled ? .purple : SharedAppTheme.secondaryText)
                        Text("Debug Mode")
                    }
                }
                .tint(.purple)

                NavigationLink {
                    DebugLogView()
                } label: {
                    HStack {
                        SwiftUI.Label("Debug Logs", systemImage: "ladybug")
                        Spacer()
                        Text("\(DebugLogger.shared.entries.count)")
                            .font(SharedAppTheme.caption)
                            .foregroundStyle(SharedAppTheme.secondaryText)
                    }
                }
            } header: {
                Text("Developer")
            } footer: {
                if debugSettings.isDebugModeEnabled {
                    Text("Debug mode is ON. Copy buttons will appear in email views.")
                        .foregroundStyle(.purple)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(SharedAppTheme.primaryBackground)
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var appVersionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let short, let build, build != short {
            return "\(short) (\(build))"
        }
        return short ?? build ?? "—"
    }
}
