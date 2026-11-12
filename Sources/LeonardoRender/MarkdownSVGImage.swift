import Foundation

/// Reads only root sizing metadata. SVG remains vector content rendered by WebKit;
/// this estimates its surface, not the cost of arbitrary filters or paths.
private final class SVGRootSize: NSObject, XMLParserDelegate {
    var attributes: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "svg" { attributes = attributeDict }
        parser.abortParsing()
    }
}

enum MarkdownSVGImage {
    static func estimatedPixels(_ data: Data, target: MarkdownImagePolicy.Target) -> Int {
        let parser = XMLParser(data: data)
        let root = SVGRootSize()
        parser.delegate = root
        parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        let width = dimension(root.attributes["width"]) ?? Double(target.longestSide)
        let height = dimension(root.attributes["height"]) ?? Double(target.longestSide)
        let scale = min(1, Double(target.longestSide) / max(width, height))
        let pixels = width * scale * height * scale
        guard pixels.isFinite, pixels > 0 else { return target.pixels }
        return Int(min(Double(target.pixels), pixels.rounded(.up)))
    }

    private static func dimension(_ text: String?) -> Double? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let units = [("px", 1.0), ("pt", 96.0 / 72.0), ("pc", 16.0),
                     ("cm", 96.0 / 2.54), ("mm", 96.0 / 25.4), ("in", 96.0)]
        let unit = units.first { value.hasSuffix($0.0) }
        let number = unit.map { String(value.dropLast($0.0.count)) } ?? value
        guard let parsed = Double(number), parsed.isFinite, parsed > 0 else { return nil }
        return parsed * (unit?.1 ?? 1)
    }
}
