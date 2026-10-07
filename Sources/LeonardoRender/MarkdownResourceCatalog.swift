import Foundation
import WebKit

enum MarkdownResource: String, CaseIterable {
    case marked = "marked.umd.js"
    case dompurify = "dompurify.min.js"
    case highlight = "highlight.min.js"
    case mermaid = "mermaid.min.js"
    case katex = "katex.min.js"
    case katexStyles = "katex.min.css"
    case previewStyles = "preview.css"
    case runtime = "renderer-runtime.js"

    var mimeType: String {
        switch self {
        case .katexStyles, .previewStyles:
            return "text/css"
        case .marked, .dompurify, .highlight, .mermaid, .katex, .runtime:
            return "text/javascript"
        }
    }
}

enum MarkdownResourceCatalog {
    static func resources(for configuration: MarkdownPreviewConfiguration) -> [MarkdownResource] {
        var resources: [MarkdownResource] = [
            .marked,
            .dompurify,
            .highlight,
            .previewStyles
        ]
        if configuration.allowsMath {
            resources.append(contentsOf: [.katex, .katexStyles])
        }
        if configuration.allowsMermaid {
            resources.append(.mermaid)
        }
        resources.append(.runtime)
        return resources
    }

    static func url(for resource: MarkdownResource) -> URL? {
        Bundle.module.url(forResource: resource.rawValue, withExtension: nil)
    }

    static func data(for resource: MarkdownResource) -> Data? {
        guard let url = url(for: resource) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func url(forFile path: String) -> URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func fontURL(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "woff2", subdirectory: "fonts")
            ?? Bundle.module.url(forResource: name, withExtension: "woff2")
    }
}

final class MarkdownResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let allowedResources: Set<MarkdownResource>
    private let allowsMath: Bool

    init(configuration: MarkdownPreviewConfiguration) {
        allowedResources = Set(MarkdownResourceCatalog.resources(for: configuration))
        allowsMath = configuration.allowsMath
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(MarkdownResourceError.notFound)
            return
        }

        if let fontName = fontName(for: url), allowsMath,
           let fontURL = MarkdownResourceCatalog.fontURL(named: fontName),
           let data = try? Data(contentsOf: fontURL) {
            let response = URLResponse(
                url: url,
                mimeType: "font/woff2",
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
            return
        }

        guard let resource = resource(for: url),
              allowedResources.contains(resource),
              let data = MarkdownResourceCatalog.data(for: resource) else {
            urlSchemeTask.didFailWithError(MarkdownResourceError.notFound)
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: resource.mimeType,
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func resource(for url: URL?) -> MarkdownResource? {
        guard let url, url.scheme == MarkdownHTMLShell.resourceScheme,
              url.host == "bundle" else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        guard path.count == 1 else { return nil }
        return MarkdownResource(rawValue: path[0])
    }

    private func fontName(for url: URL) -> String? {
        guard url.scheme == MarkdownHTMLShell.resourceScheme,
              url.host == "bundle" else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        guard path.count == 2, path[0] == "fonts", path[1].hasSuffix(".woff2") else {
            return nil
        }
        return String(path[1].dropLast(".woff2".count))
    }
}

enum MarkdownResourceError: Error {
    case notFound
}
