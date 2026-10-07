import Foundation
import WebKit

final class MarkdownDocumentSchemeHandler: NSObject, WKURLSchemeHandler {
    private let baseDirectory: URL?
    private let assetRoot: URL?

    init(baseURL: URL?, assetRootURL: URL? = nil) {
        if let baseURL, baseURL.isFileURL {
            let directory = baseURL.standardizedFileURL
            baseDirectory = directory
            assetRoot = (assetRootURL ?? directory.deletingLastPathComponent()).standardizedFileURL
        } else {
            baseDirectory = nil
            assetRoot = nil
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let fileURL = fileURL(for: url),
              isImage(fileURL),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(MarkdownDocumentError.notFound)
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: mimeType(for: fileURL),
            expectedContentLength: data.count,
            textEncodingName: isText(fileURL) ? "utf-8" : nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func fileURL(for url: URL) -> URL? {
        guard url.scheme == MarkdownHTMLShell.documentScheme,
              url.host == "local",
              let baseDirectory else { return nil }

        if let assetRoot,
           let virtualPath = Self.virtualPath(for: url),
           let candidate = Self.fileURL(relativeVirtualPath: virtualPath, assetRoot: assetRoot) {
            return candidate
        }

        return Self.resolvedFileURL(
            baseDirectory: baseDirectory,
            assetRoot: assetRoot,
            requestURL: url
        )
    }

    nonisolated static func resolvedFileURL(baseDirectory: URL, assetRoot: URL?, requestURL: URL) -> URL? {
        guard requestURL.scheme == MarkdownHTMLShell.documentScheme,
              requestURL.host == "local" else { return nil }

        let relativePath = requestURL.path.removingPercentEncoding ?? requestURL.path
        let candidate = baseDirectory
            .appendingPathComponent(relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let root = baseDirectory.resolvingSymlinksInPath().path
        let assetRoot = assetRoot?.resolvingSymlinksInPath().path ?? root
        let candidatePath = candidate.path
        let isInDocumentDirectory = candidatePath == root || candidatePath.hasPrefix(root + "/")
        let isInAssetRoot = candidatePath == assetRoot || candidatePath.hasPrefix(assetRoot + "/")
        guard isInDocumentDirectory || isInAssetRoot else { return nil }
        guard ["bmp", "gif", "ico", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]
            .contains(candidate.pathExtension.lowercased()) else { return nil }
        return candidate
    }

    nonisolated static func virtualBasePath(baseDirectory: URL, assetRoot: URL) -> String? {
        let directory = baseDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let root = assetRoot.resolvingSymlinksInPath().standardizedFileURL.path
        guard directory == root || directory.hasPrefix(root + "/") else { return nil }
        return String(directory.dropFirst(root.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func virtualPath(for url: URL) -> String? {
        guard url.scheme == MarkdownHTMLShell.documentScheme,
              url.host == "local" else { return nil }
        return (url.path.removingPercentEncoding ?? url.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func fileURL(relativeVirtualPath path: String, assetRoot: URL) -> URL? {
        let candidate = assetRoot
            .appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let root = assetRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = candidate.path
        guard candidatePath == root || candidatePath.hasPrefix(root + "/") else { return nil }
        guard ["bmp", "gif", "ico", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]
            .contains(candidate.pathExtension.lowercased()) else { return nil }
        return candidate
    }

    private func isImage(_ url: URL) -> Bool {
        ["bmp", "gif", "ico", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]
            .contains(url.pathExtension.lowercased())
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "css": return "text/css"
        case "csv": return "text/csv"
        case "gif": return "image/gif"
        case "html", "htm": return "text/html"
        case "jpeg", "jpg": return "image/jpeg"
        case "js": return "text/javascript"
        case "json": return "application/json"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "mp4": return "video/mp4"
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        case "txt", "md": return "text/plain"
        case "wav": return "audio/wav"
        case "webm": return "video/webm"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }

    private func isText(_ url: URL) -> Bool {
        ["css", "csv", "html", "htm", "js", "json", "md", "svg", "txt"].contains(url.pathExtension.lowercased())
    }
}

enum MarkdownDocumentError: Error {
    case notFound
}
