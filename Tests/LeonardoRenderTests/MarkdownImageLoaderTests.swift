import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import LeonardoRender

struct MarkdownImageLoaderTests {
    private let target = MarkdownImagePolicy.Target(longestSide: 100, pixels: 10_000)

    @Test func rejectsOversizedDiskAndMemoryInputsBeforeDecode() async throws {
        var policy = MarkdownImagePolicy.standard
        policy.maximumInputBytes = 100
        let loader = MarkdownImageLoader(policy: policy)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: 1_000_000_000)
        try file.close()
        await #expect(throws: MarkdownImageError.inputTooLarge) { try await loader.load(.file(url), target: target) }
        await #expect(throws: MarkdownImageError.inputTooLarge) {
            try await loader.load(.memory(Data(count: 101), extensionName: "png"), target: target)
        }
    }

    @Test func downsamplesDiskAndMemoryToTargetWithoutChangingOriginal() async throws {
        let bytes = try fixture(width: 1_200, height: 600)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try bytes.write(to: url)
        let loader = MarkdownImageLoader()
        for input in [MarkdownImageLoader.Input.file(url), .memory(bytes, extensionName: "png")] {
            let result = try await loader.load(input, target: target)
            let dimensions = try size(result.data)
            #expect(dimensions.0 == 100)
            #expect(dimensions.1 == 50)
            #expect(result.mimeType == "image/png")
        }
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func pixelBudgetAlsoBoundsSquareThumbnailAndPDFHasSeparateResolution() async throws {
        let bytes = try fixture(width: 1_200, height: 1_200)
        let loader = MarkdownImageLoader()
        let preview = try await loader.load(.memory(bytes, extensionName: "png"),
            target: .init(longestSide: 1_000, pixels: 10_000))
        #expect(try size(preview.data).0 == 100)
        let pdf = try await loader.load(.memory(bytes, extensionName: "png"),
            target: .pdf(width: 200, height: 200, policy: .standard))
        #expect(try size(pdf.data).0 == 625)
        let bounded = MarkdownImagePolicy.Target.preview(width: .infinity, height: 1, scale: 2, policy: .standard)
        #expect(bounded.longestSide == 4_096)
    }

    @Test func rejectsExcessiveSourcePixelsAndInvalidRaster() async throws {
        var policy = MarkdownImagePolicy.standard
        policy.maximumSourcePixels = 100
        let loader = MarkdownImageLoader(policy: policy)
        let bytes = try fixture(width: 20, height: 20)
        await #expect(throws: MarkdownImageError.pixelLimit) {
            try await loader.load(.memory(bytes, extensionName: "png"), target: target)
        }
        await #expect(throws: MarkdownImageError.invalidImage) {
            try await loader.load(.memory(Data("invalid".utf8), extensionName: "png"), target: target)
        }
    }

    @Test func preservesAnimationBytesAndRejectsExcessiveFramesOrDecodedCost() async throws {
        let bytes = try fixture(width: 20, height: 20, frames: 3)
        let result = try await MarkdownImageLoader().load(.memory(bytes, extensionName: "gif"), target: target)
        #expect(result.data == bytes)
        #expect(result.mimeType == "image/gif")
        var policy = MarkdownImagePolicy.standard
        policy.maximumAnimationPixels = 1_000
        await #expect(throws: MarkdownImageError.pixelLimit) {
            try await MarkdownImageLoader(policy: policy).load(.memory(bytes, extensionName: "gif"), target: target)
        }
        policy.maximumFrames = 2
        await #expect(throws: MarkdownImageError.pixelLimit) {
            try await MarkdownImageLoader(policy: policy).load(.memory(bytes, extensionName: "gif"), target: target)
        }
    }

    @Test func svgStaysVectorAndHasSeparateInputAndEstimatedRenderBudgets() async throws {
        let bytes = Data("<svg xmlns='http://www.w3.org/2000/svg' width='12' height='12'/>".utf8)
        let result = try await MarkdownImageLoader().load(.memory(bytes, extensionName: "svg"), target: target)
        #expect(result.data == bytes)
        #expect(result.mimeType == "image/svg+xml")
        #expect(result.estimatedBytes > bytes.count)
        var policy = MarkdownImagePolicy.standard
        policy.maximumSVGBytes = bytes.count - 1
        await #expect(throws: MarkdownImageError.inputTooLarge) {
            try await MarkdownImageLoader(policy: policy).load(.memory(bytes, extensionName: "svg"), target: target)
        }
    }

    @Test func repeatedLoadsCannotBypassLifetimeBudget() async throws {
        let bytes = try fixture(width: 20, height: 20)
        let input = MarkdownImageLoader.Input.memory(bytes, extensionName: "png")
        let resource = try await MarkdownImageLoader().load(input, target: target)
        var policy = MarkdownImagePolicy.standard
        policy.maximumDocumentBytes = resource.estimatedBytes * 2
        let loader = MarkdownImageLoader(policy: policy)
        _ = try await loader.load(input, target: target)
        _ = try await loader.load(input, target: target)
        await #expect(throws: MarkdownImageError.documentLimit) { try await loader.load(input, target: target) }
    }

    @Test func cancelledWorkDoesNotConsumeAdmissionBudget() async throws {
        let input = MarkdownImageLoader.Input.memory(try fixture(width: 20, height: 20), extensionName: "png")
        var policy = MarkdownImagePolicy.standard
        policy.maximumRequests = 1
        let loader = MarkdownImageLoader(policy: policy)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await loader.load(input, target: target)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        _ = try await loader.load(input, target: target)
        await #expect(throws: MarkdownImageError.documentLimit) { try await loader.load(input, target: target) }
    }

    private func size(_ bytes: Data) throws -> (Int, Int) {
        let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (try #require(properties[kCGImagePropertyPixelWidth] as? Int),
                try #require(properties[kCGImagePropertyPixelHeight] as? Int))
    }

    private func fixture(width: Int, height: Int, frames: Int = 1) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let type = frames > 1 ? UTType.gif : UTType.png
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, frames, nil))
        for _ in 0..<frames { CGImageDestinationAddImage(destination, image, nil) }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
