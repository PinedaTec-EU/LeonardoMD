import Foundation
import LeonardoCore
import Darwin
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

/// One actor per web view serializes reads/decodes. No original or thumbnail cache is retained.
actor MarkdownImageLoader {
    enum Input: Sendable {
        case file(URL)
        case memory(Data, extensionName: String)
    }

    struct Resource: Sendable {
        let data: Data
        let mimeType: String
        let estimatedBytes: Int
    }

    private static let allowedSourceTypes = Set(LeonardoLocalImagePolicy.extensions
        .filter { $0 != "svg" }
        .compactMap { UTType(filenameExtension: $0)?.identifier })
    private let policy: MarkdownImagePolicy
    private var admittedBytes = 0
    private var admissions: Set<String> = []
    private var documentID = 0

    init(policy: MarkdownImagePolicy = .standard) { self.policy = policy }

    func load(_ input: Input, target: MarkdownImagePolicy.Target, documentID: Int = 0,
              identity: String = "") throws -> Resource {
        try Task.checkCancellation()
        // An older pending request can still serve the new DOM. Charge it to
        // the current budget without moving that budget back to its generation.
        if documentID > self.documentID {
            self.documentID = documentID
            admittedBytes = 0
            admissions.removeAll()
        }
        let (data, extensionName) = try read(input)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let key = "\(identity)|\(extensionName)|\(target.longestSide)|\(target.pixels)|\(digest)"
        let isRepeat = admissions.contains(key)
        guard isRepeat || (admissions.count < policy.maximumRequests && admittedBytes < policy.maximumDocumentBytes) else {
            throw MarkdownImageError.documentLimit
        }
        let resource = try autoreleasepool {
            try Task.checkCancellation()
            if extensionName == "svg" {
                // Keep vector rendering and intrinsic dimensions; do not flatten SVG into a bitmap.
                guard data.count <= policy.maximumSVGBytes else { throw MarkdownImageError.inputTooLarge }
                return Resource(data: data, mimeType: "image/svg+xml", estimatedBytes: data.count + MarkdownSVGImage.estimatedPixels(data, target: target) * MarkdownImagePolicy.bytesPerPixel)
            }
            return try raster(data, target: target)
        }
        try Task.checkCancellation()
        guard isRepeat || resource.estimatedBytes <= policy.maximumDocumentBytes - admittedBytes else {
            throw MarkdownImageError.documentLimit
        }
        if !isRepeat {
            admittedBytes += resource.estimatedBytes
            admissions.insert(key)
        }
        return resource
    }

    private func read(_ input: Input) throws -> (Data, String) {
        switch input {
        case .memory(let data, let extensionName):
            guard data.count <= inputLimit(extensionName) else { throw MarkdownImageError.inputTooLarge }
            return (data, extensionName)
        case .file(let url):
            let limit = inputLimit(url.pathExtension.lowercased())
            let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { throw MarkdownImageError.invalidImage }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else {
                throw MarkdownImageError.invalidImage
            }
            // Check this open descriptor, then bound every read too (the file may grow).
            guard try handle.seekToEnd() <= UInt64(limit) else { throw MarkdownImageError.inputTooLarge }
            try handle.seek(toOffset: 0)
            var data = Data()
            let chunkBytes = 64 * 1_024
            while true {
                try Task.checkCancellation()
                let chunk = try handle.read(upToCount: min(chunkBytes, limit - data.count + 1)) ?? Data()
                if chunk.isEmpty { break }
                guard chunk.count <= limit - data.count else { throw MarkdownImageError.inputTooLarge }
                data.append(chunk)
            }
            return (data, url.pathExtension.lowercased())
        }
    }

    private func inputLimit(_ extensionName: String) -> Int {
        extensionName == "svg" ? min(policy.maximumInputBytes, policy.maximumSVGBytes) : policy.maximumInputBytes
    }

    private func raster(_ data: Data, target: MarkdownImagePolicy.Target) throws -> Resource {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            throw MarkdownImageError.invalidImage
        }
        guard let type = CGImageSourceGetType(source), Self.allowedSourceTypes.contains(type as String),
              CGImageSourceGetCount(source) > 0 else { throw MarkdownImageError.invalidImage }
        let count = CGImageSourceGetCount(source)
        guard count <= policy.maximumFrames else { throw MarkdownImageError.pixelLimit }
        let size = try dimensions(source, index: 0)
        guard size.pixels <= policy.maximumSourcePixels else { throw MarkdownImageError.pixelLimit }
        if count > 1 {
            return try animation(source, data: data, count: count)
        }
        let side = min(Double(max(size.width, size.height)), Double(target.longestSide),
                       Double(max(size.width, size.height)) * sqrt(Double(target.pixels) / Double(size.pixels)))
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(side.rounded(.down)))
        ] as CFDictionary
        try Task.checkCancellation()
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions),
              image.width * image.height <= target.pixels else { throw MarkdownImageError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw MarkdownImageError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= policy.maximumInputBytes else {
            throw MarkdownImageError.inputTooLarge
        }
        return Resource(data: output as Data, mimeType: "image/png",
                        estimatedBytes: output.length + image.width * image.height * MarkdownImagePolicy.bytesPerPixel)
    }

    private func animation(_ source: CGImageSource, data: Data, count: Int) throws -> Resource {
        var pixels = 0
        var canvasWidth = 0
        var canvasHeight = 0
        for index in 0..<count {
            try Task.checkCancellation()
            let frame = try dimensions(source, index: index)
            guard frame.pixels <= policy.maximumAnimationPixels - pixels else { throw MarkdownImageError.pixelLimit }
            pixels += frame.pixels
            canvasWidth = max(canvasWidth, frame.width)
            canvasHeight = max(canvasHeight, frame.height)
        }
        // Budget the entire logical canvas per frame, including GIF delta frames.
        if let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] {
            canvasWidth = max(canvasWidth, properties[kCGImagePropertyPixelWidth] as? Int ?? 0)
            canvasHeight = max(canvasHeight, properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
        }
        guard canvasWidth > 0, canvasHeight > 0,
              canvasWidth <= policy.maximumAnimationPixels / count,
              canvasHeight <= policy.maximumAnimationPixels / count / canvasWidth else {
            throw MarkdownImageError.pixelLimit
        }
        let canvasPixels = canvasWidth * canvasHeight
        let type = CGImageSourceGetType(source) as String?
        let mime = type.flatMap { UTType($0)?.preferredMIMEType } ?? "application/octet-stream"
        return Resource(data: data, mimeType: mime,
                        estimatedBytes: data.count + max(pixels, canvasPixels * count) * MarkdownImagePolicy.bytesPerPixel)
    }

    private func dimensions(_ source: CGImageSource, index: Int) throws -> (width: Int, height: Int, pixels: Int) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= policy.maximumSourcePixels,
              height <= policy.maximumSourcePixels / width else { throw MarkdownImageError.pixelLimit }
        return (width, height, width * height)
    }
}
