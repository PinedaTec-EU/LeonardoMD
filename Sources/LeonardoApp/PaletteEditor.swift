import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LeonardoCore

struct PaletteEditor: View {
    let session: AppSession
    let projectScope: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var surface = Color.white
    @State private var ink = Color.black
    @State private var heading = Color.blue
    @State private var accent = Color.blue
    @State private var failure: String?

    private var overrides: PaletteTokenOverrides {
        PaletteTokenOverrides(surface: surface.hexRGB, text: ink.hexRGB, heading: heading.hexRGB, accent: accent.hexRGB)
    }
    private var base: PaletteDefinition {
        PaletteCatalog.definition(for: projectScope ? session.projectConfiguration.palette ?? session.globalPreferences.palette : session.globalPreferences.palette)
    }
    private var candidate: PaletteDefinition {
        PaletteDefinition(id: base.id, displayName: base.displayName, tokens: overrides.applying(to: base.tokens))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("Customize palette")).font(.title2.bold())
            HStack {
                VStack(alignment: .leading, spacing: 16) {
                    ColorPicker(L10n.text("Paper"), selection: $surface, supportsOpacity: false)
                    ColorPicker(L10n.text("Text"), selection: $ink, supportsOpacity: false)
                    ColorPicker(L10n.text("Headings"), selection: $heading, supportsOpacity: false)
                    ColorPicker(L10n.text("Accent"), selection: $accent, supportsOpacity: false)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("LeonardoMD").font(.title2.bold()).foregroundStyle(heading)
                    Text(L10n.text("Comfortable reading, in your style.")).foregroundStyle(ink)
                    Text(L10n.text("Links and actions")).foregroundStyle(accent)
                }.padding(24).frame(width: 260, height: 140).background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
            let report = candidate.contrastReport
            Text(String(format: L10n.text("Contrast · Text %.1f:1 · Headings %.1f:1 · Accent %.1f:1"), report.textOnSurface, report.headingOnSurface, report.accentOnSurface))
                .font(.caption).foregroundStyle(report.isValid ? Color.secondary : Color.red)
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(L10n.text("Reset")) { load(base.tokens) }
                Button(L10n.text("Import…")) { importPalette() }
                Button(L10n.text("Export…")) { exportPalette() }
                Spacer()
                Button(L10n.text("Cancel")) { dismiss() }
                Button(L10n.text("Apply")) {
                    if projectScope { session.projectConfiguration.customTokens = overrides }
                    else { session.globalPreferences.customTokens = overrides }
                    session.persistSettings()
                    dismiss()
                }.buttonStyle(PremiumButtonStyle(prominent: true)).disabled(!report.isValid)
            }.buttonStyle(PremiumButtonStyle(compact: true))
        }.padding(24).frame(width: 620)
            .onAppear {
                let custom = projectScope ? session.projectConfiguration.customTokens : session.globalPreferences.customTokens
                load(custom?.applying(to: base.tokens) ?? base.tokens)
            }
    }
    private func load(_ tokens: PaletteTokens) {
        surface = Color(hex: tokens.surface)
        ink = Color(hex: tokens.text)
        heading = Color(hex: tokens.heading)
        accent = Color(hex: tokens.accent)
    }
    private func importPalette() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        presentFilePanel(panel) { url in readPalette(url) }
    }
    private func readPalette(_ url: URL) {
        do {
            let custom = try JSONDecoder().decode(PaletteTokenOverrides.self, from: Data(contentsOf: url))
            let palette = PaletteDefinition(id: base.id, displayName: base.displayName, tokens: custom.applying(to: base.tokens))
            guard palette.contrastReport.isValid else { failure = L10n.text("The imported palette has insufficient contrast."); return }
            load(palette.tokens)
            failure = nil
        } catch { failure = L10n.text("Could not read the palette JSON.") }
    }
    private func exportPalette() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "leonardomd-palette.json"
        presentFilePanel(panel) { url in writePalette(url) }
    }
    private func writePalette(_ url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(overrides).write(to: url, options: [.atomic])
            failure = nil
        } catch { failure = L10n.text("Could not export the palette.") }
    }
}

extension Color {
    var hexRGB: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}
