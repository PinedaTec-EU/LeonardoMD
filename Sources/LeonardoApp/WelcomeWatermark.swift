import SwiftUI
import AppKit

/// Decorative identity for roomy document-free windows, using the active palette's ink.
struct WelcomeWatermark: View {
    let ink: Color
    private let minimumHeight: CGFloat = 740
    private let maximumWidth: CGFloat = 760

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.height >= minimumHeight {
                VStack {
                    Spacer()
                    Image(nsImage: NSImage(contentsOf: Bundle.module.url(forResource: "WelcomeWatermark", withExtension: "png")!)!)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(ink)
                        .opacity(0.12)
                        .frame(width: min(maximumWidth, geometry.size.width * 0.75))
                        .padding(.bottom, 28)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
