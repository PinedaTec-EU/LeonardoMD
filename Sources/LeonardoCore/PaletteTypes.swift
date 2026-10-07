import Foundation

// MARK: - Portable visual and Markdown settings

public enum PaletteID: String, Codable, CaseIterable, Hashable, Sendable {
    case leonardoClassic = "leonardo-classic"
    case paperWhite = "paper-white"
    case graphiteGlass = "graphite-glass"
}

public enum PaperEffect: String, Codable, CaseIterable, Hashable, Sendable {
    case white
    case solid
    case ruled
    case grid
    case microgrid
    case parchment
}

public enum MarkdownMode: String, Codable, CaseIterable, Hashable, Sendable {
    case preview
    case edit
    case split
}

public struct PaletteTokens: Codable, Hashable, Sendable {
    public let surface: String
    public let text: String
    public let heading: String
    public let accent: String
    public let border: String
    public let codeBackground: String
    public let quote: String

    public init(
        surface: String,
        text: String,
        heading: String,
        accent: String,
        border: String,
        codeBackground: String,
        quote: String
    ) {
        self.surface = surface
        self.text = text
        self.heading = heading
        self.accent = accent
        self.border = border
        self.codeBackground = codeBackground
        self.quote = quote
    }
}

public struct PaletteTokenOverrides: Codable, Hashable, Sendable {
    public var surface: String?
    public var text: String?
    public var heading: String?
    public var accent: String?
    public var border: String?
    public var codeBackground: String?
    public var quote: String?

    public init(
        surface: String? = nil,
        text: String? = nil,
        heading: String? = nil,
        accent: String? = nil,
        border: String? = nil,
        codeBackground: String? = nil,
        quote: String? = nil
    ) {
        self.surface = surface
        self.text = text
        self.heading = heading
        self.accent = accent
        self.border = border
        self.codeBackground = codeBackground
        self.quote = quote
    }

    public func applying(to base: PaletteTokens) -> PaletteTokens {
        PaletteTokens(
            surface: surface ?? base.surface,
            text: text ?? base.text,
            heading: heading ?? base.heading,
            accent: accent ?? base.accent,
            border: border ?? base.border,
            codeBackground: codeBackground ?? base.codeBackground,
            quote: quote ?? base.quote
        )
    }
}

public struct PaletteDefinition: Codable, Hashable, Identifiable, Sendable {
    public let id: PaletteID
    public let displayName: String
    public let tokens: PaletteTokens

    public init(id: PaletteID, displayName: String, tokens: PaletteTokens) {
        self.id = id
        self.displayName = displayName
        self.tokens = tokens
    }
}

public struct PaletteContrastReport: Codable, Hashable, Sendable {
    public let textOnSurface: Double
    public let headingOnSurface: Double
    public let accentOnSurface: Double
    public let passesNormalText: Bool
    public let passesHeading: Bool
    public let passesAccent: Bool

    public var isValid: Bool { passesNormalText && passesHeading && passesAccent }

    public init(
        textOnSurface: Double,
        headingOnSurface: Double,
        accentOnSurface: Double,
        passesNormalText: Bool,
        passesHeading: Bool,
        passesAccent: Bool
    ) {
        self.textOnSurface = textOnSurface
        self.headingOnSurface = headingOnSurface
        self.accentOnSurface = accentOnSurface
        self.passesNormalText = passesNormalText
        self.passesHeading = passesHeading
        self.passesAccent = passesAccent
    }
}

public enum PaletteCatalog {
    public static let leonardoClassic = PaletteDefinition(
        id: .leonardoClassic,
        displayName: "Leonardo Classic",
        tokens: PaletteTokens(
            surface: "#E7D6AD",
            text: "#11100D",
            heading: "#7A1114",
            // The original oxide accent (#A24F2A) is below 4.5:1 on the
            // parchment surface. This darker oxide keeps the same warm hue
            // while meeting normal-text contrast for links and buttons.
            accent: "#8C3F22",
            border: "#9C8052",
            codeBackground: "#D7C18F",
            quote: "#6B5835"
        )
    )

    public static let paperWhite = PaletteDefinition(
        id: .paperWhite,
        displayName: "Paper White",
        tokens: PaletteTokens(
            surface: "#F8F8F5",
            text: "#171717",
            heading: "#254B70",
            accent: "#2B5C8A",
            border: "#C7CDD3",
            codeBackground: "#E9EDF0",
            quote: "#53616D"
        )
    )

    public static let graphiteGlass = PaletteDefinition(
        id: .graphiteGlass,
        displayName: "Graphite Glass",
        tokens: PaletteTokens(
            surface: "#1F2328",
            text: "#F2F5F7",
            heading: "#9AC9D7",
            accent: "#6AA6B8",
            border: "#4A535D",
            codeBackground: "#2A3037",
            quote: "#B6C4CB"
        )
    )

    public static let all: [PaletteDefinition] = [leonardoClassic, paperWhite, graphiteGlass]

    public static func definition(for id: PaletteID) -> PaletteDefinition {
        switch id {
        case .leonardoClassic: leonardoClassic
        case .paperWhite: paperWhite
        case .graphiteGlass: graphiteGlass
        }
    }

    public static func contrastRatio(_ foreground: String, _ background: String) -> Double {
        guard let foreground = rgbComponents(from: foreground),
              let background = rgbComponents(from: background) else {
            return 1
        }
        let foregroundLuminance = relativeLuminance(foreground)
        let backgroundLuminance = relativeLuminance(background)
        return (max(foregroundLuminance, backgroundLuminance) + 0.05)
            / (min(foregroundLuminance, backgroundLuminance) + 0.05)
    }

    public static func contrastRatio(foreground: String, background: String) -> Double {
        contrastRatio(foreground, background)
    }

    public static func meetsWCAGAA(_ ratio: Double, largeText: Bool = false) -> Bool {
        ratio >= (largeText ? 3.0 : 4.5)
    }

    public static func contrastReport(for palette: PaletteDefinition) -> PaletteContrastReport {
        let text = contrastRatio(palette.tokens.text, palette.tokens.surface)
        let heading = contrastRatio(palette.tokens.heading, palette.tokens.surface)
        let accent = contrastRatio(palette.tokens.accent, palette.tokens.surface)
        return PaletteContrastReport(
            textOnSurface: text,
            headingOnSurface: heading,
            accentOnSurface: accent,
            passesNormalText: meetsWCAGAA(text),
            passesHeading: meetsWCAGAA(heading, largeText: true),
            passesAccent: meetsWCAGAA(accent)
        )
    }

    public static func validatesContrast(for palette: PaletteDefinition) -> Bool {
        contrastReport(for: palette).isValid
    }

    private static func rgbComponents(from value: String) -> (Double, Double, Double)? {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 || hex.count == 8,
              let raw = UInt64(String(hex.prefix(6)), radix: 16) else {
            return nil
        }
        return (
            Double((raw >> 16) & 0xFF) / 255,
            Double((raw >> 8) & 0xFF) / 255,
            Double(raw & 0xFF) / 255
        )
    }

    private static func relativeLuminance(_ components: (Double, Double, Double)) -> Double {
        func linearize(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let red = linearize(components.0)
        let green = linearize(components.1)
        let blue = linearize(components.2)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

public extension PaletteDefinition {
    var contrastReport: PaletteContrastReport { PaletteCatalog.contrastReport(for: self) }
}
