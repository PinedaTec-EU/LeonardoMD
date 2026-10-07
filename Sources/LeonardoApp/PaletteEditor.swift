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
            Text("Personalizar paleta").font(.title2.bold())
            HStack {
                VStack(alignment: .leading, spacing: 16) {
                    ColorPicker("Hoja", selection: $surface, supportsOpacity: false)
                    ColorPicker("Texto", selection: $ink, supportsOpacity: false)
                    ColorPicker("Titulares", selection: $heading, supportsOpacity: false)
                    ColorPicker("Acento", selection: $accent, supportsOpacity: false)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("LeonardoMD").font(.title2.bold()).foregroundStyle(heading)
                    Text("Una lectura cómoda, con tu estilo.").foregroundStyle(ink)
                    Text("Enlaces y acciones").foregroundStyle(accent)
                }.padding(24).frame(width: 260, height: 140).background(surface, in: RoundedRectangle(cornerRadius: 12))
            }
            let report = candidate.contrastReport
            Text(String(format: "Contraste · Texto %.1f:1 · Titulares %.1f:1 · Acento %.1f:1", report.textOnSurface, report.headingOnSurface, report.accentOnSurface))
                .font(.caption).foregroundStyle(report.isValid ? Color.secondary : Color.red)
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Restaurar") { load(base.tokens) }
                Button("Importar…") { importPalette() }
                Button("Exportar…") { exportPalette() }
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Aplicar") {
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let custom = try JSONDecoder().decode(PaletteTokenOverrides.self, from: Data(contentsOf: url))
            let palette = PaletteDefinition(id: base.id, displayName: base.displayName, tokens: custom.applying(to: base.tokens))
            guard palette.contrastReport.isValid else { failure = "La paleta importada no tiene contraste suficiente."; return }
            load(palette.tokens)
            failure = nil
        } catch { failure = "No se pudo leer la paleta JSON." }
    }
    private func exportPalette() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "leonardomd-palette.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(overrides).write(to: url, options: [.atomic])
            failure = nil
        } catch { failure = "No se pudo exportar la paleta." }
    }
}

extension Color {
    var hexRGB: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}
