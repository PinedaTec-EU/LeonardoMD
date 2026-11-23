import CoreGraphics
import Foundation

/// Crops the screen's physical page surfaces into vector PDF pages, preserving text and ink.
enum MarkdownPagePDF {
    struct Geometry: Decodable {
        let documentWidth: Double
        let pages: [Page]
    }
    struct Page: Decodable { let x: Double; let y: Double; let width: Double; let height: Double; let overflow: Bool }

    static func paginate(_ data: Data, geometry: Geometry) throws -> Data {
        guard !geometry.pages.isEmpty else { return data }
        if geometry.pages.contains(where: { $0.overflow }) { throw PageOverflowError() }
        guard geometry.pages.count <= 999, geometry.documentWidth.isFinite, geometry.documentWidth > 0,
              let provider = CGDataProvider(data: data as CFData), let input = CGPDFDocument(provider),
              input.numberOfPages == 1, let source = input.page(at: 1) else { throw MarkdownRenderError.invalidPayload }
        let sourceBox = source.getBoxRect(.mediaBox)
        let sourceScale = sourceBox.width / geometry.documentWidth
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw MarkdownRenderError.invalidPayload }
        for page in geometry.pages {
            guard [page.x, page.y, page.width, page.height].allSatisfy({ $0.isFinite }), page.width > 0, page.height > 0 else {
                throw MarkdownRenderError.invalidPayload
            }
            var box = CGRect(x: 0, y: 0, width: page.width * 0.75, height: page.height * 0.75)
            let bounds = CGRect(x: page.x * sourceScale, y: sourceBox.height - (page.y + page.height) * sourceScale,
                                width: page.width * sourceScale, height: page.height * sourceScale)
            context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: &box, length: MemoryLayout<CGRect>.size)] as CFDictionary)
            context.saveGState()
            context.clip(to: box)
            context.scaleBy(x: box.width / bounds.width, y: box.height / bounds.height)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            context.drawPDFPage(source)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }
}

private struct PageOverflowError: LocalizedError {
    var errorDescription: String? { "Content exceeds page height. Split the block before exporting." }
}
