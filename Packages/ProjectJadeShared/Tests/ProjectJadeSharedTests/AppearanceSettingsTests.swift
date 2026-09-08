import XCTest
@testable import ProjectJadeShared

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

    func testPaletteSelectionHighlightUsesAccent() {
        let palette = AppThemePalette.presetForest
        XCTAssertEqual(palette.selectionHighlight, palette.accent.opacity(0.22))
    }

    func testSelectPresetPreviewsWithoutPersistingUntilApply() {
        let store = AppearanceSettingsStore.shared
        let snapshot = PaletteTestSnapshot(store: store)

        defer { snapshot.restore(into: store) }

        store.applyPaletteChanges()
        store.selectPreset(.presetOcean)

        XCTAssertTrue(store.hasUnsavedPaletteChanges)
        XCTAssertEqual(store.presetPaletteID, AppThemePalette.presetOcean.id)
        XCTAssertEqual(store.resolvedPalette.accentHex, AppThemePalette.presetOcean.accentHex)

        store.applyPaletteChanges()
        XCTAssertFalse(store.hasUnsavedPaletteChanges)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "appearance.presetPaletteID"),
            AppThemePalette.presetOcean.id
        )
    }

    func testRevertPaletteChangesRestoresSavedSelection() {
        let store = AppearanceSettingsStore.shared
        let snapshot = PaletteTestSnapshot(store: store)

        defer { snapshot.restore(into: store) }

        store.applyPaletteChanges()
        store.selectPreset(.presetForest)
        store.revertPaletteChanges()

        XCTAssertFalse(store.hasUnsavedPaletteChanges)
        XCTAssertEqual(store.presetPaletteID, snapshot.presetPaletteID)
        XCTAssertEqual(store.paletteMode, snapshot.paletteMode)
    }

    func testEditingHexWhileOnPresetSeedsCustomFromCurrentPreset() {
        let store = AppearanceSettingsStore.shared
        let snapshot = PaletteTestSnapshot(store: store)

        defer { snapshot.restore(into: store) }

        store.applyPaletteChanges()
        store.selectPreset(.presetOcean)
        store.updateCustomHex(\.accentHex, value: "#112233")

        XCTAssertEqual(store.paletteMode, .custom)
        XCTAssertEqual(store.customPalette.id, AppThemePalette.customPaletteID)
        XCTAssertEqual(store.customPalette.name, "Custom")
        XCTAssertEqual(store.customPalette.accentHex, "#112233")
        XCTAssertEqual(store.customPalette.secondaryBackgroundHex, AppThemePalette.presetOcean.secondaryBackgroundHex)
        XCTAssertTrue(store.hasUnsavedPaletteChanges)
    }
}

@MainActor
private struct PaletteTestSnapshot {
    let paletteMode: AppearancePaletteMode
    let presetPaletteID: String
    let customPalette: AppThemePalette

    init(store: AppearanceSettingsStore) {
        paletteMode = store.paletteMode
        presetPaletteID = store.presetPaletteID
        customPalette = store.customPalette
    }

    func restore(into store: AppearanceSettingsStore) {
        store.paletteMode = paletteMode
        store.presetPaletteID = presetPaletteID
        store.customPalette = customPalette
        store.applyPaletteChanges()
    }
}
