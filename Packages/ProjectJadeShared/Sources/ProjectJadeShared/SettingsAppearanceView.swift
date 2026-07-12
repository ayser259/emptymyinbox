import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Appearance preferences: app name, theme presets, and custom colors (shared iOS + macOS).
public struct SettingsAppearanceView: View {
    @ObservedObject private var appearance = AppearanceSettingsStore.shared
    @State private var showResetConfirm = false
    @State private var showThemeAppliedConfirmation = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                brandingSection
                paletteSection
                palettePreviewBar
                themeAppliedConfirmationBar
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
            Text("Restores the default app name and gold color theme.")
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

    private var paletteSection: some View {
        appearanceSection(
            title: "Theme Presets",
            footer: "Pick a preset or customize hex colors below. The app icon and logo change with your theme. Changes preview live until you apply them."
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                ForEach(AppThemePalette.presets) { preset in
                    presetChip(
                        name: preset.name,
                        accentHex: preset.accentHex,
                        backgroundHex: preset.primaryBackgroundHex,
                        iconAssetName: AppIconRegistry.themeIcon(forPaletteID: preset.id).logoAssetName,
                        isSelected: isPresetSelected(preset)
                    ) {
                        appearance.selectPreset(preset)
                    }
                }

                presetChip(
                    name: "Custom",
                    accentHex: appearance.customPalette.accentHex,
                    backgroundHex: appearance.customPalette.primaryBackgroundHex,
                    iconAssetName: AppIconRegistry.themeIcon(forPaletteID: AppThemePalette.customPaletteID).logoAssetName,
                    isSelected: isCustomSelected
                ) {
                    appearance.selectCustom()
                }
            }
        }
    }

    @ViewBuilder
    private var palettePreviewBar: some View {
        if appearance.hasUnsavedPaletteChanges {
            HStack(spacing: 12) {
                Text("Previewing — not saved yet")
                    .font(.subheadline)
                    .foregroundStyle(SharedAppTheme.secondaryText)
                Spacer(minLength: 0)
                Button("Cancel") {
                    appearance.revertPaletteChanges()
                }
                .buttonStyle(.bordered)
                Button("Apply") {
                    appearance.applyPaletteChanges()
                    showThemeAppliedConfirmation = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        await MainActor.run {
                            showThemeAppliedConfirmation = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.resolvedPalette.accent)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(appearance.resolvedPalette.accent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(appearance.resolvedPalette.accent.opacity(0.35), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var themeAppliedConfirmationBar: some View {
        if showThemeAppliedConfirmation {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(appearance.resolvedPalette.accent)
                Text("Theme applied")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SharedAppTheme.primaryText)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(appearance.resolvedPalette.accent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(appearance.resolvedPalette.accent.opacity(0.35), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func presetChip(
        name: String,
        accentHex: String,
        backgroundHex: String,
        iconAssetName: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                LogoView(assetName: iconAssetName, systemImage: "app.fill", size: 36)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(HexColorUtilities.color(from: accentHex))
                    .frame(height: 24)
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(HexColorUtilities.color(from: backgroundHex))
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .offset(x: -6, y: 4)
                    }
                Text(name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SharedAppTheme.primaryText)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? appearance.resolvedPalette.accent.opacity(0.18) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? appearance.resolvedPalette.accent : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
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
                    BrandedLogoView(size: 40)
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

    private var isCustomSelected: Bool {
        appearance.paletteMode == .custom
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
}
