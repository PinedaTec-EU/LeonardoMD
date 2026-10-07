import XCTest
@testable import LeonardoCore

final class CoreTypesTests: XCTestCase {
    func testPaletteCatalogMeetsWCAGMinimums() {
        XCTAssertEqual(PaletteCatalog.contrastRatio("#000000", "#FFFFFF"), 21, accuracy: 0.001)
        for palette in PaletteCatalog.all {
            let report = palette.contrastReport
            XCTAssertTrue(report.passesNormalText, "Text contrast failed for \(palette.id)")
            XCTAssertTrue(report.passesHeading, "Heading contrast failed for \(palette.id)")
            XCTAssertTrue(report.passesAccent, "Accent contrast failed for \(palette.id)")
            XCTAssertGreaterThanOrEqual(report.accentOnSurface, 4.5, "Accent must meet normal-text contrast for \(palette.id)")
            XCTAssertTrue(report.isValid, "Palette was not valid: \(palette.id)")
        }
    }

    func testCustomTokenOverridesLayerOnInheritedPalette() throws {
        let global = GlobalPreferences(
            palette: .paperWhite,
            customTokens: PaletteTokenOverrides(accent: "#AA0000")
        )
        let project = ProjectConfiguration(customTokens: PaletteTokenOverrides(heading: "#550000"))
        let resolved = project.resolved(using: global)

        XCTAssertEqual(resolved.palette, .paperWhite)
        XCTAssertEqual(resolved.paletteTokens.accent, "#AA0000")
        XCTAssertEqual(resolved.paletteTokens.heading, "#550000")
        XCTAssertEqual(resolved.paletteTokens.text, PaletteCatalog.paperWhite.tokens.text)

        let data = try JSONEncoder().encode(project)
        let roundTrip = try JSONDecoder().decode(ProjectConfiguration.self, from: data)
        XCTAssertEqual(roundTrip.customTokens?.heading, "#550000")
    }

    func testProjectSettingsInheritGlobalValues() {
        let global = GlobalPreferences(
            palette: .leonardoClassic,
            paperEffect: .parchment,
            markdown: MarkdownFeatures(mermaidEnabled: true, mathEnabled: true, defaultMode: .split),
            showHiddenFiles: true
        )
        let project = ProjectConfiguration()
        let resolved = project.resolved(using: global)

        XCTAssertEqual(resolved.palette, .leonardoClassic)
        XCTAssertEqual(resolved.paperEffect, .parchment)
        XCTAssertTrue(resolved.markdown.mermaidEnabled)
        XCTAssertTrue(resolved.markdown.mathEnabled)
        XCTAssertEqual(resolved.defaultMode, .split)
        XCTAssertTrue(resolved.showHiddenFiles)
    }

    func testProjectSettingsOverrideOnlySelectedGlobalValues() {
        let global = GlobalPreferences(
            palette: .paperWhite,
            paperEffect: .grid,
            markdown: MarkdownFeatures(mermaidEnabled: true, mathEnabled: false, defaultMode: .preview)
        )
        let project = ProjectConfiguration(palette: .graphiteGlass, markdown: MarkdownFeatures(mathEnabled: true))
        let resolved = project.resolved(using: global)

        XCTAssertEqual(resolved.palette, .graphiteGlass)
        XCTAssertEqual(resolved.paperEffect, .grid)
        XCTAssertFalse(resolved.markdown.mermaidEnabled)
        XCTAssertTrue(resolved.markdown.mathEnabled)
    }
}
