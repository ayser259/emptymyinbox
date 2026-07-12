//
//  LogoView.swift
//  ProjectJadeShared
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct LogoView: View {
    private let assetNameOverride: String?
    private let systemImageOverride: String?
    public let size: CGFloat

    public init(size: CGFloat = 40) {
        self.assetNameOverride = nil
        self.systemImageOverride = nil
        self.size = size
    }

    public init(assetName: String?, systemImage: String, size: CGFloat = 40) {
        self.assetNameOverride = assetName
        self.systemImageOverride = systemImage
        self.size = size
    }

    public var body: some View {
        Group {
            if let image = loadAssetImage(named: resolvedAssetName) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: size * 0.2237,
                            style: .continuous
                        )
                    )
            } else {
                fallbackIcon
            }
        }
    }

    private var resolvedAssetName: String? {
        assetNameOverride ?? AppearanceSettingsStore.shared.resolvedLogoAssetName
    }

    private var resolvedSystemImage: String {
        systemImageOverride ?? "envelope.fill"
    }

    private func loadAssetImage(named name: String?) -> Image? {
        guard let name else { return nil }
        #if os(iOS)
        if let uiImage = UIImage(named: name) {
            return Image(uiImage: uiImage)
        }
        #elseif os(macOS)
        if let img = NSImage(named: name) {
            return Image(nsImage: AppIconService.processedThemeIconImage(img))
        }
        #endif
        return nil
    }

    private var fallbackIcon: some View {
        Image(systemName: resolvedSystemImage)
            .font(.system(size: size * 0.6))
            .foregroundColor(SharedAppTheme.accent)
            .frame(width: size, height: size)
    }
}

/// Branded logo that always reflects the user's selected theme preset.
public struct BrandedLogoView: View {
    public let size: CGFloat
    @ObservedObject private var appearance = AppearanceSettingsStore.shared

    public init(size: CGFloat = 40) {
        self.size = size
    }

    public var body: some View {
        LogoView(assetName: appearance.resolvedLogoAssetName, systemImage: "envelope.fill", size: size)
    }
}
