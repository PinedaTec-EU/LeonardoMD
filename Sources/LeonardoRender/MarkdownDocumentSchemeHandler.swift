import Foundation
import LeonardoCore
import WebKit
import os.log

@MainActor
final class MarkdownDocumentSchemeHandler: NSObject, WKURLSchemeHandler {
    private var documentID = 0
    private let imageLoader: MarkdownImageLoader
    private let policy: MarkdownImagePolicy
    private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "images")
    private let baseDirectory: URL?
    private let assetRoot: URL?
    private let memoryAssets: MarkdownMemoryAssets?

    init(baseURL: URL?, assetRootURL: URL? = nil, memoryAssets: MarkdownMemoryAssets? = nil,
         policy: MarkdownImagePolicy = .standard) {
        self.policy = policy
        imageLoader = MarkdownImageLoader(policy: policy)
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
        guard url.absoluteString.utf8.count <= policy.maximumURLBytes else {
            urlSchemeTask.didFailWithError(MarkdownImageError.inputTooLarge)
            return
        }
        guard let input = imageInput(for: url) else {
            urlSchemeTask.didFailWithError(MarkdownDocumentError.notFound)
            return
        }
        let target = imageTarget(url: url, webView: webView)
        let loader = imageLoader
        let generation = documentID
        let started = DispatchTime.now().uptimeNanoseconds
        requests[id] = Task { [weak self] in
            do {
                let resource = try await loader.load(input, target: target, documentID: generation, identity: url.absoluteString)
                guard !Task.isCancelled, let self, self.requests.removeValue(forKey: id) != nil else { return }
                let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                self.logger.debug("image_load_completed encoded_bytes=\(resource.data.count, privacy: .public) estimated_bytes=\(resource.estimatedBytes, privacy: .public) duration_ms=\(milliseconds, privacy: .public)")
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

    func beginDocument() {
        // WebKit may reuse an in-flight image during an incremental DOM update.
        // Only its stop callback (or teardown) retires the corresponding task.
        documentID += 1
    }

    func cancelAll() {
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
    }

    /// Export the original bytes, never the viewport-sized preview raster.
    func originalImageData(for url: URL) async throws -> Data {
        guard url.absoluteString.utf8.count <= policy.maximumURLBytes,
              let input = imageInput(for: url) else { throw MarkdownDocumentError.notFound }
        return try await imageLoader.originalData(input)
    }

    func imageWindowData(for url: URL) async throws -> Data {
        guard url.absoluteString.utf8.count <= policy.maximumURLBytes,
              let input = imageInput(for: url) else { throw MarkdownDocumentError.notFound }
        let target = MarkdownImagePolicy.Target.preview(width: 800, height: 600, scale: 2, policy: policy)
        return try await imageLoader.load(input, target: target, documentID: documentID,
                                          identity: url.absoluteString).data
    }

    private func imageInput(for url: URL) -> MarkdownImageLoader.Input? {
        if let memoryAssets, let data = memoryAssets.data(for: url) {
            return .memory(data, extensionName: url.pathExtension.lowercased())
        }
        if memoryAssets == nil, let fileURL = fileURL(for: url), isImage(fileURL) {
            return .file(fileURL)
        }
        return nil
    }

    private func imageTarget(url: URL, webView: WKWebView) -> MarkdownImagePolicy.Target {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if query.contains(where: { $0.name == "leonardo-image-purpose" && $0.value == "pdf" }) {
            let width = query.first(where: { $0.name == "leonardo-image-width" })?.value.flatMap(Double.init) ?? 0
            let height = query.first(where: { $0.name == "leonardo-image-height" })?.value.flatMap(Double.init) ?? 0
            return .pdf(width: width, height: height, policy: policy)
        }
        #if os(macOS)
        let scale = webView.window?.backingScaleFactor ?? 2
        #else
        let scale = webView.window?.screen.scale ?? 2
        #endif
        return .preview(width: webView.bounds.width, height: webView.bounds.height,
                        scale: scale * webView.pageZoom, policy: policy)
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
