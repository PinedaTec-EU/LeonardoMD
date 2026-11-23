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
    let subtitle: String
    let artwork: PreferencesArtwork

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            artwork.illustration.frame(width: 148, height: 60)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}
