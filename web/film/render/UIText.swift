import AppKit
import CoreGraphics

/// Text and SF Symbol drawing into a top-left-origin CGContext.
enum UIText {
    static func font(_ size: Double, _ weight: NSFont.Weight, mono: Bool = false) -> NSFont {
        mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func attributes(size: Double, weight: NSFont.Weight, color: RGB, alpha: Double = 1, align: NSTextAlignment = .left, mono: Bool = false, tracking: Double = 0, lineHeight: Double? = nil) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineBreakMode = .byWordWrapping
        if let lineHeight {
            para.minimumLineHeight = lineHeight
            para.maximumLineHeight = lineHeight
        }
        var a: [NSAttributedString.Key: Any] = [
            .font: font(size, weight, mono: mono),
            .foregroundColor: NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: alpha),
            .paragraphStyle: para,
        ]
        if tracking != 0 { a[.kern] = tracking }
        return a
    }

    static func width(_ s: String, size: Double, weight: NSFont.Weight, mono: Bool = false, tracking: Double = 0) -> Double {
        (s as NSString).size(withAttributes: attributes(size: size, weight: weight, color: RGB(0, 0, 0), mono: mono, tracking: tracking)).width
    }

    static func height(_ s: String, width w: Double, size: Double, weight: NSFont.Weight, lineHeight: Double? = nil) -> Double {
        let r = (s as NSString).boundingRect(with: CGSize(width: w, height: 10_000), options: [.usesLineFragmentOrigin], attributes: attributes(size: size, weight: weight, color: RGB(0, 0, 0), lineHeight: lineHeight))
        return ceil(r.height)
    }

    private static func withContext(_ ctx: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func draw(_ s: String, in rect: CGRect, ctx: CGContext, size: Double, weight: NSFont.Weight, color: RGB, alpha: Double = 1, align: NSTextAlignment = .left, mono: Bool = false, tracking: Double = 0, lineHeight: Double? = nil) {
        withContext(ctx) {
            (s as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attributes(size: size, weight: weight, color: color, alpha: alpha, align: align, mono: mono, tracking: tracking, lineHeight: lineHeight))
        }
    }

    /// Draws a single line with its left edge (or center/right, per `align`) at `x` and its top at `y`.
    static func line(_ s: String, x: Double, y: Double, ctx: CGContext, size: Double, weight: NSFont.Weight, color: RGB, alpha: Double = 1, align: NSTextAlignment = .left, mono: Bool = false, tracking: Double = 0) {
        let w = width(s, size: size, weight: weight, mono: mono, tracking: tracking) + 2
        let left: Double
        switch align {
        case .center: left = x - w / 2
        case .right: left = x - w
        default: left = x
        }
        draw(s, in: CGRect(x: left, y: y, width: w, height: size * 1.4), ctx: ctx, size: size, weight: weight, color: color, alpha: alpha, align: .left, mono: mono, tracking: tracking)
    }

    private static var symbolCache: [String: NSImage] = [:]

    static func symbol(_ name: String, in rect: CGRect, ctx: CGContext, color: RGB, weight: NSFont.Weight = .semibold, alpha: Double = 1) {
        let key = "\(name)|\(Int(rect.height))|\(color.r),\(color.g),\(color.b)|\(weight.rawValue)"
        let image: NSImage
        if let cached = symbolCache[key] {
            image = cached
        } else {
            guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
            let config = NSImage.SymbolConfiguration(pointSize: rect.height, weight: weight)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1)]))
            image = base.withSymbolConfiguration(config) ?? base
            symbolCache[key] = image
        }
        let s = image.size
        let k = min(rect.width / s.width, rect.height / s.height)
        let r = CGRect(x: rect.midX - s.width * k / 2, y: rect.midY - s.height * k / 2, width: s.width * k, height: s.height * k)
        withContext(ctx) {
            image.draw(in: r, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        }
    }
}

extension CGContext {
    func fillRound(_ r: CGRect, radius: Double, color: RGB, alpha: Double = 1) {
        addPath(CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil))
        setFillColor(color.cg(alpha))
        fillPath()
    }

    func strokeRound(_ r: CGRect, radius: Double, color: RGB, width: Double, alpha: Double = 1) {
        addPath(CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil))
        setStrokeColor(color.cg(alpha))
        setLineWidth(width)
        strokePath()
    }

    func shadowed(blur: Double, offset: CGSize = CGSize(width: 0, height: 12), alpha: Double = 0.45, _ body: () -> Void) {
        saveGState()
        setShadow(offset: offset, blur: blur, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha))
        body()
        restoreGState()
    }
}
