import Foundation

/// The rubric field's origin on a physical page, in points, with clockwise rotation.
public struct LeonardoRubricPlacement: Codable, Equatable, Sendable {
    public var page: Int
    public var x: Double
    public var y: Double
    public var rotation: Int

    public init(page: Int, x: Double, y: Double, rotation: Int = 0) {
        self.page = page
        self.x = x
        self.y = y
        self.rotation = rotation
    }

    public var isValid: Bool {
        (1...999).contains(page) && [x, y].allSatisfy { $0.isFinite && abs($0) <= 10000 }
            && [0, 90, 180, 270].contains(rotation)
    }
}

/// A preview edit changes only the field's presentation. The field ID and answer remain intact.
public struct LeonardoRubricLayoutEdit: Decodable, Sendable {
    public let fieldID: String
    public let placement: LeonardoRubricPlacement?
    public let size: LeonardoRubricSize

    public init(fieldID: String, placement: LeonardoRubricPlacement?, size: LeonardoRubricSize) {
        self.fieldID = fieldID
        self.placement = placement
        self.size = size
    }

    public var isValid: Bool {
        [size.width, size.height].allSatisfy { $0.isFinite && $0 > 0 && $0 <= 10000 }
            && (placement?.isValid ?? true)
    }
}
