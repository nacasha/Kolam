// Reeds — reeds and cattails growing along the edges of the pond (the screen),
// and the pond's geometry they're placed on.

import SpriteKit

/// The water fills the screen; this gives the area creatures keep to and points
/// along the edges for plants.
struct PondGeometry {
    let bounds: CGRect
    var swimRect: CGRect { bounds }

    init(size: CGSize) {
        bounds = CGRect(origin: .zero, size: size)
    }

    /// Evenly spaced points along the screen border, with the outward direction.
    func edge(step: CGFloat) -> [(point: CGPoint, out: CGFloat)] {
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
}

enum Reeds {
    static func build(_ geo: PondGeometry, unit u: CGFloat, amount: CGFloat, cattails: Bool) -> SKNode {
        let root = SKNode()
        root.zPosition = 1040
        let edge = geo.edge(step: 12 * u)
        guard !edge.isEmpty else { return root }
        // Stands of reeds rooted just past the screen edge, leaning in over the water.
        // Corners get a stand each (they frame the pond best); the rest go at random spots.
        let b = geo.bounds
        let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                       CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)]
        var centres: [CGPoint] = corners
        let extra = max(0, Int((b.width + b.height) * 2 / (1100 * u) * amount) - 2)
        centres += (0..<extra).map { _ in edge.randomElement()!.point }
        for c in centres {
            // Clumps spread along the edge around the stand's centre.
            let near = edge.filter { hypot($0.point.x - c.x, $0.point.y - c.y) < 150 * u }
            for _ in 0..<Int.random(in: 3...6) {
                guard let e = near.randomElement() else { break }
                let outward = CGFloat.random(in: 4...26) * u
                let p = CGPoint(x: e.point.x + cos(e.out) * outward, y: e.point.y + sin(e.out) * outward)
                // Lean toward the pond centre, so corner stands fan diagonally inward.
                let inward = atan2(b.midY - p.y, b.midX - p.x)
                let lean = inward + angleDelta(e.out + .pi, inward) * 0.6
                root.addChild(clump(at: p, lean: lean, unit: u, cattails: cattails && .random(in: 0...1) < 0.45))
            }
        }
        return root
    }

    /// Seen from above: blades fanning out from a base toward `lean` (over the water),
    /// with cattail heads on a few stalks. The whole clump sways in the wind.
    private static func clump(at p: CGPoint, lean out: CGFloat, unit u: CGFloat, cattails: Bool) -> SKNode {
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
            let a = out + .random(in: -0.9...0.9)
            blade(Textures.leaf, greens.randomElement()!, length: .random(in: 55...125) * u,
                  width: .random(in: 5...8) * u, angle: a, z: CGFloat(k) * 0.01)
        }

        if cattails {
            let brown = SKColor(red: 0.42, green: 0.26, blue: 0.14, alpha: 1)
            for _ in 0..<Int.random(in: 1...3) {
                let a = out + .random(in: -0.5...0.5)
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
