import Foundation

public struct LeonardoRubricSize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double = 180, height: Double = 60) { self.width = width; self.height = height }
}
