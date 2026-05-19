import AppKit

enum Design {
    static let parchment = NSColor(hex: 0x08090A)
    static let ivory = NSColor(hex: 0x0F1011)
    static let warmSand = NSColor(hex: 0x191A1B)
    static let nearBlack = NSColor(hex: 0xF7F8F8)
    static let charcoal = NSColor(hex: 0xD0D6E0)
    static let oliveGray = NSColor(hex: 0x8A8F98)
    static let stone = NSColor(hex: 0x62666D)
    static let terracotta = NSColor(hex: 0x7170FF)
    static let border = NSColor(hex: 0x34343A)
    static let error = NSColor(hex: 0xFF6B6B)
    static let brand = NSColor(hex: 0x5E6AD2)

    static func titleFont(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func uiFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

final class PanelView: NSView {
    var fillColor: NSColor = Design.ivory {
        didSet { needsDisplay = true }
    }

    var strokeColor: NSColor = Design.border {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
