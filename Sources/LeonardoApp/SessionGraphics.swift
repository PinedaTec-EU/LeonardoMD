import AppKit
import CryptoKit
import Foundation
import LeonardoCore
import UniformTypeIdentifiers

extension AppSession {
    var canEditGraphics: Bool { canEditDocument && !saving && !externalConflict && mode != .fill }

    func requestRubric(fieldID: String? = nil) {
        if let fieldID {
            guard canFillLeonardoForm, let field = leonardoFieldDefinition(fieldID), field.type == .rubric, !field.readOnly else { return }
        } else if !canEditGraphics { return }
        rubricRequest = RubricRequest(documentURL: documentURL, source: content, fieldID: fieldID)
    }

    func finishRubric(_ request: RubricRequest, label: String, rubric: LeonardoRubric, saveToLibrary: Bool) -> Bool {
        guard documentURL == request.documentURL, content == request.source, rubric.isValid else { return false }
        if let field = request.fieldID {
            guard canFillLeonardoForm, let value = rubric.jsonValue,
                  let definition = leonardoFieldDefinition(field), !definition.readOnly, definition.type == .rubric else { return false }
            do {
                if saveToLibrary { try RubricLibrary.shared.add(label: label, rubric: rubric) }
                return updateLeonardoFields(expected: request.source, changes: [field: value]) != nil
            } catch { report(error); return false }
        }
        guard canEditGraphics else { return false }
        do {
            if saveToLibrary { try RubricLibrary.shared.add(label: label, rubric: rubric) }
            return insertGraphic(.init(label: label, rubric: rubric))
        } catch { report(error); return false }
    }

    @discardableResult
    func insertGraphic(_ graphic: LeonardoGraphic) -> Bool {
        guard canEditGraphics, var document = leonardoDocument else { return false }
        if document.metadata.layout == nil { document.metadata.layout = .init() }
        if document.metadata.layout?.page == nil { document.metadata.layout?.page = .init() }
        document.metadata.layout?.objects.append(graphic)
        return commitGraphics(document)
    }

    func handleGraphicAction(expected: String, object: LeonardoGraphic?, remove: String?, fieldID: String?) -> Bool {
        guard content == expected else { return false }
        if let fieldID { requestRubric(fieldID: fieldID); return rubricRequest != nil }
        guard canEditGraphics, var document = leonardoDocument,
              var layout = document.metadata.layout else { return false }
        if let object, object.isValid, let index = layout.objects.firstIndex(where: { $0.id == object.id }) {
            // Geometry bridge cannot change resources, identity or stored ink.
            var changed = layout.objects[index]
            changed.page = object.page; changed.x = object.x; changed.y = object.y
            changed.width = object.width; changed.height = object.height; changed.z = object.z
            layout.objects[index] = changed
        } else if let remove, let index = layout.objects.firstIndex(where: { $0.id == remove }) {
            layout.objects.remove(at: index)
        } else { return false }
        document.metadata.layout = layout
        return commitGraphics(document)
    }

    private func commitGraphics(_ document: LeonardoDocument) -> Bool {
        do { return editDocument(expected: content, replacement: try LeonardoFormatParser.serialize(document)) }
        catch { report(error); return false }
    }

    func insertPageBreak() {
        guard canEditGraphics, var document = leonardoDocument else { return }
        document.body += "\n\n<!-- leonardo:page-break -->\n\n"
        _ = commitGraphics(document)
    }

    func chooseGraphicImage() {
        guard canEditGraphics else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .bmp]
        panel.allowsMultipleSelection = false
        presentFilePanel(panel) { [weak self] url in Task { await self?.importGraphicImage(url) } }
    }

    func importGraphicImage(_ source: URL) async {
        guard canEditGraphics, let documentURL else { return }
        let expected = content
        do {
            guard let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: source)
            guard let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
                  bitmap.pixelsWide <= 16000, bitmap.pixelsHigh <= 16000,
                  let png = bitmap.representation(using: .png, properties: [:]), png.count <= 32 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            let hash = SHA256.hash(data: png).prefix(12).map { String(format: "%02x", $0) }.joined()
            let name = "leonardo-image-" + hash + ".png"
            let destination = documentURL.deletingLastPathComponent().appendingPathComponent(name)
            try await authorizePath(destination, .document)
            guard canEditGraphics, self.documentURL == documentURL, content == expected else { return }
            if FileManager.default.fileExists(atPath: destination.path) {
                guard try Data(contentsOf: destination) == png else { throw CocoaError(.fileWriteFileExists) }
            } else { try png.write(to: destination, options: .withoutOverwriting) }
            _ = insertGraphic(.init(label: source.deletingPathExtension().lastPathComponent.prefix(120).description,
                                    source: name, width: 180, height: 180 * Double(bitmap.pixelsHigh) / Double(bitmap.pixelsWide)))
        } catch { report(error) }
    }
}
