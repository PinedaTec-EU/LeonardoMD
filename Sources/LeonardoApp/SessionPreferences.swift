import AppKit
import SwiftUI
import LeonardoCore

extension AppSession {
    func setMermaid(_ value: Bool, project: Bool? = nil) {
        var updated = (project ?? (projectURL != nil)) ? features : globalPreferences.markdown
        updated.mermaidEnabled = value
        setFeatures(updated, project: project)
    }
    func setMath(_ value: Bool, project: Bool? = nil) {
        var updated = (project ?? (projectURL != nil)) ? features : globalPreferences.markdown
        updated.mathEnabled = value
        setFeatures(updated, project: project)
    }
    func setFeatures(_ features: MarkdownFeatures, project: Bool? = nil) {
        if !(project ?? (projectURL != nil)) || projectURL == nil { globalPreferences.markdown = features }
        else {
            // A single toggle changes one inherited flag, rather than replacing
            // another window's newly created override with a stale full value.
            if projectConfiguration.markdown == nil { projectBaseline.markdown = self.features }
            projectConfiguration.markdown = features
        }
        persistSettings()
    }
    func inheritFeatures(_ inherit: Bool) {
        projectConfiguration.markdown = inherit ? nil : features
        persistSettings()
    }
    func setPalette(_ raw: String, project: Bool) {
        if project { projectConfiguration.palette = PaletteID(rawValue: raw) }
        else if let palette = PaletteID(rawValue: raw) { globalPreferences.palette = palette }
        persistSettings()
    }
    func setPaper(_ raw: String, project: Bool) {
        if project { projectConfiguration.paperEffect = PaperEffect(rawValue: raw) }
        else if let paper = PaperEffect(rawValue: raw) { globalPreferences.paperEffect = paper }
        persistSettings()
    }
    func setGitEnabled(_ enabled: Bool) {
        projectConfiguration.git.enabled = enabled
        persistSettings()
        Task { await refreshGit() }
    }
    func persistSettings() {
        let global = globalPreferences
        let project = projectConfiguration
        let root = projectURL
        let oldGlobal = globalBaseline
        let oldProject = projectBaseline
        globalBaseline = global
        projectBaseline = project
        settingsRevision += 1
        let revision = settingsRevision
        let previous = settingsTask
        settingsTask = Task {
            await previous?.value
            defer { if settingsRevision == revision { settingsTask = nil } }
            do {
                let merged = try await configurations.mergeGlobalPreferences(updated: global, baseline: oldGlobal, at: globalPreferencesURL)
                if globalPreferences == global { globalPreferences = merged; globalBaseline = merged }
                if let root {
                    let mergedProject = try await configurations.mergeProjectConfiguration(updated: project, baseline: oldProject, for: root)
                    if projectURL == root, projectConfiguration == project { projectConfiguration = mergedProject; projectBaseline = mergedProject }
                }
            } catch { report(error) }
        }
    }
    func saveCopy() {
        guard let url = documentURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + L10n.text("Copy filename suffix")
        presentFilePanel(panel) { [weak self] destination in self?.saveCopy(to: destination, sourceURL: url) }
    }
    func saveCopy(to destination: URL, sourceURL url: URL) {
        Task { await saveCopyAndOpen(to: destination, sourceURL: url) }
    }

    func saveCopyAndOpen(to destination: URL, sourceURL url: URL) async {
        guard documentURL == url, !stopped, !busy, !isClosing else { return }
        guard destination.standardizedFileURL.resolvingSymlinksInPath() != url.standardizedFileURL.resolvingSymlinksInPath() else {
            errorMessage = L10n.text("Choose another file to keep both versions.")
            return
        }
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        guard await flushPreviewEdits(), documentURL == url, !stopped, !busy, !isClosing else { return }
        // No suspension between the final preview snapshot and the input lock.
        busy = true
        fileOperationCount += 1
        defer { busy = false; fileOperationCount -= 1 }
        let draft = content
        do {
            try await authorizePath(url, .document)
            try await authorizePath(destination, .document)
            guard !stopped, documentURL == url, content == draft else { return }
            let copy = try await documents.save(draft, to: destination)
            guard !stopped, documentURL == url, content == draft else {
                errorMessage = L10n.text("The copy was saved. Later changes remain in the original document.")
                return
            }
            // save returns a verified, readable snapshot. Commit it synchronously;
            // failures above retain every part of the original conflict session.
            projectURL = nil
            projectConfiguration = .default
            projectBaseline = .default
            rootEntries = []
            resetSearch()
            focus = false
            documentURL = destination
            snapshot = copy
            content = copy.content
            externalConflict = false
            isProtected = true
            editorScroll = 0
            requestedLine = nil
            mode = DocumentMode(rawValue: resolved.defaultMode.rawValue) ?? .preview
            saveStatus = "Saved · local file"
            NSDocumentController.shared.noteNewRecentDocumentURL(destination)
            updateTitle()
        } catch { report(error) }
    }
    func jumpToHeading(_ line: Int) {
        requestedLine = line
        let total = max(1, content.components(separatedBy: "\n").count - 1)
        editorScroll = min(1, Double(line - 1) / Double(total))
        renderer.scroll(toFraction: editorScroll)
    }
}
