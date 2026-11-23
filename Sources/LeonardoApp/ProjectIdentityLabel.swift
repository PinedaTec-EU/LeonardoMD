import SwiftUI
import AppKit
import LeonardoCore

/// Native adapter; symbols and role vocabulary are shared with Little Leonardo.
struct ProjectIdentityIcon: View {
    let identity: ProjectIdentity

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: ProjectIdentity.projectSymbolName)
            if let indicator = identity.indicatorSymbolName {
                Image(systemName: indicator).font(.caption)
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    @MainActor
    static func menuImage(for identity: ProjectIdentity) -> NSImage {
        let names = [ProjectIdentity.projectSymbolName, identity.indicatorSymbolName].compactMap { $0 }
        let image = NSImage(size: NSSize(width: names.count == 1 ? 18 : 36, height: 18),
                            flipped: false) { _ in
            for (index, name) in names.enumerated() {
                NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .draw(in: NSRect(x: index * 18, y: 1, width: 16, height: 16))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct ProjectIdentityLabel: View {
    let name: String
    let identity: ProjectIdentity
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ProjectIdentityIcon(identity: identity)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1)
                Text(identity.title(languageCode: LanguageSettings.shared.language.rawValue))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
