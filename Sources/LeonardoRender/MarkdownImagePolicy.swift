import Foundation

/// Admission limits, not a claim about WebKit's total process memory.
struct MarkdownImagePolicy: Sendable {
    static let standard = Self()
    var maximumInputBytes = 32 * 1_024 * 1_024
    var maximumSVGBytes = 2 * 1_024 * 1_024
    var maximumSourcePixels = 40_000_000
    var maximumAnimationPixels = 4_000_000
    var maximumFrames = 128
    var maximumPreviewPixels = 4_000_000
    var maximumPDFPixels = 16_000_000
    var maximumDocumentBytes = 128 * 1_024 * 1_024
    var maximumRequests = 256
    static let bytesPerPixel = 8 // Conservative allowance for 16-bit RGBA.
    static let maximumPendingRequests = 32
    static let pdfScale = 300.0 / 96.0

    struct Target: Sendable {
        let longestSide: Int
        let pixels: Int

        static func preview(width: Double, height: Double, scale: Double, policy: MarkdownImagePolicy) -> Self {
            let side = max(width, height) * scale
            return Self(longestSide: boundedSide(side, maximum: 4_096), pixels: policy.maximumPreviewPixels)
        }

        static func pdf(width: Double, height: Double, policy: MarkdownImagePolicy) -> Self {
            Self(longestSide: boundedSide(max(width, height) * pdfScale, maximum: 8_192),
                 pixels: policy.maximumPDFPixels)
        }

        private static func boundedSide(_ value: Double, maximum: Int) -> Int {
            guard value.isFinite, value > 0 else { return maximum }
            return Int(min(Double(maximum), max(1, value.rounded(.up))))
        }
    }
}

enum MarkdownImageError: Error, Equatable {
    case inputTooLarge, invalidImage, pixelLimit, documentLimit, queueLimit
}
