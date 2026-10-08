import SwiftUI
import AppKit

/// Notebook sketches frame the welcome controls without taking part in interaction.
struct WelcomeWatermark: View {
    private let minimumHeight: CGFloat = 740
    private let draftingOchre = Color(hex: "#A87832")

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.height >= minimumHeight {
                let width = geometry.size.width
                let height = geometry.size.height
                let figureSize = min(510, width * 0.32, height * 0.65)
                if width >= 1100 {
                    sketch("WelcomeVitruvian", opacity: 0.32)
                    .frame(width: figureSize)
                    .position(x: width - figureSize / 2 - 18, y: height * 0.48)
                }
                sketch("WelcomeWings", opacity: 0.30)
                    .frame(width: min(637.5, width * 0.50))
                    .rotationEffect(.degrees(-8))
                    .position(x: width * 0.27, y: height * 0.19)
                sketch("WelcomeWatermark", opacity: 0.40)
                    .frame(width: min(640, width * 0.52))
                    .position(x: width * 0.31, y: height * 0.85)
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
