import Foundation
import LeonardoCore

public enum RemoteDocumentResources {
    public static func path(url: URL, virtualRoot: URL) -> String? {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost", url.query == nil else { return nil }
        let root = virtualRoot.standardizedFileURL.pathComponents
        let target = url.standardizedFileURL.pathComponents
        guard target.count > root.count, Array(target.prefix(root.count)) == root else { return nil }
        return target.dropFirst(root.count).joined(separator: "/")
    }

    public static func imagePaths(in source: String, documentPath: String, catalogue: RemoteProjectCatalogue) -> [String] {
        let root = URL(fileURLWithPath: "/LeonardoRemote", isDirectory: true)
        let base = root.appendingPathComponent(documentPath).deletingLastPathComponent()
        let available = Set(catalogue.files.map(\.path))
        return Set(LeonardoLocalImagePolicy.localReferences(in: source).compactMap { reference in
            guard let url = URL(string: reference, relativeTo: base)?.absoluteURL,
                  let path = path(url: url, virtualRoot: root), available.contains(path) else { return nil }
            return path
        }).sorted()
    }
}
