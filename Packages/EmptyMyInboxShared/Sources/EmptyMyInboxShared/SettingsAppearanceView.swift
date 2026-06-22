import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Appearance preferences: app name, icons, and color scheme (shared iOS + macOS).
public struct SettingsAppearanceView: View {
    @ObservedObject private var appearance = AppearanceSettingsStore.shared
    @State private var showResetConfirm = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                brandingSection
                iconSection
                colorSchemeSection
                paletteSection
                customColorsSection
                previewSection
                resetSection
            }
            .padding(20)
        }
        .background(SharedAppTheme.primaryBackground)
        .navigationTitle("Appearance")
        .alert("Reset appearance?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                appearance.resetToDefaults()
            }
        } message: {
            Text("Restores the default app name, icons, and gold color theme.")
        }
    }

    private var brandingSection: some View {
        appearanceSection(title: "App Name", footer: "Shown inside the app. The Home Screen / Dock name is set when the app is installed.") {
            TextField("App name", text: $appearance.displayName)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            appearanceSection(title: "In-App Logo") {
                iconChoiceGrid(
                    choices: AppIconRegistry.inAppLogos.map { ($0.id, $0.title) },
                    selectedID: appearance.logoChoiceID
                ) { id in
                    appearance.logoChoiceID = id
                } label: { id in
                    inAppLogoPreview(for: AppIconRegistry.inAppLogo(withID: id), size: 44)
                }
            }

            #if os(iOS)
            if AppIconService.supportsAlternateIcons {
                appearanceSection(
                    title: "Home Screen Icon",
                    footer: "iOS shows a confirmation when the icon changes."
                ) {
                    iconChoiceGrid(
                        choices: AppIconRegistry.iosOSIcons.map { ($0.id, $0.title) },
                        selectedID: appearance.iosOSIconChoiceID
                    ) { id in
                        appearance.iosOSIconChoiceID = id
                    } label: { id in
                        osIconPreview(for: AppIconRegistry.iosOSIcon(withID: id), size: 44)
                    }
                }
            }
            #endif

            #if os(macOS)
            appearanceSection(
                title: "Dock Icon",
                footer: "Changes the running app icon in the Dock. Finder still shows the bundled app icon."
            ) {
                iconChoiceGrid(
                    choices: AppIconRegistry.macDockIcons.map { ($0.id, $0.title) },
                    selectedID: appearance.macDockIconChoiceID
                ) { id in
                    appearance.macDockIconChoiceID = id
                } label: { id in
                    osIconPreview(for: AppIconRegistry.macDockIcon(withID: id), size: 44)
                }
            }
            #endif
        }
    }

    private var colorSchemeSection: some View {
        appearanceSection(title: "Color Scheme") {
            Picker("Appearance", selection: $appearance.colorSchemeMode) {
                ForEach(AppearanceColorSchemeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var paletteSection: some View {
        appearanceSection(title: "Theme Presets", footer: "Pick a preset or customize hex colors below.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                ForEach(AppThemePalette.presets) { preset in
                    Button {
                        appearance.selectPreset(preset)
                    } label: {
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(HexColorUtilities.color(from: preset.accentHex))
                                .frame(height: 36)
                                .overlay(alignment: .trailing) {
                                    Circle()
                                        .fill(HexColorUtilities.color(from: preset.primaryBackgroundHex))
                                        .frame(width: 18, height: 18)
                                        .overlay(
                                            Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                        .offset(x: -6, y: 6)
                                }
                            Text(preset.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(SharedAppTheme.primaryText)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isPresetSelected(preset) ? appearance.resolvedPalette.accent.opacity(0.18) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    isPresetSelected(preset) ? appearance.resolvedPalette.accent : Color.white.opacity(0.08),
                                    lineWidth: isPresetSelected(preset) ? 2 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var customColorsSection: some View {
        appearanceSection(title: "Custom Colors", footer: "Enter 6-digit hex codes (e.g. #F6AC0A). Invalid values fall back to defaults.") {
            hexField("Accent", value: binding(\.accentHex))
            hexField("Accent pressed", value: binding(\.accentPressedHex))
            hexField("Primary background", value: binding(\.primaryBackgroundHex))
            hexField("Secondary background", value: binding(\.secondaryBackgroundHex))
            hexField("Card background", value: binding(\.cardBackgroundHex))
            hexField("Elevated surface", value: binding(\.elevatedSurfaceHex))
            hexField("Primary text", value: binding(\.primaryTextHex))
            hexField("Secondary text", value: binding(\.secondaryTextHex))
        }
    }

    private var previewSection: some View {
        appearanceSection(title: "Preview") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    inAppLogoPreview(for: appearance.selectedLogoChoice, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appearance.resolvedDisplayName)
                            .font(.headline)
                            .foregroundStyle(appearance.resolvedPalette.primaryText)
                        Text("Unread message preview")
                            .font(.caption)
                            .foregroundStyle(appearance.resolvedPalette.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "star.fill")
                        .foregroundStyle(appearance.resolvedPalette.accent)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(appearance.resolvedPalette.mailboxRowBackground(isRead: false))
                )

                HStack(spacing: 8) {
                    Text("P1")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(ActionItemPriorityColors.color(forStoredPriority: 1)))
                    Text("Today 2:00 PM")
                        .font(.caption)
                        .foregroundStyle(appearance.resolvedPalette.accent)
                    Spacer()
                }

                Button("Primary action") {}
                    .buttonStyle(.borderedProminent)
                    .tint(appearance.resolvedPalette.accent)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(appearance.resolvedPalette.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var resetSection: some View {
        Button("Reset to Defaults", role: .destructive) {
            showResetConfirm = true
        }
        .buttonStyle(.bordered)
    }

    private func isPresetSelected(_ preset: AppThemePalette) -> Bool {
        appearance.paletteMode == .preset && appearance.presetPaletteID == preset.id
    }

    private func binding(_ keyPath: WritableKeyPath<AppThemePalette, String>) -> Binding<String> {
        Binding(
            get: {
                if appearance.paletteMode == .custom {
                    return appearance.customPalette[keyPath: keyPath]
                }
                return appearance.resolvedPalette[keyPath: keyPath]
            },
            set: { newValue in
                appearance.updateCustomHex(keyPath, value: newValue)
            }
        )
    }

    @ViewBuilder
    private func appearanceSection<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(SharedAppTheme.primaryText)
            content()
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(SharedAppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hexField(_ label: String, value: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(HexColorUtilities.color(from: value.wrappedValue, fallback: appearance.resolvedPalette.accent))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            Text(label)
                .font(.subheadline)
                .foregroundStyle(SharedAppTheme.primaryText)
                .frame(width: 140, alignment: .leading)
            TextField("#FFFFFF", text: value)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .font(.system(.body, design: .monospaced))
        }
    }

    private func iconChoiceGrid<Label: View>(
        choices: [(id: String, title: String)],
        selectedID: String,
        onSelect: @escaping (String) -> Void,
        @ViewBuilder label: @escaping (String) -> Label
    ) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
            ForEach(choices, id: \.id) { choice in
                Button {
                    onSelect(choice.id)
                } label: {
                    VStack(spacing: 6) {
                        label(choice.id)
                        Text(choice.title)
                            .font(.caption2)
                            .foregroundStyle(SharedAppTheme.primaryText)
                            .lineLimit(1)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selectedID == choice.id ? appearance.resolvedPalette.accent.opacity(0.18) : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                selectedID == choice.id ? appearance.resolvedPalette.accent : Color.white.opacity(0.08),
                                lineWidth: selectedID == choice.id ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func inAppLogoPreview(for choice: AppLogoChoice, size: CGFloat) -> some View {
        LogoView(choice: choice, size: size)
    }

    @ViewBuilder
    private func osIconPreview(for choice: AppOSIconChoice, size: CGFloat) -> some View {
        if let asset = choice.previewAssetName {
            LogoView(assetName: asset, systemImage: "app.fill", size: size)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: size * 0.55))
                .foregroundStyle(appearance.resolvedPalette.accent)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: SharedAppTheme.cornerRadiusSmall, style: .continuous)
                        .fill(appearance.resolvedPalette.secondaryBackground)
                )
        }
    }
}
