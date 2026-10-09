import Foundation

enum MarkdownHTMLShell {
    static let resourceScheme = "leonardo-resource"
    static let documentScheme = "leonardo-document"

    static func make(
        content: String,
        baseURL: URL?,
        configuration: MarkdownPreviewConfiguration
    ) throws -> String {
        let encodedPayload = try payloadJSON(
            content: content,
            baseURL: baseURL,
            configuration: configuration
        )
        let resourceURL = { (resource: MarkdownResource) in
            "\(resourceScheme)://bundle/\(resource.rawValue)"
        }
        let mathStylesheet = configuration.allowsMath
            ? "<link rel=\"stylesheet\" href=\"\(resourceURL(.katexStyles))\">"
            : ""
        let mermaidScript = configuration.allowsMermaid
            ? "<script src=\"\(resourceURL(.mermaid))\"></script>"
            : ""
        let mathScript = configuration.allowsMath
            ? "<script src=\"\(resourceURL(.katex))\"></script>"
            : ""
        let documentBase = documentBaseHref(baseURL: baseURL, configuration: configuration)
            .map { "<base href=\"\($0)\">" } ?? ""

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(documentScheme): data:\(configuration.allowsRemoteImages ? " http: https:" : ""); style-src 'unsafe-inline' \(resourceScheme):; script-src 'unsafe-inline' \(resourceScheme):; font-src \(resourceScheme): data:; connect-src 'none';">
          \(documentBase)
          <link rel="stylesheet" href="\(resourceURL(.previewStyles))">
          \(mathStylesheet)
          <script src="\(resourceURL(.marked))"></script>
          <script src="\(resourceURL(.dompurify))"></script>
          <script src="\(resourceURL(.highlight))"></script>
          \(mermaidScript)
          \(mathScript)
        </head>
        <body>
          <main id="leonardo-markdown" class="markdown-body" aria-live="polite"></main>
          <script id="leonardo-payload" type="application/json">\(encodedPayload)</script>
          <script src="\(resourceURL(.runtime))"></script>
        </body>
        </html>
        """
    }

    static func payloadJSON(
        content: String,
        baseURL: URL?,
        configuration: MarkdownPreviewConfiguration
    ) throws -> String {
        let document = MarkdownDocumentParser.parse(content)
        let payload = MarkdownRenderPayload(
            markdown: document.body,
            frontMatter: document.frontMatter,
            tags: document.tags,
            showFrontMatter: configuration.frontMatter == .metadata,
            allowsMermaid: configuration.allowsMermaid,
            allowsMath: configuration.allowsMath,
            debounceMilliseconds: configuration.renderDebounce.milliseconds,
            appearance: configuration.appearance.sanitizedPayload,
            baseURL: baseURL?.absoluteString
        )
        return try payload.encodedForHTML()
    }

    static func documentBaseHref(
        baseURL: URL?,
        configuration: MarkdownPreviewConfiguration
    ) -> String? {
        guard let baseURL, baseURL.isFileURL else { return nil }
        let directory = baseURL.standardizedFileURL
        let assetRoot = (configuration.localAssetRoot ?? directory.deletingLastPathComponent())
            .standardizedFileURL
        let virtualPath = MarkdownDocumentSchemeHandler.virtualBasePath(
            baseDirectory: directory,
            assetRoot: assetRoot
        ) ?? ""
        let encodedComponents = virtualPath
            .split(separator: "/")
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                    ?? String(component)
            }
            .joined(separator: "/")
        return "\(documentScheme)://local/\(encodedComponents.isEmpty ? "" : encodedComponents + "/")"
    }
}

private struct MarkdownRenderPayload: Encodable {
    let markdown: String
    let frontMatter: [String: String]
    let tags: [String]
    let showFrontMatter: Bool
    let allowsMermaid: Bool
    let allowsMath: Bool
    let debounceMilliseconds: Int
    let appearance: MarkdownAppearancePayload
    let baseURL: String?

    func encodedForHTML() throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        guard var value = String(data: data, encoding: .utf8) else {
            throw MarkdownRenderError.invalidPayload
        }
        value = value.replacingOccurrences(of: "<", with: "\\u003c")
        value = value.replacingOccurrences(of: ">", with: "\\u003e")
        value = value.replacingOccurrences(of: "&", with: "\\u0026")
        return value
    }
}

enum MarkdownRenderError: Error {
    case invalidPayload
    case webViewUnavailable
    case renderTimedOut
    case pdfAssetFailure(String)
}

private extension Duration {
    var milliseconds: Int {
        let components = self.components
        let secondsResult = components.seconds.multipliedReportingOverflow(by: 1_000)
        if secondsResult.overflow {
            return components.seconds >= 0 ? Int.max : 0
        }
        let seconds = secondsResult.partialValue
        let attoseconds = components.attoseconds / 1_000_000_000_000_000
        let (total, overflow) = seconds.addingReportingOverflow(attoseconds)
        if overflow { return Int.max }
        return Int(clamping: max(0, total))
    }
}
