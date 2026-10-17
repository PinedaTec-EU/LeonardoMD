import SwiftUI
import AppKit

/// Notebook sketches frame the welcome controls without taking part in interaction.
struct WelcomeWatermark: View {
    // The lettering asset is 3:1. Reserve its actual height outside scrolling content.
    static func letteringSize(in size: CGSize) -> CGSize {
        let width = max(0, min(640, size.width * 0.72, size.height * 0.54))
        return CGSize(width: width, height: width / 3)
    }

    private let draftingOchre = Color(hex: "#A87832")

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let lettering = Self.letteringSize(in: geometry.size)
            sketch("WelcomeWatermark", opacity: 0.40)
                .frame(width: lettering.width, height: lettering.height)
                .position(x: width * 0.40, y: lettering.height / 2 + 12)
            if height >= 500 {
                sketch("WelcomeWings", opacity: 0.30)
                    .frame(width: min(637.5, width * 0.50, height * 0.65))
                    .rotationEffect(.degrees(-8))
                    .position(x: width * 0.31, y: height * 0.85)
            }
            if width >= 1100 && height >= 740 {
                let figureSize = min(510, width * 0.32, height * 0.65)
                sketch("WelcomeVitruvian", opacity: 0.32)
                    .frame(width: figureSize)
                    .position(x: width - figureSize / 2 - 18, y: height * 0.48)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func sketch(_ name: String, opacity: Double) -> some View {
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(draftingOchre)
                .opacity(opacity)
        }
    }
}
