// Surface — things floating on the water: lily pads, flowers, click ripples.

import SpriteKit

extension Textures {
    /// Round pad with a wedge cut out, like a real lily pad.
    static let pad = make(size: CGSize(width: 128, height: 128)) { ctx, r in
        let c = CGPoint(x: r.midX, y: r.midY)
        let path = CGMutablePath()
        path.move(to: c)
        path.addArc(center: c, radius: r.width / 2 - 1, startAngle: 0.28, endAngle: 2 * .pi - 0.02, clockwise: false)
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
        // Veins, cut slightly darker via alpha.
        ctx.setBlendMode(.destinationOut)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.22))
        ctx.setLineWidth(1.4)
        for k in 0..<9 {
            let a = 0.45 + CGFloat(k) * 0.64
            ctx.move(to: c)
            ctx.addLine(to: CGPoint(x: c.x + cos(a) * r.width * 0.46, y: c.y + sin(a) * r.width * 0.46))
        }
        ctx.strokePath()
    }

    static let petal = make(size: CGSize(width: 32, height: 64)) { ctx, r in
        ctx.fillEllipse(in: r.insetBy(dx: 2, dy: 1))
    }

    static let ring = make(size: CGSize(width: 128, height: 128)) { ctx, r in
        ctx.setStrokeColor(.white)
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: r.insetBy(dx: 3, dy: 3))
    }
}

// MARK: - Lily pad

final class LilyPad {
    let node = SKNode()
    let shadow: SKSpriteNode
    private let drift: CGVector
    private let spin: CGFloat
    private let seed = CGFloat.random(in: 0...1000)
    /// Current wave displacement, kept separate from the drift so bobbing never accumulates.
    private var bob = CGVector.zero

    let radius: CGFloat

    init(at position: CGPoint, radius: CGFloat, flower: Bool) {
        self.radius = radius
        let greens = [
            SKColor(red: 0.24, green: 0.45, blue: 0.20, alpha: 1),
            SKColor(red: 0.30, green: 0.52, blue: 0.24, alpha: 1),
            SKColor(red: 0.20, green: 0.38, blue: 0.19, alpha: 1),
        ]
        let pad = SKSpriteNode(texture: Textures.pad)
        pad.color = greens.randomElement()!
        pad.colorBlendFactor = 1
        pad.size = CGSize(width: radius * 2, height: radius * 2)
        node.addChild(pad)

        if flower {
            let petals = SKNode()
            let pink = SKColor(red: 0.98, green: 0.74, blue: 0.80, alpha: 1)
            for (count, len, alpha) in [(8, radius * 0.62, 0.92), (6, radius * 0.42, 1.0)] {
                for k in 0..<count {
                    let p = SKSpriteNode(texture: Textures.petal)
                    p.color = alpha < 1 ? pink : pink.blended(withFraction: 0.35, of: .white)!
                    p.colorBlendFactor = 1
                    p.alpha = alpha
                    p.anchorPoint = CGPoint(x: 0.5, y: 0.08)
                    p.size = CGSize(width: len * 0.5, height: len)
                    p.zRotation = CGFloat(k) / CGFloat(count) * 2 * .pi + (alpha < 1 ? 0 : 0.3)
                    petals.addChild(p)
                }
            }
            let center = SKSpriteNode(texture: Textures.circle)
            center.color = SKColor(red: 0.98, green: 0.84, blue: 0.35, alpha: 1)
            center.colorBlendFactor = 1
            center.size = CGSize(width: radius * 0.26, height: radius * 0.26)
            petals.addChild(center)
            center.zPosition = 1
            petals.position = CGPoint(x: radius * 0.1, y: -radius * 0.1)
            petals.zPosition = 1
            node.addChild(petals)
        }

        shadow = SKSpriteNode(texture: Textures.softCircle)
        shadow.color = .black
        shadow.colorBlendFactor = 1
        shadow.alpha = 0.35
        shadow.size = CGSize(width: radius * 2.6, height: radius * 2.6)

        node.position = position
        node.zRotation = .random(in: 0..<(2 * .pi))
        drift = CGVector(dx: .random(in: -3...3), dy: .random(in: -2...2))
        spin = .random(in: -0.03...0.03)
        update(dt: 0, time: 0, bounds: .infinite)
    }

    func update(dt: CGFloat, time: CGFloat, bounds: CGRect) {
        // Slow drift plus a gentle bob; wrap around so pads never pile up at an edge.
        node.position.x += (drift.dx + sin(time * 0.2 + seed) * 2) * dt
        node.position.y += (drift.dy + cos(time * 0.17 + seed) * 2) * dt
        node.zRotation += spin * dt
        if bounds != .infinite {
            let m: CGFloat = 120
            if node.position.x < bounds.minX - m { node.position.x = bounds.maxX + m }
            if node.position.x > bounds.maxX + m { node.position.x = bounds.minX - m }
            if node.position.y < bounds.minY - m { node.position.y = bounds.maxY + m }
            if node.position.y > bounds.maxY + m { node.position.y = bounds.minY - m }
        }
        let wave = Wave.offset(at: node.position)
        node.position.x += (wave.dx - bob.dx) * 0.6
        node.position.y += (wave.dy - bob.dy) * 0.6
        bob = wave
        let o = Depth.offset(CGVector(dx: 14, dy: -20))
        shadow.position = CGPoint(x: node.position.x + o.dx, y: node.position.y + o.dy)
        shadow.alpha = 0.35 * Depth.shadowAlpha
        shadow.setScale(Depth.shadowSpread)
    }
}

// MARK: - Ripple

extension Textures {
    /// A water ripple crest: a bright highlight with a dark trough just outside it
    /// and a faint dark band inside, like light bending over a small wave.
    static let waterRing = make(size: CGSize(width: 256, height: 256)) { ctx, r in
        let c = CGPoint(x: r.midX, y: r.midY)
        func band(_ radius: CGFloat, _ width: CGFloat, _ color: CGColor) {
            ctx.setStrokeColor(color)
            ctx.setLineWidth(width)
            ctx.strokeEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }
        band(117, 10, CGColor(gray: 0, alpha: 0.4))    // trough outside the crest
        band(108, 8, CGColor(gray: 1, alpha: 0.9))     // crest highlight
        band(99, 10, CGColor(gray: 0, alpha: 0.16))    // soft shade inside
    }
}

enum Ripple {
    /// Realistic: ripples are waves in the water (distortion). Otherwise drawn rings.
    static var realistic = true
    /// Multiplier from the Ripple strength setting.
    static var strength: CGFloat = 1
    static var unit: CGFloat = 1

    /// A ring wave whose size matches a drawn ripple of `size` points.
    private static func wave(at point: CGPoint, size: CGFloat, weight: CGFloat) {
        let scale = size / (240 * unit)
        Wave.splash(at: point, strength: 9 * unit * sqrt(scale) * weight * strength, scale: max(0.25, scale))
    }

    /// Expanding rings that fade out, then remove themselves. `realistic: false` always draws rings
    /// (for tiny, frequent ones like landing petals).
    static func spawn(at point: CGPoint, in parent: SKNode, size: CGFloat = 220, rings: Int = 3, strength: CGFloat = 0.5,
                      realistic allowWave: Bool = true) {
        if realistic && allowWave {
            wave(at: point, size: size, weight: min(1, strength * 2))
            return
        }
        for k in 0..<rings {
            let scale = 1 - CGFloat(k) * 0.22
            ring(at: point, in: parent, size: size * scale, duration: 1.6 + Double(k) * 0.3,
                 delay: Double(k) * 0.18, alpha: strength * 1.4)
        }
    }

    /// A raindrop: a tiny splash, then two or three rings that spread and slow down.
    static func drop(at point: CGPoint, in parent: SKNode, size: CGFloat) {
        if realistic {
            wave(at: point, size: size * 1.4, weight: 1.1)
            return
        }
        let splash = SKSpriteNode(texture: Textures.softCircle)
        splash.color = .white
        splash.colorBlendFactor = 1
        splash.size = CGSize(width: size * 0.12, height: size * 0.12)
        splash.position = point
        splash.alpha = 0.7
        splash.zPosition = 6
        parent.addChild(splash)
        splash.run(.sequence([.group([.scale(to: 0.3, duration: 0.25), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))

        for k in 0..<Int.random(in: 2...3) {
            ring(at: point, in: parent, size: size * (1 - CGFloat(k) * 0.3), duration: 1.3 - Double(k) * 0.15,
                 delay: Double(k) * 0.13, alpha: 0.85 - CGFloat(k) * 0.2)
        }
    }

    private static func ring(at point: CGPoint, in parent: SKNode, size: CGFloat, duration: Double,
                             delay: Double, alpha: CGFloat) {
        let ring = SKSpriteNode(texture: Textures.waterRing)
        ring.position = point
        ring.size = CGSize(width: size * 0.08, height: size * 0.08)
        ring.alpha = 0
        ring.zPosition = 5
        parent.addChild(ring)

        let grow = SKAction.resize(toWidth: size, height: size, duration: duration)
        grow.timingMode = .easeOut
        // Rings are strongest just after forming and thin out as they spread.
        let fade = SKAction.sequence([.fadeAlpha(to: min(1, alpha), duration: 0.06),
                                      .fadeOut(withDuration: duration - 0.06)])
        fade.timingMode = .easeIn
        ring.run(.sequence([.wait(forDuration: delay), .group([grow, fade]), .removeFromParent()]))
    }
}
