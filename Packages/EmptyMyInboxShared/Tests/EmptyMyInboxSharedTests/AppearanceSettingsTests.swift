import XCTest
@testable import EmptyMyInboxShared

@MainActor
final class AppearanceSettingsTests: XCTestCase {
    func testHexNormalizationAcceptsSixDigitWithHash() {
        XCTAssertEqual(HexColorUtilities.normalizedHex("#F6AC0A"), "#F6AC0A")
    }

    func testHexNormalizationAcceptsThreeDigit() {
        XCTAssertEqual(HexColorUtilities.normalizedHex("000"), "#000000")
    }

    func testHexNormalizationRejectsInvalid() {
        XCTAssertNil(HexColorUtilities.normalizedHex("not-a-color"))
        XCTAssertNil(HexColorUtilities.normalizedHex("#GGGGGG"))
    }

    func testPaletteSanitizationFallsBackForInvalidHex() {
        var palette = AppThemePalette.defaultDarkGold
        palette.accentHex = "invalid"
        let sanitized = palette.sanitized()
        XCTAssertEqual(sanitized.accentHex, AppThemePalette.defaultDarkGold.accentHex)
    }

    func testPresetLookup() {
        XCTAssertEqual(AppThemePalette.preset(withID: "preset-ocean")?.name, "Ocean")
    }

    func testVaultDisplayNameUsesCustomAppName() {
        let name = AppBranding.vaultDisplayName(using: "My Mail")
        XCTAssertEqual(name, "My Mail Vault")
    }

    func testVaultDisplayNameDefault() {
        XCTAssertEqual(AppBranding.vaultDisplayName(using: nil), AppBranding.defaultVaultDisplayName)
        XCTAssertEqual(AppBranding.vaultDisplayName(using: ""), AppBranding.defaultVaultDisplayName)
    }

    func testPaletteSelectionHighlightUsesAccent() {
        let palette = AppThemePalette.presetForest
        XCTAssertEqual(palette.selectionHighlight, palette.accent.opacity(0.22))
    }
}
