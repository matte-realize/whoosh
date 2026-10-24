import CoreGraphics
import Foundation

/// The 3D street, traffic, cyclist and phone, drawn with CoreGraphics (painter's algorithm).
/// Coordinates match engine.ts: x to the rider's right, y up, z forward, rider at z = 0.

let riderX = 0.9

enum Road {
    static let bikeLaneLeft = 0.0
    static let bikeLaneRight = 1.8
    static let centerLine = -3.6
    static let roadLeft = -7.2
    static let curbHeight = 0.14
    static let sidewalkRightEdge = 5.2
    static let sidewalkLeftEdge = -10.6
    static let buildingRight = 7.0
    static let buildingLeft = -12.6
    static let blockLength = 120.0
    static let crossStreetWidth = 15.0
    static let crossStreetOffset = 52.0

    /// World z (distance along the street) of the intersection nearest `zw`.
    static func intersectionCenter(near zw: Double) -> Double {
        ((zw - crossStreetOffset) / blockLength).rounded() * blockLength + crossStreetOffset
    }

    static func inIntersection(_ zw: Double, margin: Double = 0) -> Bool {
        abs(zw - intersectionCenter(near: zw)) < crossStreetWidth / 2 + margin
    }
}

struct SceneOptions {
    var showCone = 0.0          // detection zone on the road behind the rider, 0...1
    var coneAlert = false
    var showLabels = false      // floating tags over tracked vehicles and near-miss pins
    var clamp = 0.0             // phone mount: clamp appears, 0...1
    var phone = 0.0             // phone slides into the mount, 0...1
    var lensGlow = 0.0
    var drawRider = true
    var screenOn = false
    var crashRing = false
    var time = 0.0              // film seconds, for pulses
}

final class WorldRenderer {
    let ctx: CGContext
    let cam: Camera
    let width: Double
    let height: Double
    let snap: SimSnapshot
    let opt: SceneOptions
    private var items: [(depth: Double, draw: () -> Void)] = []

    let sun = Vec3(-0.45, 0.82, -0.36).normalized
    let fogColor = RGB(hex: 0xCFDCE6)
    let skyTop = RGB(hex: 0x4F86C2)
    let skyHorizon = RGB(hex: 0xD7E4EC)

    init(ctx: CGContext, cam: Camera, width: Double, height: Double, snap: SimSnapshot, options: SceneOptions) {
        self.ctx = ctx
        self.cam = cam
        self.width = width
        self.height = height
        self.snap = snap
        opt = options
    }

    // MARK: - Helpers

    func fog(_ c: RGB, _ depth: Double) -> RGB {
        let f = 1 - exp(-max(0, depth) / 190)
        return c.mix(fogColor, f * 0.9)
    }

    func shade(_ c: RGB, normal n: Vec3) -> RGB {
        let d = max(0, n.dot(sun))
        let sky = max(0, n.y) * 0.12
        return c.scaled(0.52 + 0.5 * d + sky)
    }

    func fillPoly(_ pts: [Vec3], _ color: RGB, alpha: Double = 1, seam: Bool = true) {
        guard let p = cam.projectPolygon(pts) else { return }
        let path = path(p)
        ctx.addPath(path)
        ctx.setFillColor(color.cg(alpha))
        ctx.fillPath()
        if seam && alpha >= 1 {
            ctx.addPath(path)
            ctx.setStrokeColor(color.cg(1))
            ctx.setLineWidth(0.8)
            ctx.strokePath()
        }
    }

    func rect(_ x0: Double, _ x1: Double, _ z0: Double, _ z1: Double, y: Double = 0) -> [Vec3] {
        [Vec3(x0, y, z0), Vec3(x1, y, z0), Vec3(x1, y, z1), Vec3(x0, y, z1)]
    }

    /// World z of a rider-frame z.
    func worldZ(_ z: Double) -> Double { z + snap.riderDistance }
    func frameZ(_ zw: Double) -> Double { zw - snap.riderDistance }

    // MARK: - Draw

    func draw() {
        drawSky()
        drawGround()
        addBuildings()
        addTrees()
        addLamps()
        for v in snap.vehicles { addVehicle(v) }
        addNearMissPins()
        if opt.drawRider { addBikeAndRider() }
        items.sort { $0.depth > $1.depth }
        for item in items { item.draw() }
        if opt.showLabels { drawLabels() }
    }

    // MARK: Sky

    private func drawSky() {
        let flat = Vec3(cam.forward.x, 0, cam.forward.z).normalized
        let c = Vec3(flat.dot(cam.right), flat.dot(cam.up), flat.dot(cam.forward))
        let horizon = c.z > 0.01 ? cam.cy - c.y * cam.focal / c.z : -1e4
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let grad = CGGradient(colorsSpace: space, colors: [skyTop.cg(), skyTop.mix(skyHorizon, 0.55).cg(), skyHorizon.cg()] as CFArray, locations: [0, 0.6, 1])!
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: width, height: height))
        let top = min(horizon - cam.focal * 0.9, horizon - 200)
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: max(horizon, top + 1)), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()

        // A few soft clouds at fixed directions, so they turn with the camera.
        for k in 0..<9 {
            let az = Double(k) * 0.71 + 0.3
            let el = 0.06 + hash01(k * 31) * 0.16
            let d = Vec3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
            let cc = Vec3(d.dot(cam.right), d.dot(cam.up), d.dot(cam.forward))
            guard cc.z > 0.05 else { continue }
            let p = cam.projectCam(cc)
            let r = cam.focal * (0.10 + hash01(k * 7) * 0.08)
            for j in 0..<4 {
                let ox = (Double(j) - 1.5) * r * 0.55
                let oy = (hash01(k * 13 + j) - 0.5) * r * 0.25
                let rr = r * (0.55 + hash01(k * 17 + j) * 0.35)
                let g = CGGradient(colorsSpace: space, colors: [RGB(1, 1, 1).cg(0.55), RGB(1, 1, 1).cg(0)] as CFArray, locations: [0, 1])!
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: p.x + ox, y: p.y + oy), startRadius: 0, endCenter: CGPoint(x: p.x + ox, y: p.y + oy), endRadius: rr * 0.6 + 1, options: [])
            }
        }
        // Ground below the horizon fades into haze.
        if horizon < height {
            ctx.setFillColor(fogColor.mix(RGB(hex: 0x8F948F), 0.25).cg())
            ctx.fill(CGRect(x: 0, y: max(0, horizon - 1), width: width, height: height - max(0, horizon - 1)))
        }
    }

    // MARK: Ground

    private func drawGround() {
        let asphalt = RGB(hex: 0x4B4E53)
        let bikeGreen = RGB(hex: 0x4E8B5E)
        let brick = RGB(hex: 0x9C6B57)
        let concrete = RGB(hex: 0xB9B4AA)
        let grass = RGB(hex: 0x6E8E4B)
        let lawnFar = RGB(hex: 0x8C8B7E)
        let curbFace = RGB(hex: 0x8E8A83)
        let cy = Road.curbHeight

        let chunk = 8.0
        let z0 = floor((cam.pos.z - 280) / chunk) * chunk
        let z1 = cam.pos.z + 280
        var z = z0
        while z < z1 {
            let za = z, zb = z + chunk
            let zwMid = worldZ((za + zb) / 2)
            let depth = cam.depth(Vec3(cam.pos.x, 0, (za + zb) / 2))
            let patch = 0.97 + hash01(Int(floor(worldZ(za) / chunk))) * 0.06
            let inter = Road.inIntersection(zwMid)
            func g(_ c: RGB) -> RGB { fog(c, depth) }
            // Far ground on both sides.
            fillPoly(rect(-90, Road.buildingLeft, za, zb), g(lawnFar))
            fillPoly(rect(Road.buildingRight, 90, za, zb), g(lawnFar))
            if inter {
                fillPoly(rect(-90, 90, za, zb, y: 0), g(asphalt.scaled(patch)))
            } else {
                fillPoly(rect(Road.buildingLeft, Road.sidewalkLeftEdge, za, zb, y: cy), g(grass))
                fillPoly(rect(Road.sidewalkLeftEdge, Road.roadLeft - 0.45, za, zb, y: cy), g(brick))
                fillPoly(rect(Road.roadLeft - 0.45, Road.roadLeft, za, zb, y: cy), g(concrete))
                fillPoly(rect(Road.bikeLaneRight, Road.bikeLaneRight + 0.45, za, zb, y: cy), g(concrete))
                fillPoly(rect(Road.bikeLaneRight + 0.45, Road.sidewalkRightEdge, za, zb, y: cy), g(brick))
                fillPoly(rect(Road.sidewalkRightEdge, Road.buildingRight, za, zb, y: cy), g(grass))
                fillPoly(rect(Road.roadLeft, Road.bikeLaneLeft, za, zb), g(asphalt.scaled(patch)))
            }
            if inter { fillPoly(rect(Road.roadLeft, Road.bikeLaneLeft, za, zb), g(asphalt.scaled(patch))) }
            fillPoly(rect(Road.bikeLaneLeft, Road.bikeLaneRight, za, zb), g(inter ? asphalt.mix(bikeGreen, 0.5) : bikeGreen.scaled(patch)))
            if !inter {
                // Curb faces (only the one facing the camera shows).
                if cam.pos.x < Road.bikeLaneRight {
                    fillPoly([Vec3(Road.bikeLaneRight, 0, za), Vec3(Road.bikeLaneRight, cy, za), Vec3(Road.bikeLaneRight, cy, zb), Vec3(Road.bikeLaneRight, 0, zb)], g(curbFace))
                }
                if cam.pos.x > Road.roadLeft {
                    fillPoly([Vec3(Road.roadLeft, 0, za), Vec3(Road.roadLeft, cy, za), Vec3(Road.roadLeft, cy, zb), Vec3(Road.roadLeft, 0, zb)], g(curbFace))
                }
            }
            z = zb
        }
        drawMarkings()
        drawGroundDecals()
    }

    private func drawMarkings() {
        let white = RGB(hex: 0xE9E8E1)
        let yellow = RGB(hex: 0xD8B13C)
        let y = 0.006
        let zA = cam.pos.z - 260, zB = cam.pos.z + 260
        // Long lines, split in chunks for fog and near-plane clipping.
        let chunk = 8.0
        var z = floor(zA / chunk) * chunk
        while z < zB {
            let za = z, zb = z + chunk
            let depth = cam.depth(Vec3(cam.pos.x, 0, za + 4))
            let inter = Road.inIntersection(worldZ(za + 4))
            if !inter {
                fillPoly(rect(Road.bikeLaneLeft, Road.bikeLaneLeft + 0.13, za, zb, y: y), fog(white, depth), seam: false)
                fillPoly(rect(Road.centerLine - 0.24, Road.centerLine - 0.12, za, zb, y: y), fog(yellow, depth), seam: false)
                fillPoly(rect(Road.centerLine + 0.0, Road.centerLine + 0.12, za, zb, y: y), fog(yellow, depth), seam: false)
                fillPoly(rect(Road.roadLeft + 0.25, Road.roadLeft + 0.37, za, zb, y: y), fog(white.scaled(0.95), depth), seam: false)
            } else {
                // Dashed green-and-white crossing through the intersection.
                let zw = worldZ(za)
                if Int(floor(zw / 2)) % 2 == 0 {
                    fillPoly(rect(Road.bikeLaneLeft, Road.bikeLaneLeft + 0.13, za, za + 1, y: y), fog(white, depth), seam: false)
                    fillPoly(rect(Road.bikeLaneRight - 0.13, Road.bikeLaneRight, za, za + 1, y: y), fog(white, depth), seam: false)
                }
            }
            z = zb
        }
        // Crosswalks and stop lines at each intersection in view.
        let first = Road.intersectionCenter(near: worldZ(zA))
        var c = first
        while frameZ(c) < zB + 40 {
            for side in [-1.0, 1.0] {
                let edge = frameZ(c) + side * (Road.crossStreetWidth / 2 - 1.8)
                let depth = cam.depth(Vec3(cam.pos.x, 0, edge))
                var x = Road.roadLeft + 0.3
                while x < Road.bikeLaneRight - 0.3 {
                    fillPoly(rect(x, x + 0.5, edge - 1.5, edge + 1.5, y: y), fog(white, depth), seam: false)
                    x += 1.0
                }
                let stop = edge - side * 2.6
                fillPoly(rect(Road.centerLine, Road.bikeLaneLeft, stop - 0.2, stop + 0.2, y: y), fog(white, depth), seam: false)
            }
            c += Road.blockLength
        }
        // Bike symbols in the bike lane every 36 m.
        var k = floor(worldZ(zA) / 36)
        while frameZ(k * 36) < zB {
            let zf = frameZ(k * 36 + 10)
            if !Road.inIntersection(k * 36 + 10, margin: 3) { drawBikeStencil(atZ: zf) }
            k += 1
        }
    }

    private func drawBikeStencil(atZ z: Double) {
        let depth = cam.depth(Vec3(riderX, 0, z))
        guard depth > 0.5 else { return }
        let color = fog(RGB(hex: 0xEDEDE6), depth)
        let s = cam.scale(at: Vec3(riderX, 0, z))
        ctx.setStrokeColor(color.cg(0.92))
        ctx.setLineWidth(max(0.6, s * 0.09))
        ctx.setLineCap(.round)
        func line(_ pts: [(Double, Double)]) {
            let proj = pts.compactMap { cam.project(Vec3(riderX + $0.0, 0.007, z + $0.1)) }
            guard proj.count == pts.count else { return }
            ctx.addLines(between: proj)
            ctx.strokePath()
        }
        func circle(_ cz: Double) {
            let pts = (0...16).map { i -> (Double, Double) in
                let a = Double(i) / 16 * 2 * .pi
                return (cos(a) * 0.32, cz + sin(a) * 0.32 * 1.0)
            }
            line(pts)
        }
        circle(-0.55)
        circle(0.55)
        line([(0, -0.55), (0, 0), (0, 0.55)])
        line([(-0.15, 0.1), (0.15, 0.1)])
        // Arrow ahead of the symbol.
        line([(0, 1.3), (0, 2.6)])
        line([(-0.3, 2.2), (0, 2.6), (0.3, 2.2)])
    }

    private func drawGroundDecals() {
        // Shadows.
        let shadow = RGB(hex: 0x1E2226)
        let offX = -sun.x / sun.y
        let offZ = -sun.z / sun.y
        for v in snap.vehicles {
            let h = v.height * 0.55
            for (grow, a) in [(0.35, 0.16), (0.12, 0.32)] {
                let pts = [
                    Vec3(v.x - v.width / 2 - grow, 0.008, v.z - v.length / 2 - grow),
                    Vec3(v.x + v.width / 2 + grow, 0.008, v.z - v.length / 2 - grow),
                    Vec3(v.x + v.width / 2 + grow + offX * h, 0.008, v.z + v.length / 2 + grow + offZ * h),
                    Vec3(v.x - v.width / 2 - grow + offX * h, 0.008, v.z + v.length / 2 + grow + offZ * h),
                ]
                let shifted = pts.map { Vec3($0.x + offX * h * 0.5, $0.y, $0.z + offZ * h * 0.5) }
                fillPoly(shifted, shadow, alpha: a, seam: false)
            }
        }
        if opt.drawRider {
            let f = snap.fall
            let w = 0.25 + f * 0.6
            fillPoly(rect(riderX - w + 0.25 * f, riderX + w + 0.5 * f, -0.75, 0.75, y: 0.009).map { Vec3($0.x + 0.35, $0.y, $0.z + 0.3) }, shadow, alpha: 0.3, seam: false)
        }

        // Detection zone behind the rider (what the rear camera watches).
        if opt.showCone > 0 {
            let alert = opt.coneAlert
            let base = alert ? RGB(hex: 0xFF5A4F) : RGB(hex: 0xC8F135)
            let apex = Vec3(riderX, 0.012, -0.45)
            let farL = Vec3(Road.centerLine + 0.4, 0.012, -60)
            let farR = Vec3(Road.bikeLaneRight + 0.8, 0.012, -60)
            if let p = cam.projectPolygon([apex, farL, farR]), let a = cam.project(apex), let b = cam.project(Vec3(riderX - 0.9, 0.012, -45)) {
                ctx.saveGState()
                ctx.addPath(path(p))
                ctx.clip()
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [base.cg(0.42 * opt.showCone), base.cg(0.0)] as CFArray, locations: [0, 1])!
                ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsAfterEndLocation])
                ctx.restoreGState()
                ctx.addPath(path(p))
                ctx.setStrokeColor(base.cg(0.5 * opt.showCone))
                ctx.setLineWidth(1.5)
                ctx.strokePath()
            }
        }

        // Near-miss marks painted where each was logged.
        for nm in snap.nearMisses {
            let z = nm.at - snap.riderDistance
            let r = 0.7
            let color = nm.source == "rider_reported" ? RGB(hex: 0xC8F135) : RGB(hex: 0xF5A524)
            let pts = [Vec3(riderX, 0.012, z - r), Vec3(riderX + r * 0.75, 0.012, z), Vec3(riderX, 0.012, z + r), Vec3(riderX - r * 0.75, 0.012, z)]
            fillPoly(pts, color, alpha: 0.85, seam: false)
        }

        // Crash: a pulsing ring around the rider.
        if opt.crashRing {
            let phase = snap.crashPhase
            if phase == "countdown" || phase == "sending" || phase == "sent" {
                let pulse = phase == "countdown" ? 0.5 + 0.5 * sin(opt.time * 7) : 1
                for (radius, a) in [(1.7 + pulse * 0.5, 0.18 + pulse * 0.12), (2.6 + pulse * 0.8, 0.08)] {
                    let ring = (0..<36).map { i -> Vec3 in
                        let t = Double(i) / 36 * 2 * .pi
                        return Vec3(riderX + 0.7 + cos(t) * radius, 0.013, 0.2 + sin(t) * radius)
                    }
                    fillPoly(ring, RGB(hex: 0xFF4D44), alpha: a, seam: false)
                    if let p = cam.projectPolygon(ring) {
                        ctx.addPath(path(p))
                        ctx.setStrokeColor(RGB(hex: 0xFF4D44).cg(0.8))
                        ctx.setLineWidth(2.5)
                        ctx.strokePath()
                    }
                }
            }
        }
    }

    // MARK: Buildings

    private func addBuildings() {
        let bricks: [RGB] = [RGB(hex: 0x8C4E3D), RGB(hex: 0x9E5F49), RGB(hex: 0x74503F), RGB(hex: 0xB49372), RGB(hex: 0x87604C), RGB(hex: 0xA1735B)]
        let span = 7.6
        let zwA = worldZ(cam.pos.z - 300)
        let zwB = worldZ(cam.pos.z + 300)
        var k = floor(zwA / span)
        while k * span < zwB {
            for side in [-1.0, 1.0] {
                let zs = k * span
                let ze = zs + span - 0.15
                if Road.inIntersection(zs, margin: 1) || Road.inIntersection(ze, margin: 1) { continue }
                let n = Int(k) * 2 + (side > 0 ? 1 : 0)
                let h = 11.5 + hash01(n * 3) * 6.5
                let color = bricks[Int(hash01(n * 5) * Double(bricks.count)) % bricks.count]
                let depthM = 13.0
                let xFace = side > 0 ? Road.buildingRight : Road.buildingLeft
                let xBack = xFace + side * depthM
                let za = frameZ(zs), zb = frameZ(ze)
                let center = Vec3(xFace, h / 2, (za + zb) / 2)
                let depth = cam.depth(center)
                if depth < -20 { continue }
                let facade = [Vec3(xFace, 0, za), Vec3(xFace, h, za), Vec3(xFace, h, zb), Vec3(xFace, 0, zb)]
                let normal = Vec3(-side, 0, 0)
                items.append((depth + 6, { [self] in
                    // End walls and roof first (painter order within the building).
                    if cam.pos.z < za {
                        fillPoly([Vec3(xFace, 0, za), Vec3(xBack, 0, za), Vec3(xBack, h, za), Vec3(xFace, h, za)], fog(shade(color, normal: Vec3(0, 0, -1)).scaled(0.9), depth))
                    }
                    if cam.pos.z > zb {
                        fillPoly([Vec3(xFace, 0, zb), Vec3(xBack, 0, zb), Vec3(xBack, h, zb), Vec3(xFace, h, zb)], fog(shade(color, normal: Vec3(0, 0, 1)).scaled(0.9), depth))
                    }
                    if cam.pos.y > h {
                        fillPoly([Vec3(xFace, h, za), Vec3(xBack, h, za), Vec3(xBack, h, zb), Vec3(xFace, h, zb)], fog(RGB(hex: 0x5D5650), depth))
                    }
                    guard (cam.pos.x - xFace) * -side > 0 else { return }
                    fillPoly(facade, fog(shade(color, normal: normal), depth))
                    self.drawFacadeDetail(xFace: xFace, side: side, za: za, zb: zb, h: h, n: n, depth: depth, base: color)
                }))
            }
            k += 1
        }
    }

    private func drawFacadeDetail(xFace: Double, side: Double, za: Double, zb: Double, h: Double, n: Int, depth: Double, base: RGB) {
        let x = xFace - side * 0.02
        let glass = RGB(hex: 0x2D3945).mix(skyHorizon, 0.18)
        let trim = RGB(hex: 0xE4DED2)
        let w = zb - za
        let cols = 3
        let floors = Int((h - 2.2) / 3.1)
        // Cornice band.
        fillPoly([Vec3(x, h - 0.7, za), Vec3(x, h, za), Vec3(x, h, zb), Vec3(x, h - 0.7, zb)], fog(trim.scaled(0.85), depth))
        if depth > 230 { return }
        for f in 0..<floors {
            let y0 = 2.2 + Double(f) * 3.1
            for c in 0..<cols {
                let cz = za + w * (Double(c) + 0.5) / Double(cols)
                let lit = hash01(n * 97 + f * 7 + c) < 0.12
                let g = lit ? RGB(hex: 0x8A7A55) : glass.mix(RGB(hex: 0x6E8FAE), hash01(n * 31 + f + c * 5) * 0.35)
                fillPoly([Vec3(x, y0 - 0.1, cz - 0.62), Vec3(x, y0 + 2.0, cz - 0.62), Vec3(x, y0 + 2.0, cz + 0.62), Vec3(x, y0 - 0.1, cz + 0.62)], fog(trim.scaled(0.8), depth))
                fillPoly([Vec3(x, y0, cz - 0.5), Vec3(x, y0 + 1.85, cz - 0.5), Vec3(x, y0 + 1.85, cz + 0.5), Vec3(x, y0, cz + 0.5)], fog(g, depth))
                fillPoly([Vec3(x, y0 + 0.9, cz - 0.5), Vec3(x, y0 + 0.97, cz - 0.5), Vec3(x, y0 + 0.97, cz + 0.5), Vec3(x, y0 + 0.9, cz + 0.5)], fog(trim, depth))
            }
        }
        // Door and stoop.
        let dz = za + w * 0.18
        fillPoly([Vec3(x, Road.curbHeight + 0.9, dz - 0.55), Vec3(x, 3.1, dz - 0.55), Vec3(x, 3.1, dz + 0.55), Vec3(x, Road.curbHeight + 0.9, dz + 0.55)], fog(RGB(hex: 0x2B231E), depth))
        let stoopX = x - side * 1.6
        fillPoly([Vec3(x, Road.curbHeight + 0.9, dz - 0.9), Vec3(stoopX, Road.curbHeight, dz - 0.9), Vec3(stoopX, Road.curbHeight, dz + 0.9), Vec3(x, Road.curbHeight + 0.9, dz + 0.9)], fog(base.mix(trim, 0.4).scaled(0.95), depth))
    }

    // MARK: Trees and lamps

    private func addTrees() {
        let spacing = 12.5
        var k = floor(worldZ(cam.pos.z - 260) / spacing)
        while frameZ(k * spacing) < cam.pos.z + 260 {
            for side in [-1.0, 1.0] {
                let zw = k * spacing + (side > 0 ? 3 : 9)
                if Road.inIntersection(zw, margin: 2) { continue }
                let x = side > 0 ? 3.05 : -8.35
                let z = frameZ(zw)
                let n = Int(k) * 2 + (side > 0 ? 1 : 0)
                let height = 3.4 + hash01(n * 11) * 1.2
                let base = Vec3(x, Road.curbHeight, z)
                let depth = cam.depth(base)
                if depth < 0.3 { continue }
                // Tree-pit shadow.
                let offX = -sun.x / sun.y * 4, offZ = -sun.z / sun.y * 4
                items.append((depth + 40, { [self] in
                    let pts = (0..<14).map { i -> Vec3 in
                        let a = Double(i) / 14 * 2 * .pi
                        return Vec3(x + offX + cos(a) * 2.2, Road.curbHeight + 0.004, z + offZ + sin(a) * 2.2)
                    }
                    fillPoly(pts, RGB(hex: 0x1E2420), alpha: 0.22, seam: false)
                }))
                items.append((depth, { [self] in
                    segment(base, Vec3(x, height + 0.6, z), width: 0.26, color: RGB(hex: 0x4A3A2B))
                }))
                for j in 0..<4 {
                    let ox = (hash01(n * 13 + j) - 0.5) * 1.8
                    let oz = (hash01(n * 17 + j) - 0.5) * 1.8
                    let oy = height + 0.8 + hash01(n * 19 + j) * 1.6
                    let r = 1.45 + hash01(n * 23 + j) * 0.6
                    let c = Vec3(x + ox, oy, z + oz)
                    let d = cam.depth(c)
                    if (c - cam.pos).length < r * 1.15 { continue }
                    let green = RGB(hex: 0x4C7536).mix(RGB(hex: 0x6E9A45), hash01(n * 29 + j))
                    items.append((d, { [self] in sphere(c, radius: r, color: green, depth: d) }))
                }
            }
            k += 1
        }
    }

    private func addLamps() {
        let spacing = 36.0
        var k = floor(worldZ(cam.pos.z - 200) / spacing)
        while frameZ(k * spacing) < cam.pos.z + 200 {
            for side in [-1.0, 1.0] {
                let zw = k * spacing + (side > 0 ? 20 : 2)
                if Road.inIntersection(zw, margin: 1) { continue }
                let x = side > 0 ? 2.45 : -7.75
                let z = frameZ(zw)
                let d = cam.depth(Vec3(x, 3, z))
                if d < 0.5 { continue }
                items.append((d, { [self] in
                    let dark = RGB(hex: 0x2E3236)
                    segment(Vec3(x, Road.curbHeight, z), Vec3(x, 6.6, z), width: 0.13, color: dark)
                    segment(Vec3(x, 6.6, z), Vec3(x - side * 1.4, 6.9, z), width: 0.08, color: dark)
                    segment(Vec3(x - side * 1.2, 6.82, z), Vec3(x - side * 1.75, 6.82, z), width: 0.22, color: dark)
                }))
            }
            k += 1
        }
    }

    // MARK: Primitive items

    func segment(_ a: Vec3, _ b: Vec3, width: Double, color: RGB, alpha: Double = 1, fogged: Bool = true) {
        guard let (pa, pb) = cam.projectSegment(a, b) else { return }
        let mid = Vec3.lerp(a, b, 0.5)
        let d = max(nearPlane, cam.depth(mid))
        let w = max(1.0, width * cam.focal / d)
        ctx.setStrokeColor((fogged ? fog(color, d) : color).cg(alpha))
        ctx.setLineWidth(w)
        ctx.setLineCap(.round)
        ctx.move(to: pa)
        ctx.addLine(to: pb)
        ctx.strokePath()
    }

    func sphere(_ c: Vec3, radius: Double, color: RGB, depth: Double) {
        guard let p = cam.project(c) else { return }
        let r = radius * cam.focal / max(nearPlane, depth)
        if r < 0.5 || r > 6000 { return }
        let light = fog(color.scaled(1.25), depth)
        let darkC = fog(color.scaled(0.6), depth)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: space, colors: [light.cg(), fog(color, depth).cg(), darkC.cg()] as CFArray, locations: [0, 0.55, 1])!
        // The highlight sits toward the sun on screen.
        let s = Vec3(sun.dot(cam.right), sun.dot(cam.up), 0)
        let hl = CGPoint(x: p.x + s.x * r * 0.45, y: p.y - s.y * r * 0.45)
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        ctx.clip()
        ctx.drawRadialGradient(g, startCenter: hl, startRadius: 0, endCenter: p, endRadius: r * 1.05, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    // MARK: Vehicles

    private struct Face {
        var pts: [Vec3]
        var color: RGB
        var glass = false
        var extra: ((Vec3) -> Void)? = nil  // decorations drawn on the face, given its normal
    }

    private func vehicleColor(_ v: VehicleState) -> RGB {
        let palette: [RGB] = [RGB(hex: 0xE8E9EB), RGB(hex: 0x9EA4AA), RGB(hex: 0x24272B), RGB(hex: 0x27406A), RGB(hex: 0x8E1F25), RGB(hex: 0x5E646B), RGB(hex: 0xC9C2B4)]
        if v.kind == "car" && v.x > -1.0 && v.direction == 1 { return RGB(hex: 0x2A2E33) }  // the close-pass car
        return palette[(v.id * 3 + (v.direction == 1 ? 1 : 4)) % palette.count]
    }

    private func addVehicle(_ v: VehicleState) {
        let center = Vec3(v.x, v.height / 2, v.z)
        let depth = cam.depth(center)
        if depth < -v.length || depth > 330 { return }
        let dir = Double(v.direction)
        let W = v.width
        let L = v.length
        func P(_ lx: Double, _ y: Double, _ lz: Double) -> Vec3 { Vec3(v.x + lx, y, v.z + dir * lz) }
        var faces: [Face] = []
        let body = vehicleColor(v)
        let glassC = RGB(hex: 0x1F2A33)

        switch v.kind {
        case "truck":
            let cabStart = L / 2 - 2.2
            faces += extrude(profile: [(cabStart, 0.45), (cabStart, 2.55), (L / 2 - 0.9, 2.55), (L / 2 - 0.2, 1.6), (L / 2, 1.25), (L / 2, 0.45)], halfWidth: { _ in W / 2 - 0.05 }, P: P, color: body, glassStrips: [2])
            faces += box(P: P, x0: -W / 2, x1: W / 2, y0: 0.62, y1: 3.0, z0: -L / 2, z1: cabStart - 0.1, color: RGB(hex: 0xEDEDEA))
            addWheels(v, P: P, axles: [-L / 2 + 1.4, L / 2 - 1.3], r: 0.48, faces: &faces)
            addLights(P: P, L: L, W: W, rearY: 0.75, frontY: 0.85, faces: &faces)
        case "bus":
            faces += extrude(profile: [(-L / 2, 0.35), (-L / 2, 3.05), (-L / 2 + 0.25, 3.2), (L / 2 - 0.35, 3.2), (L / 2, 2.95), (L / 2, 0.35)], halfWidth: { _ in W / 2 }, P: P, color: RGB(hex: 0xE4E6E3), glassStrips: [], busWindows: true)
            addWheels(v, P: P, axles: [-L / 2 + 2.7, L / 2 - 2.5], r: 0.5, faces: &faces)
            addLights(P: P, L: L, W: W, rearY: 0.8, frontY: 0.75, faces: &faces)
        default:
            let prof: [(Double, Double)] = [(-0.5 * L, 0.30), (-0.5 * L, 0.80), (-0.44 * L, 0.93), (-0.30 * L, 0.99), (-0.17 * L, 1.44), (0.10 * L, 1.47), (0.27 * L, 1.02), (0.46 * L, 0.85), (0.5 * L, 0.63), (0.5 * L, 0.30)]
            faces += extrude(profile: prof, halfWidth: { y in W / 2 - 0.17 * clamp01((y - 0.99) / 0.45) }, P: P, color: body, glassStrips: [3, 5], sideWindows: [(-0.285 * L, 1.04), (-0.165 * L, 1.39), (0.095 * L, 1.42), (0.255 * L, 1.04)], hw: { y in W / 2 - 0.17 * clamp01((y - 0.99) / 0.45) })
            addWheels(v, P: P, axles: [-0.32 * L, 0.32 * L], r: 0.33, faces: &faces)
            addLights(P: P, L: L, W: W, rearY: 0.7, frontY: 0.74, faces: &faces)
        }
        _ = glassC

        let objCenter = Vec3(v.x, 1.0, v.z)
        for face in faces {
            let pts = face.pts
            guard pts.count >= 3 else { continue }
            var n = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized
            let fc = pts.reduce(Vec3(0, 0, 0)) { $0 + $1 } * (1 / Double(pts.count))
            if n.dot(fc - objCenter) < 0 { n = n * -1 }
            if n.dot(cam.pos - fc) <= 0 { continue }
            let d = cam.depth(fc)
            var col: RGB
            if face.glass {
                col = RGB(hex: 0x26323C).mix(skyHorizon, 0.18 + max(0, n.y) * 0.35)
            } else {
                col = shade(face.color, normal: n)
                // A little sky reflection on top surfaces makes paint read as glossy.
                col = col.mix(skyHorizon, max(0, n.y) * 0.14)
            }
            let fcol = fog(col, d)
            items.append((d, { [self] in
                fillPoly(pts, fcol)
                if let extra = face.extra { extra(n) }
            }))
        }
    }

    private func extrude(profile: [(Double, Double)], halfWidth: @escaping (Double) -> Double, P: @escaping (Double, Double, Double) -> Vec3, color: RGB, glassStrips: [Int], sideWindows: [(Double, Double)]? = nil, hw: ((Double) -> Double)? = nil, busWindows: Bool = false) -> [Face] {
        var faces: [Face] = []
        for side in [-1.0, 1.0] {
            let pts = profile.map { P(side * halfWidth($0.1), $0.1, $0.0) }
            var face = Face(pts: pts, color: color)
            face.extra = { [self] _ in
                if let win = sideWindows, let hw {
                    let wp = win.map { P(side * (hw($0.1) + 0.012), $0.1, $0.0) }
                    let c = fog(RGB(hex: 0x26323C).mix(skyHorizon, 0.22), cam.depth(wp[0]))
                    fillPoly(wp, c)
                    // B-pillar.
                    let mz = (win[1].0 + win[2].0) / 2 - 0.02
                    segment(P(side * (hw(1.05) + 0.015), 1.05, mz), P(side * (hw(1.4) + 0.015), 1.4, mz + 0.03), width: 0.08, color: color.scaled(0.45))
                }
                if busWindows {
                    let x = side * (halfWidth(1.5) + 0.012)
                    let zs = profile.first!.0 + 0.7
                    let ze = profile.last!.0 - 1.6
                    var z = zs
                    while z < ze {
                        let wp = [P(x, 1.35, z), P(x, 2.55, z), P(x, 2.55, z + 1.25), P(x, 1.35, z + 1.25)]
                        fillPoly(wp, fog(RGB(hex: 0x24303A).mix(skyHorizon, 0.2), cam.depth(wp[0])))
                        z += 1.4
                    }
                    let stripe = [P(x, 0.55, profile.first!.0 + 0.1), P(x, 0.85, profile.first!.0 + 0.1), P(x, 0.85, profile.last!.0 - 0.1), P(x, 0.55, profile.last!.0 - 0.1)]
                    fillPoly(stripe, fog(RGB(hex: 0x23498A), cam.depth(stripe[0])))
                }
            }
            faces.append(face)
        }
        for i in 0..<(profile.count - 1) {
            let a = profile[i], b = profile[i + 1]
            let pts = [P(-halfWidth(a.1), a.1, a.0), P(halfWidth(a.1), a.1, a.0), P(halfWidth(b.1), b.1, b.0), P(-halfWidth(b.1), b.1, b.0)]
            var f = Face(pts: pts, color: color)
            f.glass = glassStrips.contains(i)
            if busWindows && i == profile.count - 2 {
                // Bus front: windshield and destination sign.
                f.extra = { [self] _ in
                    let z = b.0 + 0.012
                    let w = halfWidth(1.5) - 0.12
                    let ws = [P(-w, 1.05, z), P(w, 1.05, z), P(w, 2.55, z), P(-w, 2.55, z)]
                    fillPoly(ws, fog(RGB(hex: 0x24303A).mix(skyHorizon, 0.25), cam.depth(ws[0])))
                    let sign = [P(-w, 2.62, z), P(w, 2.62, z), P(w, 2.9, z), P(-w, 2.9, z)]
                    fillPoly(sign, RGB(hex: 0x15181B))
                    drawProjectedText("1  HARVARD", corners: (P(-w + 0.1, 2.88, z), P(w - 0.1, 2.88, z), P(-w + 0.1, 2.64, z)), color: RGB(hex: 0xFFA43A))
                }
            }
            faces.append(f)
        }
        return faces
    }

    private func box(P: @escaping (Double, Double, Double) -> Vec3, x0: Double, x1: Double, y0: Double, y1: Double, z0: Double, z1: Double, color: RGB) -> [Face] {
        [
            Face(pts: [P(x0, y1, z0), P(x1, y1, z0), P(x1, y1, z1), P(x0, y1, z1)], color: color),
            Face(pts: [P(x0, y0, z0), P(x0, y1, z0), P(x0, y1, z1), P(x0, y0, z1)], color: color),
            Face(pts: [P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), P(x1, y0, z1)], color: color),
            Face(pts: [P(x0, y0, z0), P(x1, y0, z0), P(x1, y1, z0), P(x0, y1, z0)], color: color.scaled(0.97)),
            Face(pts: [P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1)], color: color.scaled(0.97)),
        ]
    }

    private func addWheels(_ v: VehicleState, P: @escaping (Double, Double, Double) -> Vec3, axles: [Double], r: Double, faces: inout [Face]) {
        let side = cam.pos.x > v.x ? 1.0 : -1.0
        let x = side * (v.width / 2 + 0.015)
        for lz in axles {
            let tire = (0..<18).map { i -> Vec3 in
                let a = Double(i) / 18 * 2 * .pi
                return P(x, r + sin(a) * r, lz + cos(a) * r)
            }
            var f = Face(pts: tire, color: RGB(hex: 0x141516))
            f.extra = { [self] _ in
                let rim = (0..<14).map { i -> Vec3 in
                    let a = Double(i) / 14 * 2 * .pi
                    return P(x + side * 0.01, r + sin(a) * r * 0.58, lz + cos(a) * r * 0.58)
                }
                fillPoly(rim, fog(RGB(hex: 0x8F959B), cam.depth(rim[0])))
                let hub = (0..<8).map { i -> Vec3 in
                    let a = Double(i) / 8 * 2 * .pi
                    return P(x + side * 0.02, r + sin(a) * r * 0.18, lz + cos(a) * r * 0.18)
                }
                fillPoly(hub, fog(RGB(hex: 0x3A3E42), cam.depth(hub[0])))
            }
            // Arch behind the wheel.
            let arch = (0...10).map { i -> Vec3 in
                let a = Double(i) / 10 * .pi
                return P(x - side * 0.005, r + sin(a) * r * 1.14, lz + cos(a) * r * 1.14)
            } + [P(x - side * 0.005, r, lz - r * 1.14)]
            faces.append(Face(pts: arch, color: RGB(hex: 0x0E0F10)))
            faces.append(f)
        }
    }

    private func addLights(P: @escaping (Double, Double, Double) -> Vec3, L: Double, W: Double, rearY: Double, frontY: Double, faces: inout [Face]) {
        let red = RGB(hex: 0xC4161C)
        let lamp = RGB(hex: 0xF4F1E6)
        for s in [-1.0, 1.0] {
            let x0 = s * (W / 2 - 0.06), x1 = s * (W / 2 - 0.42)
            faces.append(Face(pts: [P(x0, rearY - 0.08, -L / 2 - 0.012), P(x1, rearY - 0.08, -L / 2 - 0.012), P(x1, rearY + 0.08, -L / 2 - 0.012), P(x0, rearY + 0.08, -L / 2 - 0.012)], color: red.scaled(1.5)))
            faces.append(Face(pts: [P(x0, frontY - 0.07, L / 2 + 0.012), P(x1, frontY - 0.07, L / 2 + 0.012), P(x1, frontY + 0.07, L / 2 + 0.012), P(x0, frontY + 0.07, L / 2 + 0.012)], color: lamp.scaled(1.4)))
        }
        // License plate.
        faces.append(Face(pts: [P(-0.26, 0.42, -L / 2 - 0.013), P(0.26, 0.42, -L / 2 - 0.013), P(0.26, 0.58, -L / 2 - 0.013), P(-0.26, 0.58, -L / 2 - 0.013)], color: RGB(hex: 0xF2F2EC)))
    }

    /// Draws text mapped onto a 3D quad given its top-left, top-right and bottom-left corners.
    func drawProjectedText(_ text: String, corners: (Vec3, Vec3, Vec3), color: RGB) {
        guard let tl = cam.project(corners.0), let tr = cam.project(corners.1), let bl = cam.project(corners.2) else { return }
        let size = CGSize(width: 400, height: 60)
        let t = CGAffineTransform(a: (tr.x - tl.x) / size.width, b: (tr.y - tl.y) / size.width, c: (bl.x - tl.x) / size.height, d: (bl.y - tl.y) / size.height, tx: tl.x, ty: tl.y)
        guard abs(t.a * t.d - t.b * t.c) > 1e-5 else { return }
        ctx.saveGState()
        ctx.concatenate(t)
        UIText.draw(text, in: CGRect(origin: .zero, size: size), ctx: ctx, size: 44, weight: .heavy, color: color, align: .center)
        ctx.restoreGState()
    }

    // MARK: Near-miss pins

    private func addNearMissPins() {
        for nm in snap.nearMisses {
            let z = nm.at - snap.riderDistance
            let base = Vec3(riderX, 0, z)
            let d = cam.depth(base)
            if d < 1 { continue }
            let color = nm.source == "rider_reported" ? RGB(hex: 0xC8F135) : RGB(hex: 0xF5A524)
            items.append((d, { [self] in
                segment(Vec3(riderX, 0, z), Vec3(riderX, 1.5, z), width: 0.04, color: RGB(hex: 0xF4F4F0), fogged: false)
                let top = Vec3(riderX, 1.75, z)
                guard let p = cam.project(top) else { return }
                let r = max(4, 0.26 * cam.focal / d)
                let diamond = [CGPoint(x: p.x, y: p.y - r), CGPoint(x: p.x + r * 0.8, y: p.y), CGPoint(x: p.x, y: p.y + r), CGPoint(x: p.x - r * 0.8, y: p.y)]
                ctx.addPath(path(diamond))
                ctx.setFillColor(color.cg())
                ctx.fillPath()
                ctx.addPath(path(diamond))
                ctx.setStrokeColor(RGB(hex: 0x0B0F14).cg())
                ctx.setLineWidth(max(1.5, r * 0.14))
                ctx.strokePath()
            }))
        }
    }

    // MARK: Bike, rider, phone

    /// Rolls a point about the bike's ground line (positive = toward the rider's right).
    private func rolled(_ p: Vec3, angle a: Double, lift: Double = 0, slide: Vec3 = Vec3(0, 0, 0)) -> Vec3 {
        let dx = p.x - riderX
        let x = riderX + dx * cos(a) + p.y * sin(a)
        let y = -dx * sin(a) + p.y * cos(a)
        return Vec3(x + slide.x, max(0.02, y) + lift, p.z + slide.z)
    }

    private func ik(hip: Vec3, target: Vec3, a: Double, b: Double, hint: Vec3) -> Vec3 {
        let v = target - hip
        let d = min(max(v.length, 0.05), a + b - 0.001)
        let dirV = v.normalized
        let cosA = (a * a + d * d - b * b) / (2 * a * d)
        let along = a * cosA
        let perp = a * (max(0, 1 - cosA * cosA)).squareRoot()
        let bend = (hint - dirV * hint.dot(dirV)).normalized
        return hip + dirV * along + bend * perp
    }

    private func addBikeAndRider() {
        let fall = snap.fall
        let stationary = !snap.recording && snap.riderSpeed < 0.05
        let lean = stationary ? -0.13 : 0.0
        let angle = lean * (1 - fall) + fall * 1.32
        let wheelAngle = snap.riderDistance / 0.34
        let crank = wheelAngle / 2.6 + 0.6
        let slide = Vec3(0.25 * fall, 0, 0.35 * fall)
        let riderSlide = Vec3(0.55 * fall, 0, 0.55 * fall)
        func B(_ p: Vec3) -> Vec3 { rolled(p, angle: angle, slide: slide) }
        func R(_ p: Vec3) -> Vec3 { rolled(p, angle: angle, slide: riderSlide) }

        let x = riderX
        let rearHub = Vec3(x, 0.34, -0.52), frontHub = Vec3(x, 0.34, 0.5)
        let bb = Vec3(x, 0.29, -0.05)
        let seatCluster = Vec3(x, 0.78, -0.21)
        let headTop = Vec3(x, 0.9, 0.36), headBottom = Vec3(x, 0.72, 0.41)
        let saddle = Vec3(x, 1.0, -0.29)
        let bar = Vec3(x, 0.99, 0.42)
        let frame = RGB(hex: 0x2F6E73)
        let dark = RGB(hex: 0x17181A)
        let silver = RGB(hex: 0xA9AFB4)

        func seg(_ a: Vec3, _ b: Vec3, _ w: Double, _ c: RGB, rider: Bool = false) {
            let pa = rider ? R(a) : B(a), pb = rider ? R(b) : B(b)
            let d = cam.depth(Vec3.lerp(pa, pb, 0.5))
            items.append((d, { [self] in segment(pa, pb, width: w, color: c) }))
        }
        func wheel(_ hub: Vec3) {
            let center = B(hub)
            let d = cam.depth(center)
            items.append((d + 0.02, { [self] in
                let pts = (0...28).map { i -> Vec3 in
                    let a = Double(i) / 28 * 2 * .pi
                    return B(Vec3(hub.x, hub.y + sin(a) * 0.335, hub.z + cos(a) * 0.335))
                }
                let proj = pts.compactMap { cam.project($0) }
                guard proj.count == pts.count else { return }
                let s = cam.scale(at: center)
                ctx.setLineCap(.round)
                for k in 0..<8 {
                    let a = wheelAngle + Double(k) / 8 * .pi
                    let p1 = B(Vec3(hub.x, hub.y + sin(a) * 0.3, hub.z + cos(a) * 0.3))
                    let p2 = B(Vec3(hub.x, hub.y - sin(a) * 0.3, hub.z - cos(a) * 0.3))
                    if let q1 = cam.project(p1), let q2 = cam.project(p2) {
                        ctx.setStrokeColor(silver.cg(0.55))
                        ctx.setLineWidth(max(0.5, s * 0.006))
                        ctx.move(to: q1); ctx.addLine(to: q2); ctx.strokePath()
                    }
                }
                ctx.addLines(between: proj)
                ctx.setStrokeColor(dark.cg())
                ctx.setLineWidth(max(1.2, s * 0.05))
                ctx.strokePath()
                let rim = (0...28).map { i -> Vec3 in
                    let a = Double(i) / 28 * 2 * .pi
                    return B(Vec3(hub.x, hub.y + sin(a) * 0.3, hub.z + cos(a) * 0.3))
                }.compactMap { cam.project($0) }
                ctx.addLines(between: rim)
                ctx.setStrokeColor(silver.cg())
                ctx.setLineWidth(max(0.8, s * 0.016))
                ctx.strokePath()
            }))
        }

        wheel(rearHub)
        wheel(frontHub)
        seg(bb, seatCluster, 0.045, frame)
        seg(seatCluster, headTop, 0.04, frame)
        seg(bb, headBottom, 0.05, frame)
        seg(bb, rearHub, 0.03, frame)
        seg(seatCluster, rearHub, 0.026, frame)
        seg(headBottom, frontHub, 0.032, frame)
        seg(headBottom, headTop, 0.05, frame)
        seg(headTop, Vec3(x, 0.97, 0.4), 0.035, dark)
        seg(Vec3(x - 0.21, 0.99, 0.43), Vec3(x + 0.21, 0.99, 0.43), 0.03, dark)
        seg(seatCluster, Vec3(x, 0.98, -0.27), 0.028, silver)       // seat post
        seg(Vec3(x, 1.0, -0.38), Vec3(x, 1.01, -0.15), 0.07, dark) // saddle
        // Chainring and cranks.
        let pedalR = Vec3(x + 0.12, 0.29 + sin(crank) * 0.17, -0.05 + cos(crank) * 0.17)
        let pedalL = Vec3(x - 0.12, 0.29 - sin(crank) * 0.17, -0.05 - cos(crank) * 0.17)
        seg(Vec3(x + 0.07, bb.y, bb.z), pedalR, 0.03, silver)
        seg(Vec3(x - 0.07, bb.y, bb.z), pedalL, 0.03, silver)
        seg(Vec3(x + 0.06, 0.29, -0.15), Vec3(x + 0.06, 0.29, 0.05), 0.2, dark)

        // Phone mount on the seat post, rear camera facing back.
        addPhoneMount(B: B)

        // Rider.
        let jersey = RGB(hex: 0x2E3A48)
        let shorts = RGB(hex: 0x16181B)
        let skin = RGB(hex: 0xC7997B)
        let helmet = RGB(hex: 0xC8F135)
        let shoe = RGB(hex: 0xE8E8E4)
        let pelvis = Vec3(x, 1.03, -0.24)
        let shoulder = Vec3(x, 1.43, 0.14)
        let head = Vec3(x, 1.6, 0.28)
        for s in [-1.0, 1.0] {
            let hip = R(Vec3(x + s * 0.1, pelvis.y, pelvis.z))
            var foot = B(s > 0 ? pedalR : pedalL)
            if stationary && s < 0 { foot = Vec3(x - 0.45, 0.04, -0.02) }
            if fall > 0.3 { foot = Vec3.lerp(foot, R(Vec3(x + s * 0.12, 0.35, 0.1)), fall) }
            let knee = ik(hip: hip, target: foot, a: 0.47, b: 0.47, hint: R(Vec3(x + s * 0.1, 1.2, 0.6)) - R(Vec3(x + s * 0.1, 1.0, 0.0)))
            let dh = cam.depth(Vec3.lerp(hip, knee, 0.5))
            let dk = cam.depth(Vec3.lerp(knee, foot, 0.5))
            items.append((dh, { [self] in segment(hip, knee, width: 0.14, color: shorts) }))
            items.append((dk, { [self] in
                segment(knee, foot, width: 0.1, color: skin)
                segment(foot, foot + Vec3(0, 0, 0.09), width: 0.08, color: shoe)
            }))
            let sh = R(Vec3(x + s * 0.19, shoulder.y, shoulder.z))
            var hand = B(Vec3(x + s * 0.21, 0.99, 0.43))
            if fall > 0.3 { hand = Vec3.lerp(hand, R(Vec3(x + s * 0.3, 0.9, 0.5)), fall) }
            let elbow = ik(hip: sh, target: hand, a: 0.3, b: 0.3, hint: Vec3(s * 0.4, -0.6, -0.3))
            let da = cam.depth(Vec3.lerp(sh, hand, 0.5))
            items.append((da, { [self] in
                segment(sh, elbow, width: 0.09, color: jersey)
                segment(elbow, hand, width: 0.075, color: skin)
            }))
        }
        let p0 = R(pelvis), p1 = R(shoulder)
        let dt = cam.depth(Vec3.lerp(p0, p1, 0.5))
        items.append((dt, { [self] in
            segment(p0, p1, width: 0.33, color: jersey)
            segment(Vec3.lerp(p0, p1, 0.15), Vec3.lerp(p0, p1, 0.85), width: 0.06, color: helmet.scaled(0.9))
        }))
        let hc = R(head)
        let dhd = cam.depth(hc)
        items.append((dhd, { [self] in
            segment(R(Vec3(x, 1.45, 0.18)), hc, width: 0.1, color: skin)
            sphere(R(Vec3(x, 1.57, 0.31)), radius: 0.11, color: skin, depth: dhd)
            sphere(R(Vec3(x, 1.65, 0.27)), radius: 0.145, color: helmet, depth: dhd - 0.01)
        }))
    }

    private func addPhoneMount(B: @escaping (Vec3) -> Vec3) {
        guard opt.clamp > 0 || opt.phone > 0 else { return }
        let x = riderX
        let post = Vec3(x, 0.88, -0.255)
        if opt.clamp > 0 {
            let k = opt.clamp
            let a = B(post + Vec3(-0.03 * k, 0, 0.0)), b = B(post + Vec3(0.03 * k, 0, 0.0))
            let d = cam.depth(B(post))
            items.append((d - 0.01, { [self] in
                segment(a, b, width: 0.05 * k, color: RGB(hex: 0x1A1B1D))
                segment(B(post), B(post + Vec3(0, 0, -0.04 * k)), width: 0.03 * k, color: RGB(hex: 0x1A1B1D))
            }))
        }
        guard opt.phone > 0 else { return }
        let p = opt.phone
        let drop = (1 - p) * (1 - p) * 0.45
        let c = Vec3(x, 0.86 + drop, -0.305 - (1 - p) * 0.12)
        let hw = 0.038, hh = 0.078, ht = 0.005
        func Q(_ dx: Double, _ dy: Double, _ dz: Double) -> Vec3 { B(Vec3(c.x + dx, c.y + dy, c.z + dz)) }
        let back = [Q(-hw, -hh, -ht), Q(hw, -hh, -ht), Q(hw, hh, -ht), Q(-hw, hh, -ht)]
        let front = [Q(-hw, -hh, ht), Q(hw, -hh, ht), Q(hw, hh, ht), Q(-hw, hh, ht)]
        let bc = B(c)
        let toCam = cam.pos - bc
        let backNormal = B(c + Vec3(0, 0, -1)) - bc
        let d = cam.depth(bc)
        let glow = opt.lensGlow
        let screenOn = opt.screenOn
        items.append((d - 0.02, { [self] in
            let showBack = backNormal.dot(toCam) > 0
            // Edge band first, then the visible face.
            for (s0, s1) in [(0, 1), (1, 2), (2, 3), (3, 0)] {
                fillPoly([back[s0], back[s1], front[s1], front[s0]], RGB(hex: 0x8D9196))
            }
            if showBack {
                fillPoly(back, RGB(hex: 0x2A2D31))
                let lensC = Q(-hw + 0.019, hh - 0.019, -ht - 0.002)
                let module = [Q(-hw + 0.004, hh - 0.036, -ht - 0.002), Q(-hw + 0.036, hh - 0.036, -ht - 0.002), Q(-hw + 0.036, hh - 0.004, -ht - 0.002), Q(-hw + 0.004, hh - 0.004, -ht - 0.002)]
                fillPoly(module, RGB(hex: 0x1C1E21))
                if let lp = cam.project(lensC) {
                    let r = max(1.5, 0.008 * cam.scale(at: lensC))
                    ctx.setFillColor(RGB(hex: 0x05070A).cg())
                    ctx.fillEllipse(in: CGRect(x: lp.x - r, y: lp.y - r, width: 2 * r, height: 2 * r))
                    ctx.setFillColor(RGB(hex: 0x6EA8FF).cg(0.7))
                    ctx.fillEllipse(in: CGRect(x: lp.x - r * 0.35 - r * 0.2, y: lp.y - r * 0.35 - r * 0.25, width: r * 0.5, height: r * 0.5))
                    if glow > 0 {
                        let gr = r * (4 + 3 * glow)
                        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [RGB(hex: 0xE9FF9A).cg(0.85 * glow), RGB(hex: 0xC8F135).cg(0)] as CFArray, locations: [0, 1])!
                        ctx.drawRadialGradient(g, startCenter: lp, startRadius: 0, endCenter: lp, endRadius: gr, options: [])
                    }
                }
            } else {
                fillPoly(front, screenOn ? RGB(hex: 0x10161D) : RGB(hex: 0x0B0D10))
                if screenOn {
                    let bar = [Q(-hw + 0.008, -hh + 0.02, ht + 0.001), Q(hw - 0.008, -hh + 0.02, ht + 0.001), Q(hw - 0.008, -hh + 0.032, ht + 0.001), Q(-hw + 0.008, -hh + 0.032, ht + 0.001)]
                    fillPoly(bar, RGB(hex: 0xC8F135))
                }
            }
        }))
    }

    // MARK: Labels

    private func drawLabels() {
        for v in snap.vehicles {
            let front = v.z + v.length / 2
            var text: String?
            var color = RGB(hex: 0xF5A524)
            if v.direction == -1 {
                if abs(v.z) < 40 { text = "Oncoming · ignored"; color = RGB(hex: 0xBFC6CE) }
            } else if v.state == "tracking" {
                let closing = v.speed - snap.riderSpeed
                if closing > 0.5 { text = String(format: "Tracking · ~%.1f s away", -front / closing) }
            } else if v.state == "cued" && front < 0 {
                text = "Heads-up sent"
                color = RGB(hex: 0xFF5A4F)
            }
            guard let text, let p = cam.project(Vec3(v.x, v.height + 0.9, v.z)) else { continue }
            Pill.draw(text, at: p, color: color, ctx: ctx, scale: 1.25)
        }
        for nm in snap.nearMisses {
            let z = nm.at - snap.riderDistance
            guard z < -3, let p = cam.project(Vec3(riderX, 2.25, z)) else { continue }
            Pill.draw(nm.source == "rider_reported" ? "Close call · marked" : "Near miss logged", at: p, color: RGB(hex: 0xF5A524), ctx: ctx, scale: 1.25)
        }
    }

    // MARK: Vision overlay support

    /// Screen-space bounding box of a vehicle, or nil if it is not in front of the camera.
    func screenBox(_ v: VehicleState) -> CGRect? {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for dx in [-0.5, 0.5] {
            for dy in [0.0, 1.0] {
                for dz in [-0.5, 0.5] {
                    let p = Vec3(v.x + dx * v.width, 0.2 + dy * (v.height - 0.1), v.z + dz * v.length)
                    guard let q = cam.project(p) else { return nil }
                    minX = min(minX, q.x); maxX = max(maxX, q.x)
                    minY = min(minY, q.y); maxY = max(maxY, q.y)
                }
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Rounded tag drawn in screen space.
enum Pill {
    static func draw(_ text: String, at p: CGPoint, color: RGB, ctx: CGContext, scale s: Double) {
        let font = 15 * s
        let w = UIText.width(text, size: font, weight: .bold) + 18 * s
        let h = 28 * s
        let r = CGRect(x: p.x - w / 2, y: p.y - h, width: w, height: h)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        ctx.setFillColor(RGB(hex: 0x0B0F14).cg(0.82))
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.75 * s, dy: 0.75 * s), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        ctx.setStrokeColor(color.cg())
        ctx.setLineWidth(1.6 * s)
        ctx.strokePath()
        UIText.draw(text, in: r.offsetBy(dx: 0, dy: (h - font * 1.25) / 2 - 1), ctx: ctx, size: font, weight: .bold, color: color, align: .center)
    }
}
