import AppKit
import SwiftUI
import LeonardoCore
import LeonardoRender

extension AppSession {
    var preview: some View {
        let previewDocumentURL = documentURL
        renderer.onEdit = { [weak self] expected, replacement in
            guard let self, self.documentURL == previewDocumentURL else { return false }
            return self.editDocument(expected: expected, replacement: replacement)
        }
        renderer.onFormEdit = { [weak self] expected, changes in
            guard let self, self.documentURL == previewDocumentURL else { return nil }
            return self.updateLeonardoFields(expected: expected, changes: changes)
        }
        renderer.onFieldHelp = { [weak self] fieldID in
            guard let self, self.documentURL == previewDocumentURL else { return }
            self.showLeonardoFieldHelp(fieldID)
        }
        return MarkdownPreview(
            content: content,
            baseURL: documentURL?.deletingLastPathComponent(),
            configuration: renderConfiguration,
            controller: renderer,
            onLinkActivation: { url in Task { await self.followLink(url) } },
            onScrollProgress: { fraction in
                if self.mode == .split { self.editorScroll = fraction }
            },
            onTagActivation: { self.search(tag: $0) }
        )
        .id(documentURL)
        .onChange(of: editorScroll) { _, fraction in
            if self.mode == .split { self.renderer.scroll(toFraction: fraction) }
        }
    }
    func search(tag: String) {
        guard !stopped, projectURL != nil else { return }
        focus = false
        searchQuery = ProjectSearchQuery.query(forTag: tag)
        scheduleSearch()
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
        let localAssetRoot: URL?
        switch documentStorage {
        case .package, .extracted:
            localAssetRoot = packageWorkspace?.directoryURL
        case .localFile:
            localAssetRoot = projectURL
        }
        var configuration = MarkdownPreviewConfiguration(
            allowsMermaid: features.mermaidEnabled,
            allowsMath: features.mathEnabled,
            frontMatter: showFrontmatter ? .metadata : .hidden,
            externalLinkPolicy: .callbackOnly,
            appearance: MarkdownAppearance(backgroundHex: background, textHex: tokens.text, headingHex: tokens.heading, accentHex: tokens.accent, codeBackgroundHex: tokens.codeBackground, paperEffect: effect),
            localAssetRoot: localAssetRoot
        )
        configuration.allowsLeonardoFormat = documentKind.isLeonardo
        // Form filling is a separate interaction channel. A protected MDLR
        // remains writable through its declared fields while source editing
        // stays locked behind the toolbar padlock.
        configuration.allowsEditing = canEditDocument && mode != .fill
        configuration.allowsFormFilling = canFillLeonardoForm
        configuration.formLabels = TranslationCatalog.catalogs[LanguageSettings.shared.language] ?? [:]
        return configuration
    }
    func followLink(_ url: URL) async {
        guard !stopped else { return }
        if url.isFileURL, let fragment = url.fragment, url.path == documentURL?.path || url.path == documentURL?.deletingLastPathComponent().path {
            renderer.scroll(to: fragment)
            return
        }
        if url.isFileURL, Self.supportedDocumentExtensions.contains(url.pathExtension.lowercased()) {
            await openDocument(url)
        } else if url.isFileURL || confirmExternalLinks {
            // Document-authored local links always require approval before a
            // system handler can run, even when web confirmation is disabled.
            guard pendingExternalURL == nil else { return }
            pendingExternalURL = url
        } else {
            openSystemURL(url)
        }
    }
    func confirmExternalOpening() {
        guard !stopped, let url = pendingExternalURL else { return }
        pendingExternalURL = nil
        openSystemURL(url)
    }
    func cancelExternalOpening() { pendingExternalURL = nil }
    func exportPDF() {
        guard let documentURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = documentURL.deletingPathExtension().lastPathComponent + ".pdf"
        presentFilePanel(panel) { [weak self] destination in self?.exportPDF(to: destination, documentURL: documentURL) }
    }
    private func exportPDF(to destination: URL, documentURL: URL) {
        Task {
            guard await flushPreviewEdits() else { return }
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
