import Darwin
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

struct ImportedGraphicImage: Sendable {
    let data: Data
    let width: Int
    let height: Int
}

/// Decode off the UI actor, bound image dimensions before allocating pixels, and preserve alpha.
enum GraphicImageImport {
    static func prepare(_ url: URL) async throws -> ImportedGraphicImage {
        try await Task.detached(priority: .userInitiated) {
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 32 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: url)
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 16000, height <= 16000,
                  width * height <= 40_000_000,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(width, height)
                  ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination), output.length <= 32 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
            return ImportedGraphicImage(data: output as Data, width: image.width, height: image.height)
        }.value
    }
}

/// Directory-descriptor-relative exclusive writes keep portable assets inside the owning document.
enum GraphicAssetStore {
    private static let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "graphic-assets")
    static func create(_ data: Data, name: String, beside document: URL) throws {
        guard name.range(of: "^image-[A-Fa-f0-9-]+[.]png$", options: .regularExpression) != nil else { throw CocoaError(.fileWriteInvalidFileName) }
        let root = open(document.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard root >= 0 else { throw POSIXError(.EACCES) }
        defer { close(root) }
        if mkdirat(root, "assets", 0o755) != 0 && errno != EEXIST { throw POSIXError(.EACCES) }
        let assets = openat(root, "assets", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard assets >= 0 else { throw POSIXError(.EACCES) }
        defer { close(assets) }
        let descriptor = openat(assets, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EEXIST) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try file.write(contentsOf: data)
            try file.synchronize()
            var opened = stat(), current = stat()
            guard fstat(assets, &opened) == 0, fstatat(root, "assets", &current, AT_SYMLINK_NOFOLLOW) == 0,
                  opened.st_ino == current.st_ino, opened.st_dev == current.st_dev else { throw POSIXError(.ESTALE) }
            logger.info("Stored graphic asset bytes=\(data.count, privacy: .public)")
        } catch {
            _ = unlinkat(assets, name, 0)
            throw error
        }
    }
}
