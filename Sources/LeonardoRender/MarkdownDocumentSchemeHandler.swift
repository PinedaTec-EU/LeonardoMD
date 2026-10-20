import Foundation
import LeonardoCore
import WebKit
import os.log

@MainActor
final class MarkdownDocumentSchemeHandler: NSObject, WKURLSchemeHandler {
    private let imageLoader = MarkdownImageLoader()
    private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "images")
    private let baseDirectory: URL?
    private let assetRoot: URL?
    private let memoryAssets: MarkdownMemoryAssets?

    init(baseURL: URL?, assetRootURL: URL? = nil, memoryAssets: MarkdownMemoryAssets? = nil) {
        self.memoryAssets = memoryAssets
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
        let id = ObjectIdentifier(urlSchemeTask)
        guard requests.count < MarkdownImagePolicy.maximumPendingRequests else {
            urlSchemeTask.didFailWithError(MarkdownImageError.queueLimit)
            return
        }
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(MarkdownDocumentError.notFound)
            return
        }
        let input: MarkdownImageLoader.Input
        if let memoryAssets, let data = memoryAssets.data(for: url) {
            input = .memory(data, extensionName: url.pathExtension.lowercased())
        } else if memoryAssets == nil, let fileURL = fileURL(for: url), isImage(fileURL) {
            input = .file(fileURL)
        } else {
            urlSchemeTask.didFailWithError(MarkdownDocumentError.notFound)
            return
        }
        let target = imageTarget(url: url, webView: webView)
        let loader = imageLoader
        requests[id] = Task { [weak self] in
            do {
                let resource = try await loader.load(input, target: target)
                guard !Task.isCancelled, let self, self.requests.removeValue(forKey: id) != nil else { return }
                urlSchemeTask.didReceive(URLResponse(url: url, mimeType: resource.mimeType,
                    expectedContentLength: resource.data.count, textEncodingName: nil))
                urlSchemeTask.didReceive(resource.data)
                urlSchemeTask.didFinish()
            } catch {
                guard !Task.isCancelled, let self, self.requests.removeValue(forKey: id) != nil else { return }
                let category = error is MarkdownImageError ? String(describing: error) : "read_failed"
                self.logger.notice("image_load_rejected category=\(category, privacy: .public)")
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        requests.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }

    func cancelAll() {
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
    }

    private func imageTarget(url: URL, webView: WKWebView) -> MarkdownImagePolicy.Target {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if query.contains(where: { $0.name == "leonardo-image-purpose" && $0.value == "pdf" }) {
            let width = query.first(where: { $0.name == "leonardo-image-width" })?.value.flatMap(Double.init) ?? 0
            let height = query.first(where: { $0.name == "leonardo-image-height" })?.value.flatMap(Double.init) ?? 0
            return .pdf(width: width, height: height, policy: .standard)
        }
        #if os(macOS)
        let scale = webView.window?.backingScaleFactor ?? 2
        #else
        let scale = webView.window?.screen.scale ?? 2
        #endif
        return .preview(width: webView.bounds.width, height: webView.bounds.height,
                        scale: scale * webView.pageZoom, policy: .standard)
    }

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
        guard LeonardoLocalImagePolicy.extensions
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
        guard LeonardoLocalImagePolicy.extensions
            .contains(candidate.pathExtension.lowercased()) else { return nil }
        return candidate
    }

    private func isImage(_ url: URL) -> Bool {
        LeonardoLocalImagePolicy.extensions
            .contains(url.pathExtension.lowercased())
    }

}

enum MarkdownDocumentError: Error {
    case notFound
}
