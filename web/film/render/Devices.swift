import AppKit
import CoreGraphics

/// The rider's iPhone, the Watch, the contact's iPhone and the near-miss log, drawn to match the
/// app (Whoosh/Support/Theme/Theme.swift, ActiveRideView.swift) and the website's device mocks.

enum Palette {
    static let ink = RGB(hex: 0x0B0F14)
    static let lime = RGB(hex: 0xC8F135)
    static let amber = RGB(hex: 0xF5A524)
    static let mist = RGB(hex: 0xF4F5F7)
    static let card = RGB(hex: 0x11161D)
    static let stroke = RGB(hex: 0x2A3542)
    static let secondary = RGB(hex: 0x8A94A3)
    static let secondaryLight = RGB(hex: 0x5B6472)
    static let rec = RGB(hex: 0xE5484D)
    static let positive = RGB(hex: 0x2FB344)
    static let crash = RGB(hex: 0x3A0D10)
    static let white = RGB(1, 1, 1)
}

/// Route geometry in meters, for the phone map.
struct RouteMap {
    let pts: [(Double, Double)]   // x east, y south (screen-like), meters from the first point
    let cumulative: [Double]

    init(_ route: RouteInfo) {
        let lat0 = route.points[0][1], lon0 = route.points[0][0]
        let mLat = 111_132.0, mLon = 111_320.0 * cos(lat0 * .pi / 180)
        pts = route.points.map { (($0[0] - lon0) * mLon, -($0[1] - lat0) * mLat) }
        var c: [Double] = [0]
        for i in 1..<pts.count {
            c.append(c[i - 1] + hypot(pts[i].0 - pts[i - 1].0, pts[i].1 - pts[i - 1].1))
        }
        cumulative = c
    }

    func at(_ meters: Double) -> (Double, Double) {
        let m = max(0, min(meters, cumulative.last!))
        var i = 1
        while i < cumulative.count - 1 && cumulative[i] < m { i += 1 }
        let span = max(1e-6, cumulative[i] - cumulative[i - 1])
        let f = (m - cumulative[i - 1]) / span
        return (lerp(pts[i - 1].0, pts[i].0, f), lerp(pts[i - 1].1, pts[i].1, f))
    }
}

struct PhoneContext {
    let snap: SimSnapshot
    let route: RouteMap
    let time: Double            // film time, for pulses
    var tap: (CGPoint, Double)? // tap position (phone coords) and progress 0...1
    var pressStart = false
}

enum Devices {
    static let phoneSize = CGSize(width: 300, height: 620)

    // MARK: Frames

    static func phoneFrame(_ ctx: CGContext, light: Bool, body: (CGRect) -> Void) {
        let outer = CGRect(origin: .zero, size: phoneSize)
        ctx.shadowed(blur: 40, offset: CGSize(width: 0, height: 18), alpha: 0.5) {
            ctx.fillRound(outer, radius: 50, color: RGB(hex: 0x1B1D21))
        }
        ctx.strokeRound(outer.insetBy(dx: 1, dy: 1), radius: 49, color: RGB(hex: 0x5A5F66), width: 2)
        let screen = outer.insetBy(dx: 10, dy: 10)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 41, cornerHeight: 41, transform: nil))
        ctx.clip()
        ctx.setFillColor((light ? Palette.mist : Palette.ink).cg())
        ctx.fill(screen)
        ctx.translateBy(x: screen.minX, y: screen.minY)
        body(CGRect(origin: .zero, size: screen.size))
        ctx.restoreGState()
        // Dynamic Island.
        ctx.fillRound(CGRect(x: outer.midX - 46, y: 21, width: 92, height: 27), radius: 14, color: RGB(0, 0, 0))
    }

    static func statusBar(_ ctx: CGContext, width: Double, clock: String, dark: Bool) {
        let c = dark ? Palette.white : Palette.ink
        let time = clock.replacingOccurrences(of: " PM", with: "").replacingOccurrences(of: " AM", with: "")
        UIText.line(time, x: 34, y: 17, ctx: ctx, size: 14, weight: .semibold, color: c)
        UIText.symbol("cellularbars", in: CGRect(x: width - 86, y: 19, width: 18, height: 12), ctx: ctx, color: c)
        UIText.symbol("wifi", in: CGRect(x: width - 64, y: 19, width: 17, height: 12), ctx: ctx, color: c)
        UIText.symbol("battery.75percent", in: CGRect(x: width - 42, y: 18, width: 26, height: 13), ctx: ctx, color: c)
    }

    // MARK: Rider's phone

    static func riderPhone(_ ctx: CGContext, _ p: PhoneContext) {
        let s = p.snap
        let phase = s.crashPhase
        let light = !s.recording
        phoneFrame(ctx, light: light) { r in
            if !s.recording {
                homeScreen(ctx, r, p)
            } else if phase == "countdown" {
                countdownScreen(ctx, r, p)
            } else if phase == "sending" || phase == "sent" {
                statusScreen(ctx, r, p)
            } else {
                rideScreen(ctx, r, p)
            }
            statusBar(ctx, width: r.width, clock: s.clock, dark: s.recording)
            if let (pt, k) = p.tap {
                let rr = 18 + 26 * k
                ctx.setFillColor(RGB(1, 1, 1).cg(0.55 * (1 - k)))
                ctx.fillEllipse(in: CGRect(x: pt.x - rr, y: pt.y - rr, width: rr * 2, height: rr * 2))
                ctx.setFillColor(RGB(0.2, 0.2, 0.2).cg(0.35 * (1 - k * 0.6)))
                ctx.fillEllipse(in: CGRect(x: pt.x - 17, y: pt.y - 17, width: 34, height: 34))
            }
        }
    }

    static let startButton = CGRect(x: 16, y: 494, width: 248, height: 56)

    private static func homeScreen(_ ctx: CGContext, _ r: CGRect, _ p: PhoneContext) {
        let ink = Palette.ink
        var y = 58.0
        UIText.line("whoosh", x: 18, y: y, ctx: ctx, size: 30, weight: .heavy, color: ink, tracking: -0.6)
        ctx.setFillColor(Palette.lime.cg())
        ctx.fill(CGRect(x: 18 + UIText.width("whoosh", size: 30, weight: .heavy, tracking: -0.6) - 24, y: y + 37, width: 24, height: 4))
        UIText.line("Ready to ride?", x: 18, y: y + 44, ctx: ctx, size: 13, weight: .regular, color: Palette.secondaryLight)
        ctx.fillRound(CGRect(x: r.width - 62, y: y + 2, width: 44, height: 44), radius: 22, color: Palette.white)
        UIText.symbol("gearshape", in: CGRect(x: r.width - 51, y: y + 13, width: 22, height: 22), ctx: ctx, color: ink, weight: .medium)
        y += 76
        // This week.
        ctx.fillRound(CGRect(x: 16, y: y, width: r.width - 32, height: 92), radius: 18, color: Palette.white)
        UIText.line("THIS WEEK", x: 32, y: y + 14, ctx: ctx, size: 11, weight: .semibold, color: Palette.secondaryLight, tracking: 0.8)
        UIText.line("12.4", x: 32, y: y + 32, ctx: ctx, size: 30, weight: .bold, color: ink, mono: true)
        UIText.line("mi", x: 32 + UIText.width("12.4", size: 30, weight: .bold, mono: true) + 4, y: y + 45, ctx: ctx, size: 15, weight: .semibold, color: Palette.secondaryLight)
        UIText.line("3 rides · 1h 02m", x: 32, y: y + 68, ctx: ctx, size: 12, weight: .regular, color: Palette.secondaryLight)
        let bars: [Double] = [0, 0.6, 0, 0.35, 1, 0, 0]
        for (i, b) in bars.enumerated() {
            let bx = r.width - 140 + Double(i) * 15
            let h = b > 0 ? max(6, b * 32) : 3
            ctx.fillRound(CGRect(x: bx, y: y + 56 - h, width: 8, height: h), radius: 2, color: b > 0 ? ink : RGB(hex: 0xEEF0F3))
            UIText.line(["M", "T", "W", "T", "F", "S", "S"][i], x: bx + 4, y: y + 62, ctx: ctx, size: 8, weight: .regular, color: Palette.secondaryLight, align: .center)
        }
        y += 106
        UIText.line("Recent rides", x: 18, y: y, ctx: ctx, size: 15, weight: .bold, color: ink)
        UIText.line("See all ›", x: r.width - 18, y: y + 2, ctx: ctx, size: 13, weight: .semibold, color: ink, align: .right)
        y += 28
        ctx.fillRound(CGRect(x: 16, y: y, width: r.width - 32, height: 62), radius: 16, color: Palette.white)
        ctx.fillRound(CGRect(x: 28, y: y + 11, width: 40, height: 40), radius: 9, color: ink)
        ctx.setStrokeColor(Palette.lime.cg()); ctx.setLineWidth(2.5); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addLines(between: [CGPoint(x: 36, y: y + 42), CGPoint(x: 45, y: y + 30), CGPoint(x: 52, y: y + 34), CGPoint(x: 61, y: y + 19)])
        ctx.strokePath()
        UIText.line("Thu, Oct 22 · 5:48 PM", x: 80, y: y + 12, ctx: ctx, size: 14, weight: .semibold, color: ink)
        UIText.line("5.32 mi · 24:18 · 13.1 mph", x: 80, y: y + 33, ctx: ctx, size: 12, weight: .regular, color: Palette.secondaryLight)
        y += 76
        for (icon, title, sub) in [("car.rear.fill", "Rear vehicle detection", "On · experimental"), ("cross.case.fill", "Crash alerts", "On · texts Sam")] {
            ctx.fillRound(CGRect(x: 16, y: y, width: r.width - 32, height: 56), radius: 16, color: Palette.white)
            ctx.fillRound(CGRect(x: 28, y: y + 10, width: 36, height: 36), radius: 10, color: ink)
            UIText.symbol(icon, in: CGRect(x: 36, y: y + 18, width: 20, height: 20), ctx: ctx, color: Palette.lime)
            UIText.line(title, x: 76, y: y + 10, ctx: ctx, size: 14, weight: .semibold, color: ink)
            UIText.line(sub, x: 76, y: y + 30, ctx: ctx, size: 12, weight: .regular, color: Palette.secondaryLight)
            // Toggle, on.
            ctx.fillRound(CGRect(x: r.width - 76, y: y + 16, width: 46, height: 26), radius: 13, color: Palette.positive)
            ctx.setFillColor(Palette.white.cg()); ctx.fillEllipse(in: CGRect(x: r.width - 52, y: y + 18, width: 22, height: 22))
            y += 64
        }
        let b = startButton
        let pressed = p.pressStart
        let br = pressed ? b.insetBy(dx: 4, dy: 2) : b
        ctx.fillRound(br, radius: br.height / 2, color: pressed ? Palette.lime.scaled(0.9) : Palette.lime)
        UIText.symbol("play.fill", in: CGRect(x: br.midX - 64, y: br.midY - 9, width: 18, height: 18), ctx: ctx, color: ink, weight: .bold)
        UIText.line("Start Ride", x: br.midX + 12, y: br.midY - 12, ctx: ctx, size: 18, weight: .bold, color: ink, align: .center)
        let chip = CGRect(x: r.width / 2 - 52, y: b.maxY + 12, width: 104, height: 28)
        ctx.fillRound(chip, radius: 14, color: RGB(hex: 0xE9EBEF))
        UIText.symbol("dot.radiowaves.left.and.right", in: CGRect(x: chip.minX + 11, y: chip.minY + 8, width: 14, height: 12), ctx: ctx, color: Palette.positive)
        UIText.line("GPS ready", x: chip.minX + 31, y: chip.minY + 6, ctx: ctx, size: 12, weight: .semibold, color: ink)
    }

    private static func chip(_ ctx: CGContext, x: Double, y: Double, icon: String, iconColor: RGB, text: String, dot: Bool = false) -> Double {
        let w = UIText.width(text, size: 12, weight: .semibold) + 46
        let r = CGRect(x: x, y: y, width: w, height: 30)
        ctx.fillRound(r, radius: 15, color: Palette.ink, alpha: 0.9)
        ctx.strokeRound(r, radius: 15, color: Palette.stroke, width: 1)
        if dot {
            ctx.setFillColor(iconColor.cg()); ctx.fillEllipse(in: CGRect(x: x + 13, y: y + 10, width: 10, height: 10))
        } else {
            UIText.symbol(icon, in: CGRect(x: x + 11, y: y + 8, width: 15, height: 14), ctx: ctx, color: iconColor)
        }
        UIText.line(text, x: x + 33, y: y + 7, ctx: ctx, size: 12, weight: .semibold, color: Palette.white)
        return w
    }

    private static func map(_ ctx: CGContext, _ rect: CGRect, _ p: PhoneContext, crashed: Bool) {
        let s = p.snap
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setFillColor(RGB(hex: 0x141A22).cg())
        ctx.fill(rect)
        let here = p.route.at(s.riderDistance)
        let mPerPx = 0.62
        func P(_ q: (Double, Double)) -> CGPoint {
            CGPoint(x: rect.midX + (q.0 - here.0) / mPerPx, y: rect.minY + rect.height * 0.62 + (q.1 - here.1) / mPerPx)
        }
        // Blocks and cross streets.
        let pts = p.route.pts
        ctx.setLineCap(.butt)
        for i in 1..<(pts.count - 1) {
            let a = pts[i - 1], b = pts[i + 1], c = pts[i]
            let dx = b.0 - a.0, dy = b.1 - a.1
            let l = max(1e-6, hypot(dx, dy))
            let o = (-dy / l * 220, dx / l * 220)
            ctx.setStrokeColor(RGB(hex: 0x1F2833).cg()); ctx.setLineWidth(9)
            ctx.move(to: P((c.0 - o.0, c.1 - o.1))); ctx.addLine(to: P((c.0 + o.0, c.1 + o.1))); ctx.strokePath()
        }
        // River at the north end.
        let river = P((pts.last!.0 - 400, pts.last!.1 - 40))
        ctx.setFillColor(RGB(hex: 0x17304A).cg())
        ctx.fill(CGRect(x: river.x, y: river.y - 400, width: 2000, height: 400))
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        ctx.setStrokeColor(RGB(hex: 0x2A3542).cg()); ctx.setLineWidth(15)
        ctx.addLines(between: pts.map(P)); ctx.strokePath()
        UIText.line("Mass Ave", x: P(pts[4]).x + 14, y: P(pts[4]).y - 6, ctx: ctx, size: 10, weight: .medium, color: RGB(hex: 0x6B7888))
        // Ridden path.
        var ridden: [CGPoint] = [P(pts[0])]
        var m = 4.0
        while m < s.riderDistance { ridden.append(P(p.route.at(m))); m += 4 }
        ridden.append(P(here))
        ctx.setStrokeColor(Palette.ink.cg()); ctx.setLineWidth(10); ctx.addLines(between: ridden); ctx.strokePath()
        ctx.setStrokeColor(Palette.lime.cg()); ctx.setLineWidth(6); ctx.addLines(between: ridden); ctx.strokePath()
        let st = P(pts[0])
        ctx.setFillColor(Palette.white.cg()); ctx.fillEllipse(in: CGRect(x: st.x - 7, y: st.y - 7, width: 14, height: 14))
        ctx.setStrokeColor(Palette.ink.cg()); ctx.setLineWidth(2.5); ctx.strokeEllipse(in: CGRect(x: st.x - 7, y: st.y - 7, width: 14, height: 14))
        for nm in s.nearMisses {
            let q = P(p.route.at(nm.at))
            let d = [CGPoint(x: q.x, y: q.y - 9), CGPoint(x: q.x + 8, y: q.y), CGPoint(x: q.x, y: q.y + 9), CGPoint(x: q.x - 8, y: q.y)]
            ctx.addPath(path(d)); ctx.setFillColor((nm.source == "rider_reported" ? Palette.lime : Palette.amber).cg()); ctx.fillPath()
            ctx.addPath(path(d)); ctx.setStrokeColor(Palette.ink.cg()); ctx.setLineWidth(2); ctx.strokePath()
        }
        let me = P(here)
        let dotC = crashed ? Palette.rec : Palette.lime
        let pulse = 0.5 + 0.5 * sin(p.time * 3)
        ctx.setFillColor(dotC.cg(0.18 + 0.1 * pulse)); ctx.fillEllipse(in: CGRect(x: me.x - 22, y: me.y - 22, width: 44, height: 44))
        ctx.setFillColor(Palette.white.cg()); ctx.fillEllipse(in: CGRect(x: me.x - 9, y: me.y - 9, width: 18, height: 18))
        ctx.setFillColor(dotC.cg()); ctx.fillEllipse(in: CGRect(x: me.x - 5.5, y: me.y - 5.5, width: 11, height: 11))
        ctx.restoreGState()
    }

    static let markButton = CGRect(x: 16, y: 518, width: 178, height: 56)

    private static func rideScreen(_ ctx: CGContext, _ r: CGRect, _ p: PhoneContext) {
        let s = p.snap
        map(ctx, CGRect(x: 0, y: 0, width: r.width, height: 330), p, crashed: false)
        let cancelledOK = s.crashPhase == "cancelled"
        if s.cue {
            let b = CGRect(x: 14, y: 54, width: r.width - 28, height: 58)
            ctx.shadowed(blur: 12, offset: CGSize(width: 0, height: 4), alpha: 0.4) { ctx.fillRound(b, radius: 16, color: Palette.amber) }
            UIText.symbol("exclamationmark.triangle.fill", in: CGRect(x: b.minX + 13, y: b.minY + 13, width: 22, height: 20), ctx: ctx, color: Palette.ink)
            UIText.line("Vehicle behind", x: b.minX + 46, y: b.minY + 10, ctx: ctx, size: 15, weight: .bold, color: Palette.ink)
            UIText.line("\(hintText(s.lastCueHint)) · caution", x: b.minX + 46, y: b.minY + 31, ctx: ctx, size: 12, weight: .regular, color: Palette.ink, alpha: 0.78)
        } else if cancelledOK {
            let b = CGRect(x: 14, y: 54, width: r.width - 28, height: 58)
            ctx.fillRound(b, radius: 16, color: Palette.lime)
            UIText.line("Glad you're OK", x: b.minX + 16, y: b.minY + 10, ctx: ctx, size: 15, weight: .bold, color: Palette.ink)
            UIText.line("No alert was sent.", x: b.minX + 16, y: b.minY + 31, ctx: ctx, size: 12, weight: .regular, color: Palette.ink)
        } else {
            _ = chip(ctx, x: 16, y: 56, icon: "", iconColor: Palette.rec, text: "Recording", dot: true)
        }
        if s.toast, let latest = s.nearMisses.first {
            let text = latest.source == "rider_reported" ? "Close call marked" : "Near miss logged"
            let y = s.cue ? 122.0 : 96.0
            let w = UIText.width(text, size: 13, weight: .bold) + 52
            let b = CGRect(x: 16, y: y, width: w, height: 34)
            ctx.fillRound(b, radius: 12, color: Palette.ink, alpha: 0.94)
            ctx.strokeRound(b, radius: 12, color: Palette.amber, width: 1.2, alpha: 0.7)
            UIText.symbol("diamond.fill", in: CGRect(x: b.minX + 12, y: b.minY + 10, width: 14, height: 14), ctx: ctx, color: Palette.amber)
            UIText.line(text, x: b.minX + 34, y: b.minY + 8, ctx: ctx, size: 13, weight: .bold, color: Palette.amber)
        }
        let cw = chip(ctx, x: 16, y: 284, icon: "eye.fill", iconColor: Palette.lime, text: "Rear detection on")
        _ = cw
        _ = chip(ctx, x: r.width - 70, y: 284, icon: "diamond.fill", iconColor: Palette.amber, text: "\(s.nearMisses.count)")

        // Bottom sheet.
        let sheet = CGRect(x: 0, y: 328, width: r.width, height: r.height - 328 + 30)
        ctx.fillRound(sheet, radius: 28, color: Palette.card)
        ctx.fillRound(CGRect(x: r.width / 2 - 16, y: 340, width: 32, height: 4), radius: 2, color: Palette.stroke)
        UIText.line("RIDE TIME", x: r.width / 2, y: 354, ctx: ctx, size: 10, weight: .semibold, color: Palette.secondary, align: .center, tracking: 1)
        UIText.line(formatDuration(s.rideTime), x: r.width / 2, y: 366, ctx: ctx, size: 50, weight: .bold, color: Palette.white, align: .center, mono: true)
        let metricsY = 432.0
        func metric(_ cx: Double, _ value: String, _ unit: String, _ label: String) {
            let vw = UIText.width(value, size: 26, weight: .bold, mono: true)
            let uw = UIText.width(unit, size: 13, weight: .semibold)
            let left = cx - (vw + 3 + uw) / 2
            UIText.line(value, x: left, y: metricsY, ctx: ctx, size: 26, weight: .bold, color: Palette.white, mono: true)
            UIText.line(unit, x: left + vw + 3, y: metricsY + 11, ctx: ctx, size: 13, weight: .semibold, color: Palette.secondary)
            UIText.line(label, x: cx, y: metricsY + 36, ctx: ctx, size: 9, weight: .semibold, color: Palette.secondary, align: .center, tracking: 1)
        }
        metric(r.width * 0.27, String(format: "%.2f", s.riderDistance / 1609.344), "mi", "DISTANCE")
        ctx.setFillColor(Palette.stroke.cg()); ctx.fill(CGRect(x: r.width / 2, y: metricsY + 2, width: 1, height: 42))
        metric(r.width * 0.73, s.riderSpeed > 0.2 ? String(format: "%.1f", s.riderSpeed * 2.2369362921) : "—", "mph", "SPEED")
        let pb = CGRect(x: 16, y: 500, width: 170, height: 56)
        ctx.fillRound(pb, radius: 28, color: Palette.lime)
        UIText.symbol("pause.fill", in: CGRect(x: pb.midX - 40, y: pb.midY - 9, width: 18, height: 18), ctx: ctx, color: Palette.ink, weight: .bold)
        UIText.line("Pause", x: pb.midX + 12, y: pb.midY - 12, ctx: ctx, size: 17, weight: .bold, color: Palette.ink, align: .center)
        let stop = CGRect(x: 198, y: 500, width: 66, height: 56)
        ctx.fillRound(stop, radius: 28, color: RGB(hex: 0x2A1517))
        ctx.strokeRound(stop.insetBy(dx: 0.75, dy: 0.75), radius: 28, color: Palette.rec, width: 1.5)
        ctx.fillRound(CGRect(x: stop.midX - 8, y: stop.minY + 13, width: 16, height: 16), radius: 3, color: Palette.rec)
        UIText.line("Hold", x: stop.midX, y: stop.minY + 33, ctx: ctx, size: 11, weight: .semibold, color: RGB(hex: 0xFF8A8D), align: .center)
        UIText.line("Hold Stop to end ride", x: r.width / 2, y: 566, ctx: ctx, size: 10, weight: .regular, color: Palette.secondary, align: .center)
    }

    static let okButton = CGRect(x: 16, y: 480, width: 248, height: 84)

    private static func countdownScreen(_ ctx: CGContext, _ r: CGRect, _ p: PhoneContext) {
        let s = p.snap
        let secs = Int(ceil(s.remaining ?? 0))
        // At most one luminance change per second (the spec's flashing-safe rule).
        let beat = (s.remaining ?? 0).truncatingRemainder(dividingBy: 1) > 0.5
        ctx.setFillColor((beat ? Palette.crash.scaled(1.25) : Palette.crash).cg())
        ctx.fill(r)
        let tag = "DRILL · SIMULATED CRASH"
        let tw = UIText.width(tag, size: 10, weight: .heavy, tracking: 1) + 20
        ctx.fillRound(CGRect(x: 18, y: 56, width: tw, height: 22), radius: 11, color: Palette.amber)
        UIText.line(tag, x: 28, y: 60, ctx: ctx, size: 10, weight: .heavy, color: Palette.ink, tracking: 1)
        let sn = CGRect(x: r.width - 96, y: 92, width: 80, height: 30)
        ctx.strokeRound(sn, radius: 15, color: Palette.white, width: 1, alpha: 0.4)
        UIText.line("Send now", x: sn.midX, y: sn.minY + 7, ctx: ctx, size: 12, weight: .semibold, color: Palette.white, align: .center)
        UIText.line("Crash detected", x: r.width / 2, y: 138, ctx: ctx, size: 26, weight: .bold, color: Palette.white, align: .center)
        UIText.line("\(secs)", x: r.width / 2, y: 178, ctx: ctx, size: 150, weight: .bold, color: Palette.white, align: .center, mono: true)
        UIText.draw("Sending an alert to Sam in \(secs) \(secs == 1 ? "second" : "seconds").", in: CGRect(x: 24, y: 362, width: r.width - 48, height: 50), ctx: ctx, size: 16, weight: .semibold, color: Palette.white, align: .center)
        UIText.draw("Whoosh is not an emergency service. It can't guarantee an alert is sent or read.", in: CGRect(x: 30, y: 418, width: r.width - 60, height: 40), ctx: ctx, size: 11, weight: .regular, color: RGB(hex: 0xD9B5B7), align: .center)
        let ok = okButton
        ctx.fillRound(ok, radius: 24, color: Palette.white)
        UIText.line("I'm OK — Cancel", x: ok.midX, y: ok.midY - 15, ctx: ctx, size: 23, weight: .bold, color: Palette.ink, align: .center)
    }

    private static func statusScreen(_ ctx: CGContext, _ r: CGRect, _ p: PhoneContext) {
        let s = p.snap
        let sent = s.crashPhase == "sent"
        ctx.setFillColor(Palette.card.cg()); ctx.fill(r)
        let tag = "DRILL · SIMULATED CRASH"
        let tw = UIText.width(tag, size: 10, weight: .heavy, tracking: 1) + 20
        ctx.fillRound(CGRect(x: r.width / 2 - tw / 2, y: 60, width: tw, height: 22), radius: 11, color: Palette.amber)
        UIText.line(tag, x: r.width / 2, y: 64, ctx: ctx, size: 10, weight: .heavy, color: Palette.ink, align: .center, tracking: 1)
        let c = CGPoint(x: r.width / 2, y: 210)
        ctx.setFillColor((sent ? Palette.rec : Palette.stroke).cg())
        ctx.fillEllipse(in: CGRect(x: c.x - 46, y: c.y - 46, width: 92, height: 92))
        if sent {
            UIText.symbol("checkmark", in: CGRect(x: c.x - 22, y: c.y - 20, width: 44, height: 40), ctx: ctx, color: Palette.white, weight: .bold)
        } else {
            for i in 0..<3 {
                let a = 0.35 + 0.65 * (0.5 + 0.5 * sin(p.time * 6 - Double(i)))
                ctx.setFillColor(Palette.white.cg(a))
                ctx.fillEllipse(in: CGRect(x: c.x - 26 + Double(i) * 20, y: c.y - 6, width: 12, height: 12))
            }
        }
        UIText.draw(sent ? "Alert sent to Sam" : "Sending to Sam…", in: CGRect(x: 20, y: 284, width: r.width - 40, height: 40), ctx: ctx, size: 24, weight: .bold, color: Palette.white, align: .center)
        let body = sent ? "Sam got a text at \(s.messageTime ?? "") with your location on Mass Ave." : "Your location is attached. This takes a moment."
        UIText.draw(body, in: CGRect(x: 28, y: 330, width: r.width - 56, height: 60), ctx: ctx, size: 15, weight: .regular, color: RGB(hex: 0xC9D0D8), align: .center)
        UIText.draw("Your ride is still recording. Hold Stop to finish.", in: CGRect(x: 28, y: 520, width: r.width - 56, height: 40), ctx: ctx, size: 12, weight: .regular, color: Palette.secondary, align: .center)
    }

    // MARK: Watch

    static let watchSize = CGSize(width: 190, height: 226)

    static func watch(_ ctx: CGContext, _ p: PhoneContext, tapShake: Double) {
        let s = p.snap
        let outer = CGRect(origin: .zero, size: watchSize)
        ctx.saveGState()
        ctx.translateBy(x: sin(tapShake * 60) * 5 * tapShake, y: 0)
        // Band.
        ctx.fillRound(CGRect(x: 35, y: -70, width: 120, height: 366), radius: 30, color: RGB(hex: 0x23272C))
        ctx.shadowed(blur: 24, offset: CGSize(width: 0, height: 10)) {
            ctx.fillRound(outer, radius: 56, color: RGB(hex: 0x2B2F34))
        }
        ctx.strokeRound(outer.insetBy(dx: 1, dy: 1), radius: 55, color: RGB(hex: 0x666B72), width: 2)
        ctx.fillRound(CGRect(x: outer.maxX - 2, y: 54, width: 10, height: 34), radius: 4, color: RGB(hex: 0x50555B))
        let face = outer.insetBy(dx: 12, dy: 12)
        ctx.addPath(CGPath(roundedRect: face, cornerWidth: 44, cornerHeight: 44, transform: nil))
        ctx.clip()
        var bg = RGB(0, 0, 0)
        let phase = s.crashPhase
        if !s.recording { bg = RGB(0, 0, 0) }
        else if phase == "countdown" || phase == "sending" || phase == "sent" { bg = Palette.crash }
        else if s.cue { bg = Palette.amber }
        ctx.setFillColor(bg.cg()); ctx.fill(face)
        let cx = face.midX
        if !s.recording {
            UIText.line("whoosh", x: cx, y: face.minY + 66, ctx: ctx, size: 26, weight: .heavy, color: Palette.lime, align: .center)
            UIText.line("Start on iPhone", x: cx, y: face.minY + 104, ctx: ctx, size: 13, weight: .semibold, color: Palette.white, align: .center)
        } else if phase == "countdown" {
            UIText.line("Crash detected", x: cx, y: face.minY + 22, ctx: ctx, size: 13, weight: .semibold, color: Palette.white, align: .center)
            UIText.line("\(Int(ceil(s.remaining ?? 0)))", x: cx, y: face.minY + 40, ctx: ctx, size: 60, weight: .bold, color: Palette.white, align: .center, mono: true)
            let b = CGRect(x: face.minX + 22, y: face.maxY - 58, width: face.width - 44, height: 38)
            ctx.fillRound(b, radius: 19, color: Palette.white)
            UIText.line("I'm OK", x: b.midX, y: b.minY + 9, ctx: ctx, size: 15, weight: .bold, color: Palette.ink, align: .center)
        } else if phase == "sending" || phase == "sent" {
            UIText.symbol(phase == "sent" ? "checkmark.circle.fill" : "ellipsis.circle.fill", in: CGRect(x: cx - 26, y: face.minY + 44, width: 52, height: 52), ctx: ctx, color: Palette.white)
            UIText.draw(phase == "sent" ? "Alert sent\nto Sam" : "Sending…", in: CGRect(x: face.minX + 10, y: face.minY + 108, width: face.width - 20, height: 50), ctx: ctx, size: 14, weight: .semibold, color: Palette.white, align: .center)
        } else if s.cue {
            UIText.line("TAP", x: cx, y: face.minY + 48, ctx: ctx, size: 40, weight: .black, color: Palette.ink, align: .center, tracking: 3)
            UIText.draw("Vehicle\n\(hintText(s.lastCueHint))", in: CGRect(x: face.minX + 10, y: face.minY + 104, width: face.width - 20, height: 50), ctx: ctx, size: 14, weight: .semibold, color: Palette.ink, align: .center)
        } else {
            ctx.setFillColor(Palette.rec.cg()); ctx.fillEllipse(in: CGRect(x: face.minX + 26, y: face.minY + 31, width: 9, height: 9))
            UIText.line(formatDuration(s.rideTime), x: face.minX + 42, y: face.minY + 18, ctx: ctx, size: 30, weight: .bold, color: Palette.lime, mono: true)
            UIText.line(String(format: "%.2f", s.riderDistance / 1609.344), x: face.minX + 26, y: face.minY + 64, ctx: ctx, size: 24, weight: .semibold, color: Palette.white, mono: true)
            UIText.line("MI", x: face.minX + 112, y: face.minY + 74, ctx: ctx, size: 12, weight: .semibold, color: Palette.secondary)
            UIText.line(s.riderSpeed > 0.2 ? String(format: "%.1f", s.riderSpeed * 2.2369362921) : "—", x: face.minX + 26, y: face.minY + 100, ctx: ctx, size: 24, weight: .semibold, color: Palette.white, mono: true)
            UIText.line("MPH", x: face.minX + 112, y: face.minY + 110, ctx: ctx, size: 12, weight: .semibold, color: Palette.secondary)
            UIText.symbol("eye.fill", in: CGRect(x: face.minX + 26, y: face.minY + 146, width: 16, height: 12), ctx: ctx, color: Palette.lime)
            UIText.line("Rear watch", x: face.minX + 48, y: face.minY + 143, ctx: ctx, size: 12, weight: .semibold, color: Palette.secondary)
        }
        ctx.restoreGState()
    }

    // MARK: Contact's phone

    static func contactPhone(_ ctx: CGContext, _ p: PhoneContext, sinceSent: Double?) {
        let s = p.snap
        phoneFrame(ctx, light: true) { r in
            ctx.setFillColor(Palette.white.cg()); ctx.fill(r)
            ctx.setFillColor(RGB(hex: 0xF6F6F8).cg()); ctx.fill(CGRect(x: 0, y: 0, width: r.width, height: 126))
            ctx.setFillColor(RGB(hex: 0xE3E3E8).cg()); ctx.fill(CGRect(x: 0, y: 126, width: r.width, height: 1))
            UIText.symbol("chevron.left", in: CGRect(x: 14, y: 70, width: 14, height: 22), ctx: ctx, color: RGB(hex: 0x0A7AFF))
            ctx.setFillColor(RGB(hex: 0x9EA4AE).cg()); ctx.fillEllipse(in: CGRect(x: r.width / 2 - 24, y: 56, width: 48, height: 48))
            UIText.line("W", x: r.width / 2, y: 67, ctx: ctx, size: 20, weight: .semibold, color: Palette.white, align: .center)
            UIText.line("+1 (855) 555-0199 ›", x: r.width / 2, y: 106, ctx: ctx, size: 11, weight: .regular, color: Palette.ink, align: .center)
            if let msg = s.message, let since = sinceSent {
                UIText.line("Text Message · Today \(s.messageTime ?? "")", x: r.width / 2, y: 140, ctx: ctx, size: 10, weight: .medium, color: RGB(hex: 0x8E8E93), align: .center)
                let bw = r.width - 58
                let attrsH = UIText.height(msg, width: bw - 24, size: 12, weight: .regular, lineHeight: 15.5)
                let bubble = CGRect(x: 12, y: 162, width: bw, height: attrsH + 18)
                let k = clamp01(since / 0.35)
                ctx.saveGState()
                ctx.setAlpha(k)
                ctx.translateBy(x: 0, y: (1 - k) * 14)
                ctx.fillRound(bubble, radius: 18, color: RGB(hex: 0xE9E9EB))
                drawMessage(ctx, msg, in: bubble.insetBy(dx: 12, dy: 9))
                ctx.restoreGState()
                // Lock-screen style banner as it arrives.
                let bk = window(since, 0, 3.2, fade: 0.35)
                if bk > 0 {
                    ctx.saveGState()
                    ctx.translateBy(x: 0, y: -(1 - bk) * 40)
                    ctx.setAlpha(bk)
                    let b = CGRect(x: 10, y: 52, width: r.width - 20, height: 74)
                    ctx.shadowed(blur: 18, offset: CGSize(width: 0, height: 6), alpha: 0.3) { ctx.fillRound(b, radius: 20, color: RGB(hex: 0xF4F4F6)) }
                    ctx.fillRound(CGRect(x: b.minX + 12, y: b.minY + 14, width: 30, height: 30), radius: 7, color: Palette.positive)
                    UIText.symbol("message.fill", in: CGRect(x: b.minX + 18, y: b.minY + 21, width: 18, height: 16), ctx: ctx, color: Palette.white)
                    UIText.line("+1 (855) 555-0199", x: b.minX + 52, y: b.minY + 10, ctx: ctx, size: 13, weight: .semibold, color: Palette.ink)
                    UIText.line("now", x: b.maxX - 12, y: b.minY + 11, ctx: ctx, size: 11, weight: .regular, color: RGB(hex: 0x8E8E93), align: .right)
                    UIText.draw("WHOOSH DEMO - NOT REAL: Alex is demonstrating Whoosh crash alerts…", in: CGRect(x: b.minX + 52, y: b.minY + 30, width: b.width - 64, height: 40), ctx: ctx, size: 12, weight: .regular, color: Palette.ink)
                    ctx.restoreGState()
                }
            } else {
                let text: String
                switch s.crashPhase {
                case "countdown": text = "Nothing yet. Alex can still tap I'm OK."
                case "sending": text = "Incoming…"
                case "cancelled": text = "Alex tapped I'm OK. No text was sent."
                default: text = "No messages."
                }
                UIText.draw(text, in: CGRect(x: 30, y: 290, width: r.width - 60, height: 50), ctx: ctx, size: 13, weight: .regular, color: RGB(hex: 0x8E8E93), align: .center)
            }
            // Input bar.
            ctx.strokeRound(CGRect(x: 52, y: r.height - 52, width: r.width - 68, height: 34), radius: 17, color: RGB(hex: 0xD1D1D6), width: 1)
            UIText.line("Text Message", x: 66, y: r.height - 44, ctx: ctx, size: 13, weight: .regular, color: RGB(hex: 0xB0B0B5))
            UIText.symbol("plus", in: CGRect(x: 16, y: r.height - 46, width: 22, height: 22), ctx: ctx, color: RGB(hex: 0x8E8E93))
            statusBar(ctx, width: r.width, clock: s.clock, dark: false)
        }
    }

    private static func drawMessage(_ ctx: CGContext, _ msg: String, in rect: CGRect) {
        let full = NSMutableAttributedString()
        let base = UIText.attributes(size: 12, weight: .regular, color: Palette.ink, lineHeight: 15.5)
        for (i, line) in msg.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if i > 0 { full.append(NSAttributedString(string: "\n", attributes: base)) }
            let l = String(line)
            if let range = l.range(of: "https://") {
                full.append(NSAttributedString(string: String(l[..<range.lowerBound]), attributes: base))
                var link = base
                link[.foregroundColor] = NSColor(srgbRed: 0.04, green: 0.42, blue: 0.9, alpha: 1)
                link[.underlineStyle] = NSUnderlineStyle.single.rawValue
                full.append(NSAttributedString(string: String(l[range.lowerBound...]), attributes: link))
            } else {
                var a = base
                if i == 0 { a[.font] = UIText.font(12, .semibold) }
                full.append(NSAttributedString(string: l, attributes: a))
            }
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        full.draw(with: rect, options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Near-miss log card

    static func nearMissLog(_ ctx: CGContext, _ s: SimSnapshot, width w: Double) -> Double {
        let rows = s.nearMisses
        let h = 78.0 + Double(max(1, rows.count)) * 70 + 34
        let r = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.shadowed(blur: 30, offset: CGSize(width: 0, height: 12), alpha: 0.45) { ctx.fillRound(r, radius: 22, color: Palette.ink, alpha: 0.94) }
        ctx.strokeRound(r.insetBy(dx: 0.5, dy: 0.5), radius: 22, color: Palette.stroke, width: 1)
        UIText.symbol("diamond.fill", in: CGRect(x: 22, y: 24, width: 18, height: 18), ctx: ctx, color: Palette.amber)
        UIText.line("NEAR-MISS LOG · THIS RIDE", x: 50, y: 24, ctx: ctx, size: 14, weight: .heavy, color: Palette.white, tracking: 1.2)
        var y = 64.0
        if rows.isEmpty {
            UIText.line("Nothing logged yet.", x: 22, y: y + 10, ctx: ctx, size: 16, weight: .regular, color: Palette.secondary)
        }
        for nm in rows {
            let row = CGRect(x: 16, y: y, width: w - 32, height: 60)
            ctx.fillRound(row, radius: 12, color: RGB(hex: 0x1A222C))
            ctx.fillRound(CGRect(x: row.minX, y: row.minY, width: 5, height: row.height), radius: 2.5, color: nm.source == "rider_reported" ? Palette.lime : Palette.amber)
            UIText.line(formatDuration(nm.t - s.rideStartsAt), x: row.minX + 18, y: row.minY + 18, ctx: ctx, size: 18, weight: .bold, color: Palette.white, mono: true)
            let what = nm.source == "rider_reported" ? "Close call · marked by rider" : "Detected \(nm.kind ?? "vehicle") · \(hintText(nm.hint)) · score \(String(format: "%.2f", nm.score ?? 0))"
            UIText.line(what, x: row.minX + 84, y: row.minY + 9, ctx: ctx, size: 15, weight: .semibold, color: Palette.white)
            UIText.line(String(format: "%.5f, %.5f · Mass Ave, Boston", nm.lat, nm.lon), x: row.minX + 84, y: row.minY + 33, ctx: ctx, size: 12.5, weight: .regular, color: Palette.secondary, mono: true)
            y += 70
        }
        UIText.line("Saved on the phone. No video or frames are kept.", x: 22, y: h - 30, ctx: ctx, size: 12, weight: .regular, color: Palette.secondary)
        return h
    }
}

func hintText(_ hint: String?) -> String {
    guard let hint else { return "behind you" }
    return hint == "center" ? "directly behind" : "on your \(hint)"
}

func formatDuration(_ seconds: Double) -> String {
    let total = Int(max(0, seconds).rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}
