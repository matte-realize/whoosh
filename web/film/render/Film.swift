import AppKit
import CoreGraphics
import Foundation

/// The film's script: which ride is on screen, where the camera is, and what overlays show,
/// all as functions of film time in seconds.

enum Film {
    static let width = 1920.0
    static let height = 1080.0
    static let fps = 30
    static let duration = 66.5

    static let act2Start = 14.5          // the ride with Whoosh begins (phone mounting)
    static let lapseStart = 50.5         // countdown time-lapse
    static let lapseEnd = 53.0
    static let lapseRate = 3.6
    static let endCard = 60.0

    /// Ride-simulation time for a film time (acts 2 to 5).
    static func rideTime(_ t: Double) -> Double {
        let l = t - act2Start
        if t < lapseStart { return max(0, l) }
        let lapseL = lapseStart - act2Start
        if t < lapseEnd { return lapseL + (t - lapseStart) * lapseRate }
        return lapseL + (lapseEnd - lapseStart) * lapseRate + (t - lapseEnd)
    }

    struct Shot {
        let from: Double
        let to: Double
        let pov: Bool
        let camera: (Double, Double) -> (Vec3, Vec3, Double)  // (u 0...1, t) -> pos, target, fov
    }

    static func orbit(_ target: Vec3, az: Double, el: Double, r: Double) -> Vec3 {
        target + Vec3(r * sin(az) * cos(el), r * sin(el), r * cos(az) * cos(el))
    }

    static let shots: [Shot] = [
        // Act 1: the problem.
        Shot(from: 0, to: 5, pov: false) { u, _ in
            let k = smooth(u)
            return (Vec3.lerp(Vec3(-7.5, 10.5, -31), Vec3(-4.6, 5.6, -17.5), k), Vec3.lerp(Vec3(0.5, 0.6, 10), Vec3(0.6, 0.9, 4), k), 50)
        },
        Shot(from: 5, to: 9.8, pov: false) { u, _ in
            (Vec3.lerp(Vec3(2.95, 1.25, 9.6), Vec3(2.65, 1.2, 8.1), u), Vec3.lerp(Vec3(-0.4, 1.05, -20), Vec3(-0.2, 1.0, -12), u), 46)
        },
        Shot(from: 9.8, to: act2Start, pov: false) { u, t in
            let shake = window(t, 12.95, 13.7, fade: 0.15)
            let j = Vec3(sin(t * 61) * 0.025, sin(t * 47) * 0.02, 0) * shake
            return (Vec3.lerp(Vec3(4.4, 1.15, 5.6), Vec3(4.1, 1.1, 4.2), u) + j, Vec3.lerp(Vec3(0.3, 1.0, -3), Vec3(0.4, 1.0, -1), u), 48)
        },
        // Act 2: the attachment.
        Shot(from: act2Start, to: 19.5, pov: false) { u, _ in
            let tgt = Vec3(riderX, 0.84, -0.3)
            return (orbit(tgt, az: lerp(2.25, 2.72, smooth(u)), el: lerp(0.2, 0.14, u), r: lerp(1.5, 1.12, smooth(u))), tgt, 40)
        },
        Shot(from: 19.5, to: 24.5, pov: false) { u, _ in
            (Vec3.lerp(Vec3(3.5, 1.85, -4.9), Vec3(3.0, 1.62, -3.9), u), Vec3(0.55, 0.95, 0.5), 46)
        },
        // Act 3: ride recording.
        Shot(from: 24.5, to: 29.5, pov: false) { u, _ in
            (Vec3.lerp(Vec3(-2.3, 3.4, -9.2), Vec3(-1.9, 3.0, -7.6), u), Vec3(0.8, 0.8, 6), 50)
        },
        // Fly into the phone's camera.
        Shot(from: 29.5, to: 31.0, pov: false) { u, _ in
            let k = smooth(u)
            let pos = Vec3.lerp(Vec3(-1.9, 3.0, -7.6), Vec3(1.05, 0.92, -0.78), k)
            let tgt = Vec3.lerp(Vec3(0.8, 0.8, 6), Vec3(riderX, 0.86, -0.3), k)
            return (pos, tgt, lerp(50, 34, k))
        },
        // Act 4: Whoosh Vision through the rear camera.
        Shot(from: 31.0, to: 36.5, pov: true) { _, t in
            (Vec3(riderX, 0.86 + sin(t * 23) * 0.003, -0.34), Vec3(riderX - 0.55, 0.6, -30), 64)
        },
        Shot(from: 36.5, to: 41.5, pov: false) { u, _ in
            (Vec3.lerp(Vec3(3.7, 1.9, 7.6), Vec3(3.3, 1.7, 6.0), u), Vec3.lerp(Vec3(-0.6, 0.9, -9), Vec3(-0.2, 0.8, -12), u), 50)
        },
        Shot(from: 41.5, to: 44.0, pov: false) { u, _ in
            (Vec3.lerp(Vec3(-6.2, 13.5, -27), Vec3(-5.2, 12, -22.5), u), Vec3(0.5, 0, -6), 50)
        },
        // Act 5: crash response.
        Shot(from: 44.0, to: lapseEnd, pov: false) { u, _ in
            let tgt = Vec3(1.45, 0.45, 0.3)
            return (orbit(tgt, az: lerp(0.85, 1.55, u), el: lerp(0.44, 0.34, u), r: lerp(7.6, 5.4, smooth(u))), tgt, 46)
        },
        Shot(from: lapseEnd, to: duration, pov: false) { u, _ in
            let k = smooth(min(1, u * 1.4))
            let tgt = Vec3(1.3, 0.3, 0.2)
            return (orbit(tgt, az: lerp(1.55, 2.0, k), el: lerp(0.4, 0.8, k), r: lerp(6, 15, k)), tgt, 46)
        },
    ]

    static func shot(at t: Double) -> (Shot, Double) {
        let s = shots.first { t >= $0.from && t < $0.to } ?? shots.last!
        return (s, clamp01((t - s.from) / (s.to - s.from)))
    }

    struct Caption {
        let from: Double
        let to: Double
        let text: String
        var alert = false
    }

    static let captions: [Caption] = [
        Caption(from: 5.3, to: 9.6, text: "Most close passes come from behind, where a rider can't see them."),
        Caption(from: 10.4, to: 14.2, text: "No warning. Just a whoosh."),
        Caption(from: 15.0, to: 17.4, text: "Meet Whoosh. Your phone becomes a rear-view sensor."),
        Caption(from: 17.6, to: 19.4, text: "Clip it to the seat post, back camera facing traffic."),
        Caption(from: 19.8, to: 23.3, text: "Rear detection and crash alerts on. Tap Start Ride."),
        Caption(from: 23.8, to: 29.3, text: "Whoosh records the ride on the phone and the Watch: time, distance, speed and route."),
        Caption(from: 31.3, to: 33.7, text: "Whoosh Vision watches the road behind you, right on the phone."),
        Caption(from: 33.9, to: 35.8, text: "It tracks vehicles closing in from behind and ignores oncoming traffic."),
        Caption(from: 35.95, to: 38.4, text: "Heads-up: car on your left. One cue, on the phone and on your wrist.", alert: true),
        Caption(from: 38.7, to: 43.9, text: "Every close call goes into the near-miss log, with the time and the place."),
        Caption(from: 44.7, to: 47.6, text: "If Whoosh detects a probable crash, a countdown starts."),
        Caption(from: 47.8, to: 50.4, text: "Tap I'm OK to cancel. If you can't, Whoosh alerts your emergency contact.", alert: true),
        Caption(from: 53.4, to: 59.7, text: "Sam gets a text with the rider's location and a map link."),
    ]

    static let chapters: [(Double, Double, String)] = [
        (0.0, act2Start, "THE PROBLEM"),
        (act2Start, 23.6, "THE ATTACHMENT"),
        (23.6, 29.5, "1 · RIDE RECORDING"),
        (31.0, 44.0, "2 · NEAR-MISS LOGGING"),
        (44.0, endCard, "3 · CRASH RESPONSE"),
    ]
}

// MARK: - Frame composition

final class FilmRenderer {
    let engine: Engine
    let route: RouteMap
    private var act1Time = 0.0
    private var rideSimTime = 0.0
    private var cueStartedAt: Double?
    private let grain: [CGImage]
    private let ctx: CGContext

    init(engine: Engine) {
        self.engine = engine
        route = RouteMap(engine.route())
        engine.create("act1", scenario: "act1")
        engine.create("ride", scenario: "ride")
        ctx = CGContext(data: nil, width: Int(Film.width), height: Int(Film.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.translateBy(x: 0, y: Film.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        grain = (0..<4).map { FilmRenderer.noise(seed: $0) }
    }

    private static func noise(seed: Int) -> CGImage {
        let w = 480, h = 270
        var bytes = [UInt8](repeating: 0, count: w * h)
        var x = UInt64(seed + 1) &* 0x9E37_79B9_7F4A_7C15
        for i in 0..<bytes.count {
            x ^= x << 13; x ^= x >> 7; x ^= x << 17
            bytes[i] = UInt8(truncatingIfNeeded: x)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Advances the simulations to film time `t` and returns the snapshot on screen.
    private func advance(to t: Double) -> (SimSnapshot, Bool) {
        if t < Film.act2Start {
            let target = t
            engine.advance("act1", by: target - act1Time)
            act1Time = target
            return (engine.snapshot("act1"), true)
        }
        let target = Film.rideTime(t)
        engine.advance("ride", by: target - rideSimTime)
        rideSimTime = target
        return (engine.snapshot("ride"), false)
    }

    func render(_ t: Double, draw: Bool) -> CGImage? {
        let (snap, act1) = advance(to: t)
        if snap.cue { if cueStartedAt == nil { cueStartedAt = t } } else { cueStartedAt = nil }
        guard draw else { return nil }

        let (shot, u) = Film.shot(at: t)
        let (pos, target, fov) = shot.camera(u, t)
        let cam = Camera(pos: pos, target: target, fov: fov, width: Film.width, height: Film.height)

        var opt = SceneOptions()
        opt.time = t
        if !act1 {
            let m = t - Film.act2Start
            opt.clamp = ramp(m, 0.5, 1.3)
            opt.phone = ramp(m, 1.5, 2.9)
            opt.lensGlow = m > 3.2 ? ramp(m, 3.2, 3.9) * (0.75 + 0.25 * sin(t * 4)) : 0
            opt.screenOn = snap.recording
            opt.showCone = (t >= 24.5 && t < 29.5 ? ramp(t, 25.2, 26.4) : 0) + (t >= 36.5 && t < 44 ? 1 : 0)
            opt.coneAlert = snap.cue
            opt.showLabels = t >= 36.5 && t < 44
            opt.crashRing = true
        }
        let world = WorldRenderer(ctx: ctx, cam: cam, width: Film.width, height: Film.height, snap: snap, options: opt)
        world.draw()

        if shot.pov { drawVisionHUD(world, snap, t) }
        drawOverlays(snap, t, act1: act1)
        drawText(t)
        post(t)
        return ctx.makeImage()
    }

    // MARK: Vision HUD

    private func drawVisionHUD(_ world: WorldRenderer, _ s: SimSnapshot, _ t: Double) {
        let W = Film.width, H = Film.height
        let lime = Palette.lime, amber = RGB(hex: 0xFFB020), red = RGB(hex: 0xFF4D44), gray = RGB(hex: 0xC3CAD2)
        // Camera-feed look: slightly darker and cooler.
        ctx.setFillColor(RGB(hex: 0x0B1620).cg(0.16)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let topG = CGGradient(colorsSpace: space, colors: [RGB(0, 0, 0).cg(0.55), RGB(0, 0, 0).cg(0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(topG, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 170), options: [])
        ctx.drawLinearGradient(topG, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: H - 150), options: [])

        // Detection zone, as the app would draw it over the feed.
        let zone = [Vec3(Road.centerLine + 0.3, 0.01, -3), Vec3(Road.bikeLaneRight + 0.6, 0.01, -3), Vec3(Road.bikeLaneRight + 0.6, 0.01, -60), Vec3(Road.centerLine + 0.3, 0.01, -60)]
        if let zp = world.cam.projectPolygon(zone) {
            ctx.addPath(path(zp)); ctx.setFillColor((s.cue ? red : lime).cg(0.08)); ctx.fillPath()
            ctx.addPath(path(zp)); ctx.setStrokeColor((s.cue ? red : lime).cg(0.35)); ctx.setLineWidth(2); ctx.setLineDash(phase: 0, lengths: [14, 10]); ctx.strokePath(); ctx.setLineDash(phase: 0, lengths: [])
        }

        for v in s.vehicles {
            guard var box = world.screenBox(v) else { continue }
            box = box.intersection(CGRect(x: -40, y: -40, width: W + 80, height: H + 80))
            if box.isNull || box.width < 8 || box.height < 6 { continue }
            let front = v.z + v.length / 2
            let kind = v.kind.uppercased()
            let score = min(0.97, 0.52 + 0.42 * clamp01(box.height / 420) + 0.012 * sin(t * 3 + Double(v.id)))
            if v.direction == -1 {
                dashedBox(box, gray, 2)
                tag("\(kind) · ONCOMING · IGNORED", over: box, color: gray, filled: false)
                continue
            }
            if v.state == "passed" || front > 0 { continue }
            let closing = v.speed - s.riderSpeed
            let ttc = closing > 0.5 ? -front / closing : nil
            switch v.state {
            case "cued":
                ctx.setStrokeColor(red.cg()); ctx.setLineWidth(5); ctx.stroke(box)
                corners(box, red, 9)
                tag("HEADS-UP · \(kind) ON YOUR LEFT", over: box, color: red, filled: true)
                if let ttc { tag(String(format: "~%.1f s · near miss logged ◆", ttc), under: box, color: red) }
            case "tracking":
                corners(box, amber, 5)
                tag(String(format: "%@ %.2f · APPROACHING", kind, score), over: box, color: amber, filled: false)
                if let ttc {
                    let k = clamp01(1 - ttc / 7)
                    let bar = CGRect(x: box.minX, y: box.maxY + 10, width: max(140, box.width), height: 8)
                    ctx.fillRound(bar, radius: 4, color: RGB(0, 0, 0), alpha: 0.5)
                    ctx.fillRound(CGRect(x: bar.minX, y: bar.minY, width: bar.width * k, height: bar.height), radius: 4, color: amber)
                    UIText.line(String(format: "time to reach ~%.1f s", ttc), x: bar.minX, y: bar.maxY + 6, ctx: ctx, size: 18, weight: .semibold, color: amber)
                }
            default:
                ctx.setStrokeColor(RGB(1, 1, 1).cg(0.75)); ctx.setLineWidth(2); ctx.stroke(box)
                tag(String(format: "%@ %.2f", kind, score), over: box, color: RGB(1, 1, 1), filled: false)
            }
        }

        // Frame furniture.
        let m = 46.0
        for (x, y, dx, dy) in [(m, m, 1.0, 1.0), (W - m, m, -1.0, 1.0), (m, H - m, 1.0, -1.0), (W - m, H - m, -1.0, -1.0)] {
            ctx.setStrokeColor(lime.cg(0.9)); ctx.setLineWidth(4); ctx.setLineCap(.square)
            ctx.move(to: CGPoint(x: x, y: y + dy * 54)); ctx.addLine(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + dx * 54, y: y)); ctx.strokePath()
        }
        let blink = sin(t * 5) > 0
        ctx.setFillColor((blink ? red : red.scaled(0.5)).cg()); ctx.fillEllipse(in: CGRect(x: 76, y: 84, width: 16, height: 16))
        UIText.line("WHOOSH VISION", x: 102, y: 74, ctx: ctx, size: 30, weight: .heavy, color: lime, tracking: 2)
        UIText.line("Rear camera · runs on the phone · no video saved", x: 78, y: 114, ctx: ctx, size: 19, weight: .medium, color: RGB(1, 1, 1), alpha: 0.85)
        UIText.line("ON-DEVICE MODEL · YOLO26n", x: W - 78, y: 80, ctx: ctx, size: 19, weight: .bold, color: RGB(1, 1, 1), alpha: 0.85, align: .right, tracking: 1.5)
        UIText.line("EXPERIMENTAL", x: W - 78, y: 108, ctx: ctx, size: 16, weight: .bold, color: amber, align: .right, tracking: 2)
        UIText.line("←  RIDER'S RIGHT", x: 80, y: H - 96, ctx: ctx, size: 19, weight: .bold, color: RGB(1, 1, 1), alpha: 0.75, tracking: 1.5)
        UIText.line("RIDER'S LEFT  →", x: W - 80, y: H - 96, ctx: ctx, size: 19, weight: .bold, color: RGB(1, 1, 1), alpha: 0.75, align: .right, tracking: 1.5)
        if s.cue {
            ctx.setStrokeColor(red.cg(0.85)); ctx.setLineWidth(16); ctx.stroke(CGRect(x: 8, y: 8, width: W - 16, height: H - 16))
        }
    }

    private func dashedBox(_ r: CGRect, _ c: RGB, _ w: Double) {
        ctx.setStrokeColor(c.cg(0.7)); ctx.setLineWidth(w); ctx.setLineDash(phase: 0, lengths: [10, 7]); ctx.stroke(r); ctx.setLineDash(phase: 0, lengths: [])
    }

    private func corners(_ r: CGRect, _ c: RGB, _ w: Double) {
        let l = min(40, min(r.width, r.height) * 0.3)
        ctx.setStrokeColor(c.cg()); ctx.setLineWidth(w); ctx.setLineCap(.square)
        for (x, y, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            ctx.move(to: CGPoint(x: x, y: y + dy * l)); ctx.addLine(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + dx * l, y: y)); ctx.strokePath()
        }
    }

    private func tag(_ text: String, over box: CGRect, color: RGB, filled: Bool) {
        let size = 19.0
        let w = UIText.width(text, size: size, weight: .bold, tracking: 1) + 22
        let r = CGRect(x: max(10, min(Film.width - w - 10, box.minX)), y: max(10, box.minY - 38), width: w, height: 32)
        ctx.fillRound(r, radius: 6, color: filled ? color : RGB(hex: 0x0B0F14), alpha: filled ? 0.95 : 0.78)
        if !filled { ctx.strokeRound(r, radius: 6, color: color, width: 1.5) }
        UIText.line(text, x: r.minX + 11, y: r.minY + 4, ctx: ctx, size: size, weight: .bold, color: filled ? Palette.ink : color, tracking: 1)
    }

    private func tag(_ text: String, under box: CGRect, color: RGB) {
        UIText.line(text, x: box.minX, y: box.maxY + 10, ctx: ctx, size: 20, weight: .bold, color: color)
    }

    // MARK: Device overlays

    private func place(_ at: CGPoint, scale: Double, alpha: Double, slide: Double = 0, _ body: () -> Void) {
        guard alpha > 0.001 else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.translateBy(x: at.x + slide * (1 - alpha) * 60, y: at.y)
        ctx.scaleBy(x: scale, y: scale)
        body()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func drawOverlays(_ s: SimSnapshot, _ t: Double, act1: Bool) {
        if act1 { return }
        var p = PhoneContext(snap: s, route: route, time: t)
        let tapAt = 23.05
        if t >= tapAt && t < tapAt + 0.5 {
            p.tap = (CGPoint(x: Devices.startButton.midX, y: Devices.startButton.midY), (t - tapAt) / 0.5)
        }
        p.pressStart = t >= tapAt && t < tapAt + 0.45 && !s.recording
        let shake = cueStartedAt.map { clamp01(1 - (t - $0) / 0.7) } ?? 0

        // Rider's phone.
        let phoneLayout: (CGPoint, Double, Double)? = {
            if t >= 19.5 && t < 24.5 { return (CGPoint(x: 1405, y: 150), 1.22, window(t, 19.6, 24.5, fade: 0.35)) }
            if t >= 24.5 && t < 30.0 { return (CGPoint(x: 1540, y: 210), 1.0, window(t, 24.5, 29.9, fade: 0.4)) }
            if t >= 34.2 && t < 36.5 { return (CGPoint(x: 1600, y: 380), 0.8, window(t, 34.2, 36.6, fade: 0.3)) }
            if t >= 36.5 && t < 44.0 { return (CGPoint(x: 1560, y: 190), 0.96, window(t, 36.4, 44.2, fade: 0.3)) }
            if t >= 44.0 && t < 53.0 { return (CGPoint(x: 1500, y: 120), 1.12, window(t, 43.9, 53.4, fade: 0.3)) }
            if t >= 53.0 && t < Film.endCard { return (CGPoint(x: 1090, y: 190), 0.98, window(t, 52.9, Film.endCard, fade: 0.4)) }
            return nil
        }()
        if let (pt, sc, a) = phoneLayout {
            place(pt, scale: sc, alpha: a, slide: 1) { Devices.riderPhone(ctx, p) }
        }

        // Watch.
        let watchLayout: (CGPoint, Double, Double)? = {
            if t >= 23.7 && t < 30.0 { return (CGPoint(x: t < 24.5 ? 1150 : 1300, y: t < 24.5 ? 610 : 600), 1.0, window(t, 23.7, 29.9, fade: 0.35)) }
            if t >= 34.2 && t < 36.5 { return (CGPoint(x: 1410, y: 720), 0.85, window(t, 34.2, 36.6, fade: 0.3)) }
            if t >= 36.5 && t < 44.0 { return (CGPoint(x: 1330, y: 600), 0.95, window(t, 36.4, 44.2, fade: 0.3)) }
            if t >= 44.0 && t < 53.0 { return (CGPoint(x: 1265, y: 600), 1.0, window(t, 44.3, 53.4, fade: 0.3)) }
            return nil
        }()
        if let (pt, sc, a) = watchLayout {
            place(pt, scale: sc, alpha: a, slide: 1) { Devices.watch(ctx, p, tapShake: shake) }
        }

        // Near-miss log.
        if t >= 37.6 && t < 44.0 {
            place(CGPoint(x: 70, y: 590), scale: 1.0, alpha: window(t, 37.6, 44.2, fade: 0.35), slide: -1) {
                _ = Devices.nearMissLog(ctx, s, width: 680)
            }
        }

        // Contact's phone.
        if t >= 53.0 && t < Film.endCard {
            let since = s.crashSentAt.map { s.t - $0 }
            place(CGPoint(x: 1500, y: 120), scale: 1.12, alpha: window(t, 53.0, Film.endCard, fade: 0.4), slide: 1) {
                Devices.contactPhone(ctx, p, sinceSent: since)
            }
            let a = window(t, 53.2, Film.endCard, fade: 0.4)
            if a > 0 {
                UIText.line("Alex's phone", x: 1090 + 147, y: 805, ctx: ctx, size: 20, weight: .semibold, color: RGB(1, 1, 1), alpha: a, align: .center)
                UIText.line("Sam's phone · emergency contact", x: 1500 + 168, y: 830, ctx: ctx, size: 20, weight: .semibold, color: RGB(1, 1, 1), alpha: a, align: .center)
            }
        }

        // Countdown time-lapse badge.
        let lapse = window(t, Film.lapseStart, Film.lapseEnd, fade: 0.2)
        if lapse > 0 {
            let r = CGRect(x: 60, y: 120, width: 360, height: 50)
            ctx.fillRound(r, radius: 25, color: Palette.ink, alpha: 0.8 * lapse)
            UIText.symbol("forward.fill", in: CGRect(x: 80, y: 134, width: 28, height: 22), ctx: ctx, color: Palette.lime, alpha: lapse)
            UIText.line("15-second countdown, sped up", x: 120, y: 132, ctx: ctx, size: 20, weight: .semibold, color: RGB(1, 1, 1), alpha: lapse)
        }
    }

    // MARK: Titles, captions, chapters

    private func drawText(_ t: Double) {
        let W = Film.width, H = Film.height
        // Opening title.
        let title = window(t, 0.4, 4.6, fade: 0.6)
        if title > 0 {
            ctx.setFillColor(Palette.ink.cg(0.42 * title)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            wordmark(center: CGPoint(x: W / 2, y: 420), size: 190, alpha: title)
            UIText.line("A rear-view sensor for city cyclists", x: W / 2, y: 560, ctx: ctx, size: 44, weight: .medium, color: RGB(1, 1, 1), alpha: title, align: .center)
        }

        // Chapter tag.
        for (from, to, label) in Film.chapters where t >= from && t < to {
            let a = window(t, from + 0.2, to, fade: 0.35) * (1 - window(t, 0.4, 4.6, fade: 0.6))
            guard a > 0 else { continue }
            let w = UIText.width(label, size: 20, weight: .heavy, tracking: 2.5) + 54
            let r = CGRect(x: 56, y: 50, width: w, height: 46)
            ctx.fillRound(r, radius: 23, color: Palette.ink, alpha: 0.72 * a)
            ctx.setFillColor(Palette.lime.cg(a)); ctx.fillEllipse(in: CGRect(x: 76, y: 66, width: 14, height: 14))
            UIText.line(label, x: 102, y: 60, ctx: ctx, size: 20, weight: .heavy, color: RGB(1, 1, 1), alpha: a, tracking: 2.5)
        }

        // Captions.
        for c in Film.captions where t >= c.from && t <= c.to {
            let a = window(t, c.from, c.to, fade: 0.28)
            let size = 40.0
            let maxW = 1240.0
            let textW = min(maxW, UIText.width(c.text, size: size, weight: .semibold))
            let textH = UIText.height(c.text, width: textW + 4, size: size, weight: .semibold)
            let r = CGRect(x: W / 2 - textW / 2 - 40, y: H - 108 - textH, width: textW + 80, height: textH + 34)
            let rise = (1 - a) * 12
            ctx.saveGState()
            ctx.translateBy(x: 0, y: rise)
            ctx.fillRound(r, radius: 18, color: c.alert ? RGB(hex: 0x3A0D10) : Palette.ink, alpha: 0.76 * a)
            ctx.fillRound(CGRect(x: r.minX, y: r.minY, width: 7, height: r.height), radius: 3.5, color: c.alert ? RGB(hex: 0xFF4D44) : Palette.lime, alpha: a)
            UIText.draw(c.text, in: CGRect(x: W / 2 - textW / 2 - 2, y: r.minY + 16, width: textW + 4, height: textH + 4), ctx: ctx, size: size, weight: .semibold, color: RGB(1, 1, 1), alpha: a, align: .center)
            ctx.restoreGState()
        }

        // End card.
        let end = ramp(t, Film.endCard - 0.2, Film.endCard + 0.8)
        if end > 0 {
            ctx.setFillColor(Palette.ink.cg(end)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let a = ramp(t, Film.endCard + 0.5, Film.endCard + 1.3) * (1 - ramp(t, Film.duration - 0.7, Film.duration))
            wordmark(center: CGPoint(x: W / 2, y: 360), size: 170, alpha: a)
            UIText.line("A heads-up for what's behind you.", x: W / 2, y: 500, ctx: ctx, size: 50, weight: .semibold, color: RGB(1, 1, 1), alpha: a, align: .center)
            let b = ramp(t, Film.endCard + 1.2, Film.endCard + 2.0) * (1 - ramp(t, Film.duration - 0.7, Film.duration))
            UIText.line("Ride recording   ·   Near-miss logging   ·   Crash response", x: W / 2, y: 610, ctx: ctx, size: 32, weight: .semibold, color: Palette.lime, alpha: b, align: .center)
            UIText.line("Simulated footage. Rear detection and crash detection are experimental. Whoosh is not an emergency service.", x: W / 2, y: 930, ctx: ctx, size: 21, weight: .regular, color: Palette.secondary, alpha: b, align: .center)
        }
    }

    private func wordmark(center: CGPoint, size: Double, alpha: Double) {
        let w = UIText.width("whoosh", size: size, weight: .heavy, tracking: -size * 0.02)
        UIText.line("whoosh", x: center.x, y: center.y - size * 0.62, ctx: ctx, size: size, weight: .heavy, color: RGB(1, 1, 1), alpha: alpha, align: .center, tracking: -size * 0.02)
        ctx.setFillColor(Palette.lime.cg(alpha))
        ctx.fill(CGRect(x: center.x + w / 2 - size * 0.42, y: center.y + size * 0.52, width: size * 0.4, height: size * 0.075))
    }

    // MARK: Post

    private func post(_ t: Double) {
        let W = Film.width, H = Film.height
        // Cuts: short dips to black, a longer one between acts, a flash into the camera view.
        var dip = 0.0
        for c in [5.0, 9.8, 19.5, 24.5, 36.5, 41.5, 44.0] { dip = max(dip, 1 - abs(t - c) / 0.16) }
        dip = max(dip, 1 - abs(t - Film.act2Start) / 0.55)
        dip = max(dip, 1 - t / 0.6)
        if dip > 0 { ctx.setFillColor(RGB(0, 0, 0).cg(clamp01(dip))); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
        let flash = max(0, 1 - abs(t - 31.0) / 0.22)
        if flash > 0 { ctx.setFillColor(RGB(1, 1, 1).cg(flash * 0.9)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
        let snapFlash = max(0, 1 - abs(t - (Film.act2Start + 2.95)) / 0.12) * 0.35
        if snapFlash > 0 { ctx.setFillColor(RGB(1, 1, 1).cg(snapFlash)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }

        // Vignette.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: space, colors: [RGB(0, 0, 0).cg(0), RGB(0, 0, 0).cg(0.38)] as CFArray, locations: [0.55, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: 0, endCenter: CGPoint(x: W / 2, y: H / 2), endRadius: hypot(W, H) / 2, options: [.drawsAfterEndLocation])

        // Film grain.
        let frame = Int(t * Double(Film.fps))
        ctx.saveGState()
        ctx.setBlendMode(.overlay)
        ctx.setAlpha(0.07)
        let img = grain[frame % grain.count]
        let ox = Double((frame * 37) % 97), oy = Double((frame * 53) % 61)
        ctx.draw(img, in: CGRect(x: -ox, y: -oy, width: W + 200, height: H + 120))
        ctx.restoreGState()

        // Small honesty badge.
        if t < Film.endCard && !Film.shot(at: t).0.pov && window(t, 0.4, 4.6, fade: 0.6) == 0 {
            let r = CGRect(x: W - 236, y: 54, width: 180, height: 36)
            ctx.fillRound(r, radius: 18, color: Palette.ink, alpha: 0.5)
            UIText.line("SIMULATION", x: r.midX, y: r.minY + 8, ctx: ctx, size: 15, weight: .heavy, color: RGB(1, 1, 1), alpha: 0.8, align: .center, tracking: 2.5)
        }
    }
}
