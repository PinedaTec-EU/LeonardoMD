import AppKit
import SwiftUI

enum PreferencesArtwork: String {
    case general, extensions, sync, updates, share, remote

    @MainActor private static let images: [Self: NSImage] = Dictionary(uniqueKeysWithValues:
        [Self.general, .extensions, .sync, .updates, .share, .remote].compactMap { artwork in
            guard let url = Bundle.module.url(forResource: "preferences-\(artwork.rawValue)", withExtension: "png"),
                  let image = NSImage(contentsOf: url) else { return nil }
            return (artwork, image)
        }
    )

    @MainActor var illustration: some View {
        Group {
            if let image = Self.images[self] {
                Image(nsImage: image).resizable().scaledToFit()
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct IllustratedPreferencesHeader: View {
    let title: String
    let artwork: PreferencesArtwork

    var body: some View {
        HStack(spacing: 16) {
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            artwork.illustration.frame(width: 220, height: 90)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}
