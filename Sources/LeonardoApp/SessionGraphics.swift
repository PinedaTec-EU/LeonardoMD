import AppKit
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
                if saveToLibrary { try rubricLibrary.add(label: label, rubric: rubric) }
                return updateLeonardoFields(expected: request.source, changes: [field: value]) != nil
            } catch { report(error); return false }
        }
        guard canEditGraphics else { return false }
        do {
            if saveToLibrary { try rubricLibrary.add(label: label, rubric: rubric) }
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
            let image = try await GraphicImageImport.prepare(source)
            let name = "image-" + UUID().uuidString + ".png"
            let destination = documentURL.deletingLastPathComponent().appendingPathComponent("assets/" + name)
            try await authorizePath(destination, .document)
            guard canEditGraphics, self.documentURL == documentURL, content == expected else { return }
            try GraphicAssetStore.create(image.data, name: name, beside: documentURL)
            _ = insertGraphic(.init(label: source.deletingPathExtension().lastPathComponent.prefix(120).description,
                                    source: "assets/" + name, width: 180, height: min(10000, 180 * Double(image.height) / Double(image.width))))
        } catch { report(error) }
    }
}
