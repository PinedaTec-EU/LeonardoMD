import SwiftUI

/// Pointer coordinates and header frames belong to the same window-local bar.
enum TabReordering {
    static let coordinateSpace = "document-tab-bar"

    static func destination(at point: CGPoint, frames: [UUID: CGRect], excluding sourceID: UUID) -> UUID? {
        frames.first { id, frame in id != sourceID && frame.contains(point) }?.key
    }
}

struct TabDragState: Equatable {
    let sourceID: UUID
    let translation: CGSize
    let location: CGPoint
}

struct TabFramesPreference: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// Two vertical columns of dots identify the reorder affordance.
struct DocumentTabGrip: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<2) { _ in
                VStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        Circle().frame(width: 2.5, height: 2.5)
                    }
                }
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
    }
}
