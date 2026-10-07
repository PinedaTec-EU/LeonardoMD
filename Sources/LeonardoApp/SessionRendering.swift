import AppKit
import SwiftUI
import LeonardoCore
import LeonardoRender

extension AppSession {
    var preview: some View {
        MarkdownPreview(
            content: content,
            baseURL: documentURL?.deletingLastPathComponent(),
            configuration: renderConfiguration,
            controller: renderer,
            onLinkActivation: { url in self.followLink(url) },
            onScrollProgress: { fraction in
                if self.mode == .split { self.editorScroll = fraction }
            }
        )
        .onChange(of: editorScroll) { _, fraction in
            if self.mode == .split { self.renderer.scroll(toFraction: fraction) }
        }
    }
    var renderConfiguration: MarkdownPreviewConfiguration {
        let tokens = resolved.paperEffect == .white && darkPalette ? PaletteCatalog.paperWhite.tokens : palette.tokens
        let effect: LeonardoRender.PaperEffect
        switch resolved.paperEffect {
        case .white, .solid: effect = .plain
        case .ruled: effect = .ruled
        case .grid: effect = .grid
        case .microgrid: effect = .microgrid
        case .parchment: effect = .parchment
        }
        let background = resolved.paperEffect == .white ? "#F8F8F5" : tokens.surface
        return MarkdownPreviewConfiguration(
            allowsMermaid: features.mermaidEnabled,
            allowsMath: features.mathEnabled,
            frontMatter: showFrontmatter ? .metadata : .hidden,
            externalLinkPolicy: .callbackOnly,
            appearance: MarkdownAppearance(backgroundHex: background, textHex: tokens.text, headingHex: tokens.heading, accentHex: tokens.accent, codeBackgroundHex: tokens.codeBackground, paperEffect: effect),
            localAssetRoot: projectURL
        )
    }
    func followLink(_ url: URL) {
        if let fragment = url.fragment, url.path == documentURL?.path || url.path == documentURL?.deletingLastPathComponent().path {
            renderer.scroll(to: fragment)
            return
        }
        if url.isFileURL {
            Task { await openDocument(url) }
        } else {
            if confirmExternalLinks {
                let alert = NSAlert()
                alert.messageText = "¿Abrir enlace externo?"
                alert.informativeText = url.absoluteString
                alert.addButton(withTitle: "Abrir en navegador")
                alert.addButton(withTitle: "Cancelar")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            NSWorkspace.shared.open(url)
        }
    }
    func exportPDF() {
        guard let documentURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = documentURL.deletingPathExtension().lastPathComponent + ".pdf"
        presentFilePanel(panel) { [weak self] destination in self?.exportPDF(to: destination, documentURL: documentURL) }
    }
    private func exportPDF(to destination: URL, documentURL: URL) {
        Task {
            let previousMode = mode
            defer { mode = previousMode }
            do {
                if mode == .edit {
                    mode = .split
                    // Allow SwiftUI to attach the preview before requesting export.
                    for _ in 0..<100 {
                        if renderer.isReady { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                }
                renderer.update(content: content, baseURL: documentURL.deletingLastPathComponent(), configuration: renderConfiguration)
                let data = try await renderer.exportPDF()
                try data.write(to: destination, options: [.atomic])
            } catch { report(error) }
        }
    }
}
