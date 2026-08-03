import AppKit

struct CodableColor: Codable, Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.sRGB) ?? color
        red = converted.redComponent
        green = converted.greenComponent
        blue = converted.blueComponent
        alpha = converted.alphaComponent
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var relativeLuminance: CGFloat {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    var automaticOutlineColor: CodableColor {
        relativeLuminance > 0.5 ? .darkOutline : .white
    }

    static let white = CodableColor(red: 1, green: 1, blue: 1)
    static let darkOutline = CodableColor(red: CGFloat(0x1A) / 255, green: CGFloat(0x1A) / 255, blue: CGFloat(0x1A) / 255)
    static let accentPink = CodableColor(red: 1, green: CGFloat(0x3B) / 255, blue: CGFloat(0x7B) / 255)
}
