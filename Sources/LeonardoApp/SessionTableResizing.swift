import Foundation
import LeonardoCore

extension AppSession {
    /// One native mutation boundary for both ordinary Markdown migration and
    /// existing MDLF/package documents. The renderer owns only transient pixels.
    func resizePreviewTable(expected: String, resize: LeonardoTableResize) async -> Bool {
        let canApplyCloseSnapshot = isClosing && isClosePreviewSyncPending && canEditDocumentIgnoringClose
        guard canEditDocument || canApplyCloseSnapshot,
              !saving, !externalConflict,
              mode == .preview || mode == .split, content == expected else { return false }
        if documentKind == .markdown {
            return await migrateMarkdownToLeonardo(allowClosing: canApplyCloseSnapshot, tableResize: resize)
        }
        guard documentKind.isLeonardo else { return false }
        do {
            let original = try LeonardoFormatParser.parse(expected)
            let resized = try resize.applying(to: original)
            let replacement = try LeonardoFormatParser.serialize(resized)
            return editPreviewDocument(expected: expected, replacement: replacement)
        } catch {
            report(error)
            return false
        }
    }
}
