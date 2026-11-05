import Foundation
import LeonardoCore

extension AppSession {
    var selectedGraphic: LeonardoGraphic? {
        guard !stopped, documentURL != nil, !isProtected, !externalConflict,
              mode == .preview || mode == .split, let selectedGraphicID else { return nil }
        return leonardoDocument?.metadata.layout?.objects.first { $0.id == selectedGraphicID }
    }

    func receiveGraphicSelection(expected: String, id: String?, inspect: Bool) {
        guard !stopped, content == expected else { return }
        guard let id else {
            selectedGraphicID = nil; showsGraphicInspector = false
            return
        }
        guard canEditDocument, mode != .fill,
              leonardoDocument?.metadata.layout?.objects.contains(where: { $0.id == id }) == true else { return }
        selectedGraphicID = id
        if inspect { showsGraphicInspector = true }
    }

    func clearGraphicSelection() {
        selectedGraphicID = nil; showsGraphicInspector = false
        renderer.clearObjectSelection()
    }

    @discardableResult
    func updateInspectedGraphic(_ expected: LeonardoGraphic, change: (inout LeonardoGraphic) -> Void) -> Bool {
        guard canEditGraphics, selectedGraphic == expected, var document = leonardoDocument,
              let index = document.metadata.layout?.objects.firstIndex(where: { $0.id == expected.id }) else { return false }
        var changed = expected
        change(&changed)
        guard changed.isValid, changed.id == expected.id, changed.source == expected.source,
              changed.label == expected.label else { return false }
        document.metadata.layout?.objects[index] = changed
        return commitGraphics(document)
    }

    @discardableResult
    func recolorInspectedGraphic(_ expected: LeonardoGraphic, color: String) -> Bool {
        guard expected.rubric != nil else { return false }
        return updateInspectedGraphic(expected) { graphic in
            guard var rubric = graphic.rubric else { return }
            rubric.strokes = rubric.strokes.map { stroke in
                var changed = stroke; changed.color = color; return changed
            }
            graphic.rubric = rubric
        }
    }

    func removeInspectedGraphic(_ expected: LeonardoGraphic) {
        guard selectedGraphic == expected else { return }
        _ = handleGraphicAction(expected: content, object: nil, remove: expected.id, fieldID: nil)
    }
}
