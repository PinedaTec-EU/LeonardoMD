import AppKit
import UniformTypeIdentifiers
import LeonardoCore

extension AppSession {
    func exportMarkdown() {
        Task {
            guard let documentURL, documentKind.isLeonardo, !busy, !isSyncSuspended else { return }
            let alert = Self.markdownExportWarning()
            guard await NativeDialog.present(alert, on: presentationWindow) == .alertFirstButtonReturn, self.documentURL == documentURL,
                  !stopped, !isClosing else { return }
            let panel = NSSavePanel()
            panel.title = L10n.text("Export Markdown…")
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = documentURL.deletingPathExtension().lastPathComponent + ".md"
            presentFilePanel(panel) { [weak self] destination in
                Task { await self?.exportMarkdown(to: destination, documentURL: documentURL) }
            }
        }
    }

    static func markdownExportWarning() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("Export to Markdown loses Leonardo capabilities")
        alert.informativeText = L10n.text("The exported copy loses Leonardo layout and interactive forms. Fields become their current values. Local and unsupported images are removed. Leonardo capabilities cannot be recovered from this Markdown file. The original document is preserved.")
        alert.addButton(withTitle: L10n.text("Export Markdown"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        return alert
    }

    /// The UI obtains loss confirmation and a destination before invoking this adapter.
    func exportMarkdown(to destination: URL, documentURL: URL) async {
        guard documentKind.isLeonardo, let identity = leonardoExportIdentity(for: documentURL),
              !stopped, !busy, !saving, !isClosing, !isSyncSuspended,
              !isCapturingPreview, fileOperationCount == 0 else { return }
        fileOperationCount += 1
        var ownsBusy = false
        defer {
            if ownsBusy { busy = false }
            fileOperationCount -= 1
        }
        guard await flushPreviewEdits(), fileOperationCount == 1,
              !stopped, !busy, !saving, !isClosing, !isSyncSuspended,
              !isCapturingPreview, leonardoExportIdentityIsCurrent(identity),
              let document = leonardoDocument else { return }
        busy = true
        ownsBusy = true
        let draft = content
        let fingerprint = snapshot?.fingerprint
        let output = destination.pathExtension.lowercased() == "md"
            ? destination : destination.appendingPathExtension("md")
        let sources = leonardoExportSources(for: identity)
        do {
            guard !sources.contains(where: {
                $0.resolvingSymlinksInPath().standardizedFileURL == output.resolvingSymlinksInPath().standardizedFileURL
            }) else { throw DocumentStoreError.invalidDestination(output) }
            try await authorizeLeonardoExport(sources: sources, destinationURL: output)
            guard leonardoExportMayWrite(identity: identity, content: draft, snapshotFingerprint: fingerprint) else { return }
            _ = try await documents.save(LeonardoMarkdownExport.markdown(from: document), to: output)
            saveStatus = "Exported · Markdown"
        } catch { report(error) }
    }
}
