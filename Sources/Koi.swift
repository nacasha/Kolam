// Koi — a procedural fish. The head steers; the body is a chain of points that
// follows it at a fixed spacing, which produces natural S-shaped swimming.
// Everything is drawn with a few shared white textures tinted per sprite, so
// SpriteKit batches all fish into a handful of draw calls.

import SpriteKit

// MARK: - Textures

enum Textures {
    static let circle = make(size: CGSize(width: 64, height: 64)) { ctx, r in
        ctx.fillEllipse(in: r.insetBy(dx: 1, dy: 1))
    }

    static let softCircle = make(size: CGSize(width: 64, height: 64)) { ctx, r in
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        let c = CGPoint(x: r.midX, y: r.midY)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: r.width / 2, options: [])
    }

    /// Teardrop fin pointing along +x, widest near its tip.
    static let fin = make(size: CGSize(width: 64, height: 32)) { ctx, r in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: r.midY))
        path.addCurve(to: CGPoint(x: r.maxX, y: r.midY),
                      control1: CGPoint(x: r.width * 0.35, y: r.maxY + 4), control2: CGPoint(x: r.maxX, y: r.maxY))
        path.addCurve(to: CGPoint(x: 0, y: r.midY),
                      control1: CGPoint(x: r.maxX, y: r.minY), control2: CGPoint(x: r.width * 0.35, y: r.minY - 4))
        ctx.addPath(path)
        ctx.fillPath()
    }

    private static func make(size: CGSize, draw: @escaping (CGContext, CGRect) -> Void) -> SKTexture {
        let image = NSImage(size: size, flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.setFillColor(.white)
            draw(ctx, rect)
            return true
        }
        return SKTexture(image: image)
    }
}

// MARK: - Varieties

struct KoiVariety {
    let base: SKColor
    let spots: [SKColor]
    let spotChance: Double
    let finAlpha: CGFloat

    static let white = SKColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1)
    static let red = SKColor(red: 0.86, green: 0.25, blue: 0.11, alpha: 1)
    static let orange = SKColor(red: 0.96, green: 0.53, blue: 0.14, alpha: 1)
    static let gold = SKColor(red: 0.97, green: 0.78, blue: 0.36, alpha: 1)
    static let black = SKColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)

    static let all: [KoiVariety] = [
        KoiVariety(base: white, spots: [red], spotChance: 0.65, finAlpha: 0.55),        // kohaku
        KoiVariety(base: white, spots: [red, black], spotChance: 0.6, finAlpha: 0.55),  // sanke
        KoiVariety(base: black, spots: [red, white], spotChance: 0.55, finAlpha: 0.6),  // showa
        KoiVariety(base: orange, spots: [], spotChance: 0, finAlpha: 0.5),              // orenji ogon
        KoiVariety(base: gold, spots: [white], spotChance: 0.25, finAlpha: 0.5),        // yamabuki
        KoiVariety(base: white, spots: [orange], spotChance: 0.5, finAlpha: 0.5),       // kujaku-ish
    ]
}

// MARK: - Koi

final class Koi {
    let node = SKNode()
    let shadowNode = SKNode()

    private static let segmentCount = 14

    private var spine: [CGPoint]
    private var heading: CGFloat
    private let spacing: CGFloat
    private let radii: [CGFloat]

    private var body: [SKSpriteNode] = []
    private var shadows: [SKSpriteNode] = []
    private var spots: [(sprite: SKSpriteNode, segment: Int, offset: CGFloat)] = []
    private var eyes: [SKSpriteNode] = []
    private var pectoral: [SKSpriteNode] = []
    private var tail: [SKSpriteNode] = []

    private let seed: CGFloat
    private let baseSpeed: CGFloat
    private let shadowOffset: CGVector
    private var swimPhase: CGFloat = 0
    private var time: CGFloat = 0

    var head: CGPoint { spine[0] }

    /// depth 0 = near the surface (bright, far shadow), 1 = deep (dimmer, shadow close).
    init(at position: CGPoint, scale s: CGFloat, depth: CGFloat, variety v: KoiVariety, water: SKColor) {
        seed = .random(in: 0...1000)
        baseSpeed = .random(in: 38...58) * s
        let startHeading = CGFloat.random(in: 0..<(2 * .pi)), gap = 8.5 * s
        heading = startHeading
        spacing = gap
        shadowOffset = CGVector(dx: 16 * (1 - depth * 0.6), dy: -22 * (1 - depth * 0.6))

        let n = Self.segmentCount
        radii = (0..<n).map { i in
            let t = CGFloat(i) / CGFloat(n - 1)
            let shape = t < 0.28 ? 0.78 + 0.22 * (t / 0.28) : pow(1 - (t - 0.28) / 0.72, 1.15) * 0.88 + 0.12
            return 15 * s * shape
        }
        spine = (0..<n).map { i in
            CGPoint(x: position.x - cos(startHeading) * CGFloat(i) * gap,
                    y: position.y - sin(startHeading) * CGFloat(i) * gap)
        }

        // Deeper fish fade toward the water colour instead of using alpha,
        // so the overlapping body circles never show seams.
        let fade = depth * 0.38
        func tint(_ c: SKColor) -> SKColor { c.blended(withFraction: fade, of: water) ?? c }

        func sprite(_ tex: SKTexture, _ color: SKColor, alpha: CGFloat = 1, z: CGFloat) -> SKSpriteNode {
            let sp = SKSpriteNode(texture: tex)
            sp.color = color
            sp.colorBlendFactor = 1
            sp.alpha = alpha
            sp.zPosition = z
            return sp
        }

        let finColor = tint(v.base == KoiVariety.black ? KoiVariety.black : v.base.blended(withFraction: 0.25, of: .white)!)

        for side in [-1.0, 1.0] as [CGFloat] {
            let fin = sprite(Textures.fin, finColor, alpha: v.finAlpha, z: 0)
            fin.anchorPoint = CGPoint(x: 0, y: 0.5)
            fin.size = CGSize(width: 22 * s, height: 11 * s)
            fin.userData = ["side": side]
            pectoral.append(fin)

            let t = sprite(Textures.fin, finColor, alpha: v.finAlpha, z: 0)
            t.anchorPoint = CGPoint(x: 0, y: 0.5)
            t.size = CGSize(width: 34 * s, height: 16 * s)
            t.userData = ["side": side]
            tail.append(t)
        }

        for i in 0..<n {
            let b = sprite(Textures.circle, tint(v.base), z: 1)
            b.size = CGSize(width: radii[i] * 2, height: radii[i] * 2)
            body.append(b)

            if i % 2 == 0 {
                let sh = sprite(Textures.softCircle, .black, alpha: 0.2, z: 0)
                sh.size = CGSize(width: radii[i] * 3, height: radii[i] * 3)
                shadows.append(sh)
            }

            // Patches: 1–2 blobs on some segments, kept inside the body outline.
            if let color = v.spots.randomElement(), i < n - 3, Double.random(in: 0...1) < v.spotChance {
                for _ in 0..<Int.random(in: 1...2) {
                    let r = radii[i] * .random(in: 0.45...0.8)
                    let maxOffset = radii[i] - r
                    let spot = sprite(Textures.circle, tint(color), z: 2)
                    spot.size = CGSize(width: r * 2, height: r * 2.4)
                    spots.append((spot, i, .random(in: -maxOffset...maxOffset)))
                }
            }
        }

        for _ in 0..<2 {
            let e = sprite(Textures.circle, tint(KoiVariety.black), z: 3)
            e.size = CGSize(width: 3.2 * s, height: 3.2 * s)
            eyes.append(e)
        }

        (pectoral + tail + body + spots.map(\.sprite) + eyes).forEach(node.addChild)
        shadows.forEach(shadowNode.addChild)
        layout()
    }

    // MARK: Simulation

    func update(dt: CGFloat, bounds: CGRect, others: [Koi]) {
        time += dt

        // Wander: two slow sine waves give a smooth, non-repeating turn rate.
        var turn = sin(time * 0.31 + seed) * 0.45 + sin(time * 0.13 + seed * 1.7) * 0.35

        // Steer back toward the middle when close to an edge (fish may drift partly off-screen).
        let margin: CGFloat = min(bounds.width, bounds.height) * 0.18
        let p = spine[0]
        let edge = min(p.x - bounds.minX, bounds.maxX - p.x, p.y - bounds.minY, bounds.maxY - p.y)
        if edge < margin {
            let toCenter = atan2(bounds.midY - p.y, bounds.midX - p.x)
            turn += angleDiff(toCenter, heading) * (1 - max(edge, -margin) / margin) * 1.6
        }

        // Keep a little distance from other koi.
        for other in others where other !== self {
            let d = hypot(other.head.x - p.x, other.head.y - p.y)
            let minDist = spacing * 11
            if d < minDist, d > 0.01 {
                let away = atan2(p.y - other.head.y, p.x - other.head.x)
                turn += angleDiff(away, heading) * (1 - d / minDist) * 1.2
            }
        }

        heading += turn * dt
        let speed = baseSpeed * (0.75 + 0.35 * sin(time * 0.21 + seed * 0.5))
        swimPhase += dt * speed * 0.16

        // The head swings slightly side to side; the chain turns that into a wave down the body.
        let swing = heading + sin(swimPhase) * 0.32
        spine[0].x += cos(swing) * speed * dt
        spine[0].y += sin(swing) * speed * dt

        for i in 1..<spine.count {
            let dx = spine[i - 1].x - spine[i].x, dy = spine[i - 1].y - spine[i].y
            let len = hypot(dx, dy)
            if len > 0.0001 {
                spine[i].x = spine[i - 1].x - dx / len * spacing
                spine[i].y = spine[i - 1].y - dy / len * spacing
            }
        }
        layout()
    }

    private func angle(at i: Int) -> CGFloat {
        let a = i == 0 ? spine[0] : spine[i - 1]
        let b = i == 0 ? spine[1] : spine[i]
        return atan2(a.y - b.y, a.x - b.x)
    }

    private func layout() {
        for i in 0..<spine.count {
            body[i].position = spine[i]
        }
        for (k, sh) in shadows.enumerated() {
            let i = k * 2
            sh.position = CGPoint(x: spine[i].x + shadowOffset.dx, y: spine[i].y + shadowOffset.dy)
        }
        for s in spots {
            let a = angle(at: s.segment)
            s.sprite.position = CGPoint(x: spine[s.segment].x - sin(a) * s.offset,
                                        y: spine[s.segment].y + cos(a) * s.offset)
            s.sprite.zRotation = a
        }

        let headAngle = angle(at: 1)
        for (k, e) in eyes.enumerated() {
            let side: CGFloat = k == 0 ? -1 : 1
            let r = radii[1] * 0.62
            e.position = CGPoint(x: spine[1].x - sin(headAngle) * r * side + cos(headAngle) * radii[1] * 0.35,
                                 y: spine[1].y + cos(headAngle) * r * side + sin(headAngle) * radii[1] * 0.35)
        }

        // Pectoral fins: at segment 3, sweeping backward and paddling gently.
        let a3 = angle(at: 3)
        let paddle = sin(swimPhase * 0.5) * 0.25
        for fin in pectoral {
            let side = fin.userData?["side"] as? CGFloat ?? 1
            fin.position = CGPoint(x: spine[3].x - sin(a3) * radii[3] * 0.7 * side,
                                   y: spine[3].y + cos(a3) * radii[3] * 0.7 * side)
            fin.zRotation = a3 + .pi + side * (-1.05 + paddle * side)
        }

        // Tail: two lobes from the last segment, following the body's wave.
        let last = spine.count - 1
        let aTail = angle(at: last)
        let flap = sin(swimPhase - 1.2) * 0.3
        for t in tail {
            let side = t.userData?["side"] as? CGFloat ?? 1
            t.position = spine[last]
            t.zRotation = aTail + .pi + side * 0.32 + flap
        }
    }
}

private func angleDiff(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    var d = a - b
    while d > .pi { d -= 2 * .pi }
    while d < -.pi { d += 2 * .pi }
    return d
}
