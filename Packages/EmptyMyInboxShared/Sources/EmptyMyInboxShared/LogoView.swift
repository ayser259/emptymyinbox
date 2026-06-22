//
//  LogoView.swift
//  EmptyMyInboxShared
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct LogoView: View {
    private let choice: AppLogoChoice?
    private let assetNameOverride: String?
    private let systemImageOverride: String?
    public let size: CGFloat

    public init(size: CGFloat = 40) {
        self.choice = nil
        self.assetNameOverride = nil
        self.systemImageOverride = nil
        self.size = size
    }

    public init(choice: AppLogoChoice, size: CGFloat = 40) {
        self.choice = choice
        self.assetNameOverride = nil
        self.systemImageOverride = nil
        self.size = size
    }

    public init(assetName: String?, systemImage: String, size: CGFloat = 40) {
        self.choice = nil
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
                    .cornerRadius(SharedAppTheme.cornerRadiusSmall)
            } else {
                fallbackIcon
            }
        }
    }

    private var activeChoice: AppLogoChoice {
        choice ?? AppearanceSettingsStore.shared.selectedLogoChoice
    }

    private var resolvedAssetName: String? {
        assetNameOverride ?? activeChoice.assetName
    }

    private var resolvedSystemImage: String {
        systemImageOverride ?? activeChoice.systemImage
    }

    private func loadAssetImage(named name: String?) -> Image? {
        guard let name else { return nil }
        #if os(iOS)
        if let uiImage = UIImage(named: name) {
            return Image(uiImage: uiImage)
        }
        #elseif os(macOS)
        if let img = NSImage(named: name) {
            return Image(nsImage: img)
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

/// Branded logo that always reflects the user's selected in-app logo.
public struct BrandedLogoView: View {
    public let size: CGFloat
    @ObservedObject private var appearance = AppearanceSettingsStore.shared

    public init(size: CGFloat = 40) {
        self.size = size
    }

    public var body: some View {
        LogoView(choice: appearance.selectedLogoChoice, size: size)
    }
}
