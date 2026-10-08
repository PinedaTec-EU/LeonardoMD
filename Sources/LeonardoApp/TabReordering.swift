import SwiftUI

/// Pointer coordinates and header frames belong to the same window-local bar.
enum TabReordering {
    static let coordinateSpace = "document-tab-bar"

    static func destination(at point: CGPoint, frames: [UUID: CGRect], excluding sourceID: UUID) -> UUID? {
        frames.first { id, frame in id != sourceID && frame.contains(point) }?.key
    }
}

struct TabFramesPreference: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
