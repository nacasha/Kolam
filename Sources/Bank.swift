// Bank — the pond's shape: a grassy bank with a stone edge around the water,
// plus reeds and cattails growing along the edge.

import SpriteKit

enum PondShape: String { case full, rounded, natural }

/// Where the water is. `path` is nil when the water fills the screen.
struct PondGeometry {
    let bounds: CGRect
    let path: CGPath?
    /// Area fish, pads and creatures keep to.
    let swimRect: CGRect
    /// Closed outline, counter-clockwise (only for shaped ponds).
    private let outline: [CGPoint]

    init(shape: PondShape, size: CGSize) {
        bounds = CGRect(origin: .zero, size: size)
        switch shape {
        case .full:
            path = nil
            swimRect = bounds
            outline = []
        case .rounded, .natural:
            let natural = shape == .natural
            let rx = size.width * (natural ? 0.46 : 0.44), ry = size.height * (natural ? 0.43 : 0.40)
            let c = CGPoint(x: bounds.midX, y: bounds.midY)
            // Superellipse: squarish enough to use the wide screen, with a wobbly
            // shoreline when natural.
            let n: CGFloat = natural ? 3.2 : 5
            let s1 = CGFloat.random(in: 0...6), s2 = CGFloat.random(in: 0...6)
            let points = (0..<240).map { k -> CGPoint in
                let t = CGFloat(k) / 240 * 2 * .pi
                let ct = cos(t), st = sin(t)
                var r = pow(pow(abs(ct) / rx, n) + pow(abs(st) / ry, n), -1 / n)
                if natural { r *= 1 + 0.06 * sin(3 * t + s1) + 0.035 * sin(5 * t + s2) + 0.02 * sin(9 * t) }
                return CGPoint(x: c.x + ct * r, y: c.y + st * r)
            }
            outline = points
            let p = CGMutablePath()
            p.addLines(between: points)
            p.closeSubpath()
            path = p
            swimRect = CGRect(x: c.x - rx * 0.86, y: c.y - ry * 0.82, width: rx * 1.72, height: ry * 1.64)
        }
    }

    func contains(_ p: CGPoint) -> Bool { path?.contains(p) ?? true }

    /// Evenly spaced points along the water's edge, with the outward direction.
    func edge(step: CGFloat) -> [(point: CGPoint, out: CGFloat)] {
        if outline.isEmpty {
            // Full screen: walk the screen border.
            var result: [(CGPoint, CGFloat)] = []
            let b = bounds
            for x in stride(from: b.minX, through: b.maxX, by: step) {
                result.append((CGPoint(x: x, y: b.minY), -.pi / 2))
                result.append((CGPoint(x: x, y: b.maxY), .pi / 2))
            }
            for y in stride(from: b.minY + step, through: b.maxY - step, by: step) {
                result.append((CGPoint(x: b.minX, y: y), .pi))
                result.append((CGPoint(x: b.maxX, y: y), 0))
            }
            return result
        }
        var result: [(CGPoint, CGFloat)] = []
        var carry: CGFloat = 0
        let n = outline.count
        for k in 0..<n {
            let a = outline[k], b = outline[(k + 1) % n]
            let len = hypot(b.x - a.x, b.y - a.y)
            let out = atan2(-(b.x - a.x), b.y - a.y)
            var d = step - carry
            while d <= len {
                let t = d / len
                result.append((CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), out))
                d += step
            }
            carry = len - (d - step)
        }
        return result
    }
}

enum Bank {
    /// Grass around the water, a muddy rim, a ring of stones, and the bank's
    /// shadow falling onto the water.
    static func build(_ geo: PondGeometry, unit u: CGFloat) -> SKNode? {
        guard let pond = geo.path else { return nil }
        let size = geo.bounds.size
        let edge = geo.edge(step: 21 * u)
        let lightOffset = Depth.offset(CGVector(dx: 10 * u, dy: -14 * u))

        let texture = Textures.make(size: size) { ctx, r in
            let land = CGMutablePath()
            land.addRect(r)
            land.addPath(pond)

            // Bank shadow onto the water.
            ctx.saveGState()
            ctx.addPath(pond)
            ctx.clip()
            ctx.setShadow(offset: CGSize(width: lightOffset.dx, height: lightOffset.dy), blur: 22 * u * Depth.shadowBlur,
                          color: CGColor(gray: 0, alpha: min(1, 0.6 * Depth.shadowAlpha)))
            ctx.addPath(land)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()

            // Grass.
            ctx.saveGState()
            ctx.addPath(land)
            ctx.clip(using: .evenOdd)
            ctx.setFillColor(CGColor(red: 0.21, green: 0.33, blue: 0.16, alpha: 1))
            ctx.fill(r)
            let area = r.width * r.height
            for _ in 0..<Int(area / 3000) {
                let light = Bool.random()
                ctx.setFillColor(CGColor(red: light ? 0.36 : 0.10, green: light ? 0.50 : 0.20, blue: light ? 0.22 : 0.08,
                                         alpha: .random(in: 0.05...0.14)))
                let rr = CGFloat.random(in: 20...110) * u
                ctx.fillEllipse(in: CGRect(x: .random(in: r.minX...r.maxX) - rr, y: .random(in: r.minY...r.maxY) - rr,
                                           width: rr * 2, height: rr * 1.6))
            }
            ctx.setLineCap(.round)
            for _ in 0..<Int(area / 45) {
                let x = CGFloat.random(in: r.minX...r.maxX), y = CGFloat.random(in: r.minY...r.maxY)
                let a = CGFloat.pi / 2 + .random(in: -0.6...0.6), l = CGFloat.random(in: 5...13) * u
                let g = CGFloat.random(in: 0.3...0.62)
                ctx.setStrokeColor(CGColor(red: g * 0.62, green: g, blue: g * 0.4, alpha: .random(in: 0.35...0.8)))
                ctx.setLineWidth(.random(in: 0.8...1.8) * u)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l))
                ctx.strokePath()
            }
            // Muddy rim right at the waterline.
            ctx.addPath(pond)
            ctx.setStrokeColor(CGColor(red: 0.25, green: 0.20, blue: 0.13, alpha: 0.95))
            ctx.setLineWidth(18 * u)
            ctx.strokePath()
            ctx.restoreGState()

            // Stones straddling the edge: shadow, body, highlight.
            for e in edge {
                let rr = CGFloat.random(in: 7...14) * u
                let p = CGPoint(x: e.point.x + cos(e.out) * rr * 0.3, y: e.point.y + sin(e.out) * rr * 0.3)
                let rect = CGRect(x: p.x - rr, y: p.y - rr * 0.8, width: rr * 2, height: rr * .random(in: 1.4...1.8))
                ctx.setFillColor(CGColor(gray: 0, alpha: 0.35 * Depth.shadowAlpha))
                ctx.fillEllipse(in: rect.offsetBy(dx: lightOffset.dx * 0.35, dy: lightOffset.dy * 0.35))
                let g = CGFloat.random(in: 0.38...0.6)
                ctx.setFillColor(CGColor(red: g, green: g * 0.97, blue: g * 0.9, alpha: 1))
                ctx.fillEllipse(in: rect)
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.18))
                ctx.fillEllipse(in: rect.insetBy(dx: rr * 0.45, dy: rr * 0.4).offsetBy(dx: -rr * 0.2, dy: rr * 0.2))
            }
        }

        let node = SKSpriteNode(texture: texture)
        node.anchorPoint = .zero
        node.size = size
        node.zPosition = 1020
        return node
    }
}

enum Reeds {
    static func build(_ geo: PondGeometry, unit u: CGFloat, amount: CGFloat, cattails: Bool) -> SKNode {
        let root = SKNode()
        root.zPosition = 1040
        let edge = geo.edge(step: 12 * u)
        guard !edge.isEmpty else { return root }
        // Clumps come in stands: pick stand centres along the edge, then scatter clumps around each.
        let stands = max(3, Int(CGFloat(edge.count) * 12 * u / (420 * u) * amount))
        for _ in 0..<stands {
            let base = Int.random(in: 0..<edge.count)
            for _ in 0..<Int.random(in: 2...5) {
                let e = edge[(base + Int.random(in: -8...8) + edge.count) % edge.count]
                let inward = CGFloat.random(in: -18...10) * u
                let p = CGPoint(x: e.point.x - cos(e.out) * inward, y: e.point.y - sin(e.out) * inward)
                root.addChild(clump(at: p, out: e.out, unit: u, cattails: cattails && .random(in: 0...1) < 0.45))
            }
        }
        return root
    }

    /// Seen from above: blades fanning out from a base, leaning away from the water,
    /// with cattail heads on a few stalks. The whole clump sways in the wind.
    private static func clump(at p: CGPoint, out: CGFloat, unit u: CGFloat, cattails: Bool) -> SKNode {
        let clump = SKNode()
        clump.position = p
        let greens: [SKColor] = [
            SKColor(red: 0.30, green: 0.48, blue: 0.20, alpha: 1),
            SKColor(red: 0.38, green: 0.55, blue: 0.24, alpha: 1),
            SKColor(red: 0.46, green: 0.56, blue: 0.26, alpha: 1),
            SKColor(red: 0.55, green: 0.58, blue: 0.30, alpha: 1),
        ]
        let o = Depth.offset(CGVector(dx: 14 * u, dy: -18 * u))
        let shadowAlpha = 0.22 * Depth.shadowAlpha

        func blade(_ tex: SKTexture, _ color: SKColor, length: CGFloat, width: CGFloat, angle: CGFloat, z: CGFloat) {
            for isShadow in [true, false] {
                let b = SKSpriteNode(texture: tex)
                b.color = isShadow ? .black : color
                b.colorBlendFactor = 1
                b.alpha = isShadow ? shadowAlpha : 1
                b.anchorPoint = CGPoint(x: 0, y: 0.5)
                b.size = CGSize(width: length, height: width)
                b.zRotation = angle
                b.position = isShadow ? CGPoint(x: o.dx, y: o.dy) : .zero
                b.zPosition = isShadow ? -1 : z
                clump.addChild(b)
            }
        }

        for k in 0..<Int.random(in: 8...15) {
            let a = out + .random(in: -1.4...1.4)
            blade(Textures.leaf, greens.randomElement()!, length: .random(in: 55...125) * u,
                  width: .random(in: 5...8) * u, angle: a, z: CGFloat(k) * 0.01)
        }

        if cattails {
            let brown = SKColor(red: 0.42, green: 0.26, blue: 0.14, alpha: 1)
            for _ in 0..<Int.random(in: 1...3) {
                let a = out + .random(in: -0.8...0.8)
                let len = CGFloat.random(in: 90...140) * u
                blade(Textures.leaf, SKColor(red: 0.36, green: 0.44, blue: 0.22, alpha: 1), length: len, width: 3.2 * u, angle: a, z: 1)
                // Head: a brown capsule near the stalk's tip.
                let head = SKSpriteNode(texture: Textures.circle)
                head.color = brown
                head.colorBlendFactor = 1
                head.size = CGSize(width: 28 * u, height: 9.5 * u)
                head.zRotation = a
                head.position = CGPoint(x: cos(a) * len * 0.78, y: sin(a) * len * 0.78)
                head.zPosition = 2
                let headShadow = SKSpriteNode(texture: Textures.circle)
                headShadow.color = .black
                headShadow.colorBlendFactor = 1
                headShadow.alpha = shadowAlpha
                headShadow.size = head.size
                headShadow.zRotation = a
                headShadow.position = CGPoint(x: head.position.x + o.dx * 1.6, y: head.position.y + o.dy * 1.6)
                headShadow.zPosition = -1
                clump.addChild(headShadow)
                clump.addChild(head)
            }
        }

        let sway = SKAction.rotate(byAngle: .random(in: 0.025...0.05), duration: .random(in: 2.2...3.6))
        sway.timingMode = .easeInEaseOut
        clump.run(.sequence([.wait(forDuration: .random(in: 0...2)), .repeatForever(.sequence([sway, sway.reversed()]))]))
        return clump
    }
}
