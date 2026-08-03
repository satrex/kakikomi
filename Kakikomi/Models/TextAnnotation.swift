import AppKit
import CoreText

struct TextAnnotation: Annotation {
    var id = UUID()
    var text: String
    var origin: CGPoint
    var fontSize: CGFloat
    var fontName: String
    var fillColor: CodableColor
    var outlineColor: CodableColor
    var outlineWidthRatio: CGFloat
    var shadowEnabled: Bool

    init(
        id: UUID = UUID(),
        text: String = "",
        origin: CGPoint,
        fontSize: CGFloat = 48,
        fontName: String = "HiraginoSans-W7",
        fillColor: CodableColor = .white,
        outlineColor: CodableColor = .darkOutline,
        outlineWidthRatio: CGFloat = 0.12,
        shadowEnabled: Bool = true
    ) {
        self.id = id
        self.text = text
        self.origin = origin
        self.fontSize = fontSize
        self.fontName = fontName
        self.fillColor = fillColor
        self.outlineColor = outlineColor
        self.outlineWidthRatio = outlineWidthRatio
        self.shadowEnabled = shadowEnabled
    }

    var font: NSFont {
        NSFont(name: fontName, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
    }

    var frame: CGRect {
        get { CGRect(origin: origin, size: measuredSize) }
        set { origin = newValue.origin }
    }

    var measuredSize: CGSize {
        let lines = text.components(separatedBy: "\n")
        let widths = lines.map { line -> CGFloat in
            let value = line.isEmpty ? " " : line
            let attributed = NSAttributedString(string: value, attributes: [.font: font])
            return ceil(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil))
        }
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return CGSize(width: max(widths.max() ?? fontSize, fontSize * 0.5),
                      height: max(lineHeight * CGFloat(max(lines.count, 1)), lineHeight))
    }

    func hitTest(_ point: CGPoint) -> Bool {
        let slop = max(fontSize * outlineWidthRatio, 6)
        return frame.insetBy(dx: -slop, dy: -slop).contains(point)
    }
}
