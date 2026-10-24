import CoreGraphics
import Foundation

struct Vec3 {
    var x: Double
    var y: Double
    var z: Double
    init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
    func dot(_ b: Vec3) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: Vec3) -> Vec3 { Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    var length: Double { (x * x + y * y + z * z).squareRoot() }
    var normalized: Vec3 { let l = length; return l > 0 ? self * (1 / l) : self }
    static func lerp(_ a: Vec3, _ b: Vec3, _ t: Double) -> Vec3 { a + (b - a) * t }
}

func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func clamp01(_ t: Double) -> Double { max(0, min(1, t)) }
func smooth(_ t: Double) -> Double { let c = clamp01(t); return c * c * (3 - 2 * c) }
/// 0 → 1 between a and b, eased.
func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double { smooth((t - a) / (b - a)) }
/// Fades in over `fade` after `from`, out over `fade` before `to`.
func window(_ t: Double, _ from: Double, _ to: Double, fade: Double = 0.3) -> Double {
    if t < from || t > to { return 0 }
    return min(clamp01((t - from) / fade), clamp01((to - t) / fade))
}

struct RGB {
    var r: Double
    var g: Double
    var b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }
    func scaled(_ s: Double) -> RGB { RGB(min(1, r * s), min(1, g * s), min(1, b * s)) }
    func mix(_ o: RGB, _ t: Double) -> RGB { RGB(lerp(r, o.r, t), lerp(g, o.g, t), lerp(b, o.b, t)) }
    func cg(_ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

let nearPlane = 0.15

struct Camera {
    let pos: Vec3
    let right: Vec3
    let up: Vec3
    let forward: Vec3
    let focal: Double
    let cx: Double
    let cy: Double

    init(pos: Vec3, target: Vec3, fov: Double, width: Double, height: Double, roll: Double = 0) {
        self.pos = pos
        let f = (target - pos).normalized
        var r = Vec3(0, 1, 0).cross(f).normalized
        var u = f.cross(r)
        if roll != 0 {
            let c = cos(roll), s = sin(roll)
            let r2 = r * c + u * s
            u = u * c - r * s
            r = r2
        }
        forward = f
        right = r
        up = u
        focal = height / 2 / tan(fov * .pi / 180 / 2)
        cx = width / 2
        cy = height / 2
    }

    func toCamera(_ p: Vec3) -> Vec3 {
        let d = p - pos
        return Vec3(d.dot(right), d.dot(up), d.dot(forward))
    }

    func projectCam(_ c: Vec3) -> CGPoint {
        let s = focal / c.z
        return CGPoint(x: cx + c.x * s, y: cy - c.y * s)
    }

    func project(_ p: Vec3) -> CGPoint? {
        let c = toCamera(p)
        return c.z < nearPlane ? nil : projectCam(c)
    }

    func depth(_ p: Vec3) -> Double { (p - pos).dot(forward) }

    /// Pixels per meter at a world point (0 if behind the camera).
    func scale(at p: Vec3) -> Double {
        let z = depth(p)
        return z < nearPlane ? 0 : focal / z
    }

    /// Projects a world polygon, clipping it against the near plane.
    func projectPolygon(_ pts: [Vec3]) -> [CGPoint]? {
        let cam = pts.map(toCamera)
        var out: [Vec3] = []
        out.reserveCapacity(cam.count + 2)
        for i in 0..<cam.count {
            let a = cam[i]
            let b = cam[(i + 1) % cam.count]
            let aIn = a.z >= nearPlane
            let bIn = b.z >= nearPlane
            if aIn { out.append(a) }
            if aIn != bIn {
                let t = (nearPlane - a.z) / (b.z - a.z)
                out.append(Vec3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, nearPlane))
            }
        }
        return out.count >= 3 ? out.map(projectCam) : nil
    }

    /// Projects a segment, clipping it against the near plane.
    func projectSegment(_ a: Vec3, _ b: Vec3) -> (CGPoint, CGPoint)? {
        var ca = toCamera(a)
        var cb = toCamera(b)
        if ca.z < nearPlane && cb.z < nearPlane { return nil }
        if ca.z < nearPlane {
            let t = (nearPlane - ca.z) / (cb.z - ca.z)
            ca = Vec3(ca.x + (cb.x - ca.x) * t, ca.y + (cb.y - ca.y) * t, nearPlane)
        } else if cb.z < nearPlane {
            let t = (nearPlane - cb.z) / (ca.z - cb.z)
            cb = Vec3(cb.x + (ca.x - cb.x) * t, cb.y + (ca.y - cb.y) * t, nearPlane)
        }
        return (projectCam(ca), projectCam(cb))
    }
}

/// Deterministic hash noise in 0..<1.
func hash01(_ n: Int) -> Double {
    var x = UInt64(bitPattern: Int64(n)) &* 0x9E37_79B9_7F4A_7C15
    x ^= x >> 31
    x = x &* 0xBF58_476D_1CE4_E5B9
    x ^= x >> 27
    return Double(x % 1_000_000) / 1_000_000
}

func path(_ pts: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: pts)
    p.closeSubpath()
    return p
}
