// Koi — a procedural fish. The head steers; the body is a chain of points that
// follows it at a fixed spacing, which produces natural S-shaped swimming.
// The body (outline, patches, eyes) is painted once into a straight texture,
// clipped to the fish outline, then bent along the spine with a warp grid.

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

    static func make(size: CGSize, draw: @escaping (CGContext, CGRect) -> Void) -> SKTexture {
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

    private static let segmentCount = 18

    private var spine: [CGPoint]
    /// Spine plus the swimming wave, used only for drawing: the head stays steady,
    /// the sideways sway grows toward the tail.
    private var pose: [CGPoint] = []
    private var heading: CGFloat
    private let spacing: CGFloat
    private let radii: [CGFloat]

    private let body: SKSpriteNode
    private let shadow: SKSpriteNode
    /// Body texture layout: x of each spine point (head = index 0), and total size.
    private let segmentX: [CGFloat]
    private let textureSize: CGSize
    private var pectoral: [SKSpriteNode] = []
    private var tail: [SKSpriteNode] = []

    private let seed: CGFloat
    private let baseSpeed: CGFloat
    private let shadowOffset: CGVector
    private var swimPhase: CGFloat = 0
    /// Smoothed turn rate; bends the whole body toward the turn so it curves as one C.
    private var bend: CGFloat = 0
    private var time: CGFloat = 0
    private var lure: CGPoint?
    private var lureUntil: CGFloat = 0

    var head: CGPoint { spine[0] }

    /// How close the mouth must get to eat something.
    var reach: CGFloat { spacing * 2.2 }

    /// Swim for food at `point`; renewed every frame while it lasts.
    func chase(_ point: CGPoint) {
        lure = point
        lureUntil = time + 1.5
    }

    /// Something landed on the water: swim over for a few seconds if it's close enough.
    func notice(_ point: CGPoint, reach: CGFloat) {
        guard hypot(point.x - head.x, point.y - head.y) < reach else { return }
        lure = point
        lureUntil = time + .random(in: 3.5...5.5)
    }

    /// depth 0 = near the surface (bright, far shadow), 1 = deep (dimmer, shadow close).
    init(at position: CGPoint, scale s: CGFloat, depth: CGFloat, variety v: KoiVariety, water: SKColor) {
        seed = .random(in: 0...1000)
        baseSpeed = .random(in: 38...58) * s
        let startHeading = CGFloat.random(in: 0..<(2 * .pi)), gap = 6.5 * s
        heading = startHeading
        spacing = gap
        shadowOffset = CGVector(dx: 16 * (1 - depth * 0.6), dy: -22 * (1 - depth * 0.6))

        let n = Self.segmentCount
        radii = (0..<n).map { i in
            let t = CGFloat(i) / CGFloat(n - 1)
            let shape = t < 0.25 ? 0.72 + 0.28 * sin(t / 0.25 * .pi / 2) : pow(1 - (t - 0.25) / 0.75, 1.3) * 0.8 + 0.2
            return 15 * s * shape
        }
        spine = (0..<n).map { i in
            CGPoint(x: position.x - cos(startHeading) * CGFloat(i) * gap,
                    y: position.y - sin(startHeading) * CGFloat(i) * gap)
        }

        // Deeper fish fade toward the water colour, baked into the texture.
        let fade = depth * Depth.koiFade
        func tint(_ c: SKColor) -> SKColor { c.blended(withFraction: fade, of: water) ?? c }

        func sprite(_ tex: SKTexture, _ color: SKColor, alpha: CGFloat = 1, z: CGFloat) -> SKSpriteNode {
            let sp = SKSpriteNode(texture: tex)
            sp.color = color
            sp.colorBlendFactor = 1
            sp.alpha = alpha
            sp.zPosition = z
            return sp
        }

        let finColor = tint(v.base == KoiVariety.black ? v.base.blended(withFraction: 0.15, of: .white)! : v.base)

        for side in [-1.0, 1.0] as [CGFloat] {
            let fin = sprite(Textures.fin, finColor, alpha: v.finAlpha, z: 0)
            fin.anchorPoint = CGPoint(x: 0, y: 0.5)
            fin.size = CGSize(width: 24 * s, height: 13 * s)
            fin.userData = ["side": side]
            pectoral.append(fin)

            let t = sprite(Textures.fin, finColor, alpha: v.finAlpha, z: 0)
            t.anchorPoint = CGPoint(x: 0, y: 0.5)
            t.size = CGSize(width: 40 * s, height: 20 * s)
            t.userData = ["side": side]
            tail.append(t)
        }

        let art = KoiArt(radii: radii, spacing: gap, variety: v, tint: tint)
        segmentX = art.segmentX
        textureSize = art.size

        body = SKSpriteNode(texture: art.body)
        body.size = art.size
        body.zPosition = 1

        shadow = SKSpriteNode(texture: art.shadow)
        shadow.size = art.size
        shadow.alpha = 0.32

        (pectoral + tail + [body]).forEach(node.addChild)
        shadowNode.addChild(shadow)
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

        // Head for the lure, faster at first, and lose interest on arrival.
        var boost: CGFloat = 1
        if let target = lure {
            let d = hypot(target.x - p.x, target.y - p.y)
            if time > lureUntil || d < spacing * 2 {
                lure = nil
            } else {
                turn += angleDiff(atan2(target.y - p.y, target.x - p.x), heading) * 2.4
                boost = 1 + min(1, (lureUntil - time) / 3) * 0.9
            }
        }

        // A koi can't spin on the spot: cap how fast the head turns (faster while chasing food).
        let maxTurn: CGFloat = lure == nil ? 0.8 : 1.3
        turn = max(-maxTurn, min(maxTurn, turn))
        heading += turn * dt
        bend += (max(-0.8, min(0.8, turn)) - bend) * min(1, dt * 3)
        let speed = baseSpeed * boost * (0.75 + 0.35 * sin(time * 0.21 + seed * 0.5))
        swimPhase += dt * speed * 0.09

        // The head swings slightly side to side; the chain turns that into a wave down the body.
        let swing = heading + sin(swimPhase) * 0.06
        spine[0].x += cos(swing) * speed * dt
        spine[0].y += sin(swing) * speed * dt

        // Skeleton: each segment follows the one ahead at a fixed spacing, and each joint
        // may bend only a little relative to the segment before it. The front of the body
        // is stiffer than the tail, so the whole fish curves at most about 95°.
        var previous = heading
        let n = spine.count
        for i in 1..<n {
            let dx = spine[i - 1].x - spine[i].x, dy = spine[i - 1].y - spine[i].y
            var a = hypot(dx, dy) > 0.0001 ? atan2(dy, dx) : previous
            let t = CGFloat(i) / CGFloat(n - 1)
            let limit = 0.05 + 0.1 * t
            a = previous + max(-limit, min(limit, angleDiff(a, previous)))
            spine[i].x = spine[i - 1].x - cos(a) * spacing
            spine[i].y = spine[i - 1].y - sin(a) * spacing
            previous = a
        }
        layout()
    }

    private func angle(at i: Int) -> CGFloat {
        let a = i == 0 ? pose[0] : pose[i - 1]
        let b = i == 0 ? pose[1] : pose[i]
        return atan2(a.y - b.y, a.x - b.x)
    }

    private func layout() {
        let n = spine.count
        pose = spine
        for i in 1..<n {
            let t = CGFloat(i) / CGFloat(n - 1)
            let a = atan2(spine[i - 1].y - spine[i].y, spine[i - 1].x - spine[i].x)
            let sway = (sin(swimPhase - t * 3.0) * 0.5 + bend * 0.7) * spacing * t * t
            pose[i] = CGPoint(x: spine[i].x - sin(a) * sway, y: spine[i].y + cos(a) * sway)
        }
        warpBody()
        // Pectoral fins: at segment 3, sweeping backward and paddling gently.
        let a3 = angle(at: 3)
        let paddle = sin(swimPhase * 0.5) * 0.25
        for fin in pectoral {
            let side = fin.userData?["side"] as? CGFloat ?? 1
            fin.position = CGPoint(x: pose[3].x - sin(a3) * radii[3] * 0.7 * side,
                                   y: pose[3].y + cos(a3) * radii[3] * 0.7 * side)
            fin.zRotation = a3 + .pi + side * (-1.05 + paddle * side)
        }

        // Tail: two lobes from the last segment, following the body's wave.
        let last = spine.count - 1
        let aTail = angle(at: last)
        let flap = sin(swimPhase - 1.2) * 0.15
        for t in tail {
            let side = t.userData?["side"] as? CGFloat ?? 1
            t.position = pose[last]
            t.zRotation = aTail + .pi + side * 0.32 + flap
        }
    }
}

extension Koi {
    /// Bends the straight body texture along the spine. Grid columns sit at the
    /// texture's tail edge, each spine point, and the head edge; three rows span
    /// the width. Each column is laid out perpendicular to the spine there.
    fileprivate func warpBody() {
        let n = spine.count
        let center = pose[n / 2]
        body.position = center
        let o = Depth.offset(shadowOffset)
        shadow.position = CGPoint(x: center.x + o.dx, y: center.y + o.dy)
        shadow.alpha = 0.32 * Depth.shadowAlpha
        shadow.setScale(Depth.shadowSpread)

        // Columns from tail edge (u = 0) to head edge (u = 1).
        var columns: [(point: CGPoint, angle: CGFloat, u: CGFloat)] = []
        let tailAngle = angle(at: n - 1)
        let tailExtra = segmentX[n - 1]
        columns.append((CGPoint(x: pose[n - 1].x - cos(tailAngle) * tailExtra,
                                y: pose[n - 1].y - sin(tailAngle) * tailExtra), tailAngle, 0))
        for i in stride(from: n - 1, through: 0, by: -1) {
            columns.append((pose[i], angle(at: i), segmentX[i] / textureSize.width))
        }
        let headAngle = angle(at: 0)
        let headExtra = textureSize.width - segmentX[0]
        columns.append((CGPoint(x: pose[0].x + cos(headAngle) * headExtra,
                                y: pose[0].y + sin(headAngle) * headExtra), headAngle, 1))

        let rows: [CGFloat] = [0, 0.5, 1]
        var source: [vector_float2] = []
        var dest: [vector_float2] = []
        source.reserveCapacity(columns.count * rows.count)
        dest.reserveCapacity(columns.count * rows.count)
        for v in rows {
            for c in columns {
                let off = (v - 0.5) * textureSize.height
                let x = c.point.x - sin(c.angle) * off
                let y = c.point.y + cos(c.angle) * off
                source.append(vector_float2(Float(c.u), Float(v)))
                dest.append(vector_float2(Float((x - center.x) / textureSize.width + 0.5),
                                          Float((y - center.y) / textureSize.height + 0.5)))
            }
        }
        let grid = SKWarpGeometryGrid(columns: columns.count - 1, rows: rows.count - 1,
                                      sourcePositions: source, destinationPositions: dest)
        body.warpGeometry = grid
        shadow.warpGeometry = grid
    }
}

// MARK: - Body art

/// Paints a straight koi (head on the right) into a body texture and a soft shadow texture.
struct KoiArt {
    let body: SKTexture
    let shadow: SKTexture
    let size: CGSize
    let segmentX: [CGFloat]

    init(radii: [CGFloat], spacing: CGFloat, variety v: KoiVariety, tint: (SKColor) -> SKColor) {
        let n = radii.count
        let pad = (radii.max() ?? 10) * 0.9   // room for the shadow blur
        let maxR = radii.max() ?? 10
        let tailX = pad + radii[n - 1]
        let segmentX = (0..<n).map { tailX + CGFloat(n - 1 - $0) * spacing }
        let size = CGSize(width: segmentX[0] + radii[0] * 1.15 + pad, height: maxR * 2 + pad * 2)
        self.segmentX = segmentX
        self.size = size
        let cy = size.height / 2

        // Outline: smooth curve through the segment edges, plus round head and tail caps.
        let spine = CGMutablePath()
        let top = (0..<n).reversed().map { CGPoint(x: segmentX[$0], y: cy + radii[$0]) }
        let bottom = (0..<n).map { CGPoint(x: segmentX[$0], y: cy - radii[$0]) }
        let ring = top + bottom
        spine.move(to: mid(ring[ring.count - 1], ring[0]))
        for k in 0..<ring.count {
            spine.addQuadCurve(to: mid(ring[k], ring[(k + 1) % ring.count]), control: ring[k])
        }
        spine.closeSubpath()
        let head = CGPath(ellipseIn: CGRect(x: segmentX[0] - radii[0] * 1.15, y: cy - radii[0],
                                            width: radii[0] * 2.3, height: radii[0] * 2), transform: nil)
        let tailCap = CGPath(ellipseIn: CGRect(x: segmentX[n - 1] - radii[n - 1], y: cy - radii[n - 1],
                                               width: radii[n - 1] * 2, height: radii[n - 1] * 2), transform: nil)
        // One merged silhouette, so the edge shading only follows the true outer edge.
        let outline = spine.union(head).union(tailCap)

        // Patches: a few organic blobs, each built from overlapping ellipses.
        var patches: [(SKColor, [CGRect])] = []
        if !v.spots.isEmpty {
            let count = Int((Double(n) * v.spotChance * 0.35).rounded()) + 1
            for _ in 0..<count {
                let i = Int.random(in: 0...(n - 5))
                let r = radii[i]
                let c = CGPoint(x: segmentX[i] + .random(in: -spacing...spacing), y: cy + .random(in: -r * 0.7...r * 0.7))
                let blob = (0..<Int.random(in: 2...4)).map { _ -> CGRect in
                    let w = r * .random(in: 0.7...1.4), h = r * .random(in: 0.6...1.2)
                    return CGRect(x: c.x + .random(in: -r * 0.5...r * 0.5) - w / 2,
                                  y: c.y + .random(in: -r * 0.4...r * 0.4) - h / 2, width: w, height: h)
                }
                patches.append((tint(v.spots.randomElement()!), blob))
            }
        }

        let base = tint(v.base)
        let eyeColor = tint(KoiVariety.black)
        let eyeR = radii[0] * 0.14
        let eyeX = segmentX[0] + radii[0] * 0.45

        let bodyTexture = Textures.make(size: size) { ctx, _ in
            ctx.addPath(outline)
            ctx.clip()
            ctx.setFillColor(base.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            for (color, blob) in patches {
                ctx.setFillColor(color.cgColor)
                blob.forEach { ctx.fillEllipse(in: $0) }
            }
            // Soft edge shading so the body reads as rounded, clipped to the outline.
            ctx.addPath(outline)
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
            ctx.setLineWidth(maxR * 0.35)
            ctx.strokePath()
            ctx.setFillColor(eyeColor.cgColor)
            for side in [-1.0, 1.0] as [CGFloat] {
                ctx.fillEllipse(in: CGRect(x: eyeX - eyeR, y: cy + side * radii[0] * 0.55 - eyeR,
                                           width: eyeR * 2, height: eyeR * 2))
            }
        }

        // Shadow: draw the outline far off-canvas so only its blurred shadow lands inside.
        let far = size.height * 4
        let shadowTexture = Textures.make(size: size) { ctx, _ in
            ctx.setShadow(offset: CGSize(width: 0, height: -far), blur: pad * 0.8 * Depth.shadowBlur, color: CGColor(gray: 0, alpha: 1))
            ctx.translateBy(x: 0, y: far)
            ctx.addPath(outline)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fillPath()
        }
        body = bodyTexture
        shadow = shadowTexture
    }
}

private func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

private func angleDiff(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    var d = a - b
    while d > .pi { d -= 2 * .pi }
    while d < -.pi { d += 2 * .pi }
    return d
}
