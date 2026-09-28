// Turtle — paddles slowly along the bottom, and every minute or so swims to a
// lily pad, climbs on to rest (riding along as the pad drifts), then dives again.

import SpriteKit

extension Textures {
    /// Shell seen from above, long axis along +x: a central row of scutes with
    /// side plates. White with grey seams so it can be tinted.
    static let shell = make(size: CGSize(width: 76, height: 64)) { ctx, r in
        let oval = CGPath(ellipseIn: r.insetBy(dx: 1, dy: 1), transform: nil)
        ctx.addPath(oval)
        ctx.fillPath()
        ctx.addPath(oval)
        ctx.clip()
        ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 1))
        ctx.setLineWidth(2)
        let c = CGPoint(x: r.midX, y: r.midY)
        // Central scutes.
        for k in 0..<3 {
            let x = c.x + CGFloat(k - 1) * 17
            ctx.strokeEllipse(in: CGRect(x: x - 9, y: c.y - 10, width: 18, height: 20))
        }
        // Side plates: lines from the centre row out to the rim.
        for k in 0..<5 {
            let x = c.x + CGFloat(k - 2) * 14
            ctx.move(to: CGPoint(x: x, y: c.y + 10))
            ctx.addLine(to: CGPoint(x: x * 1.02 - c.x * 0.02, y: r.maxY))
            ctx.move(to: CGPoint(x: x, y: c.y - 10))
            ctx.addLine(to: CGPoint(x: x * 1.02 - c.x * 0.02, y: r.minY))
        }
        ctx.strokePath()
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: r.insetBy(dx: 6, dy: 6))
    }
}

final class Turtle {
    let node = SKNode()
    let shadow: SKSpriteNode

    private enum State {
        case swimming(until: CGFloat)
        case toPad(LilyPad)
        case resting(LilyPad, until: CGFloat)
    }

    private var state: State = .swimming(until: .random(in: 25...50))
    private var parts: [(sprite: SKSpriteNode, color: SKColor)] = []
    private var flippers: [(sprite: SKSpriteNode, rest: CGFloat)] = []
    private var heading = CGFloat.random(in: 0..<(2 * .pi))
    private var time: CGFloat = 0
    private let seed = CGFloat.random(in: 0...100)
    private let unit: CGFloat
    private let water: SKColor
    private weak var underwater: SKNode?

    init(at p: CGPoint, unit u: CGFloat, water: SKColor, underwater: SKNode, shadows: SKNode) {
        unit = u
        self.water = water
        self.underwater = underwater
        let f = u * 1.5
        let skin = SKColor(red: 0.45, green: 0.50, blue: 0.30, alpha: 1)
        let shellColor = SKColor(red: 0.40, green: 0.38, blue: 0.20, alpha: 1)

        shadow = SKSpriteNode(texture: Textures.softCircle)
        shadow.color = .black
        shadow.colorBlendFactor = 1
        shadow.size = CGSize(width: 78 * f, height: 62 * f)
        shadows.addChild(shadow)

        func part(_ tex: SKTexture, _ color: SKColor, _ size: CGSize, at pos: CGPoint, rot: CGFloat = 0, z: CGFloat) -> SKSpriteNode {
            let s = SKSpriteNode(texture: tex)
            s.color = color
            s.colorBlendFactor = 1
            s.size = size
            s.position = pos
            s.zRotation = rot
            s.zPosition = z
            node.addChild(s)
            parts.append((s, color))
            return s
        }

        for (x, y, rot, len) in [(12.0, 15.0, 0.9, 24.0), (12.0, -15.0, -0.9, 24.0),
                                 (-15.0, 13.0, 2.4, 16.0), (-15.0, -13.0, -2.4, 16.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            let flipper = part(Textures.leaf, skin, CGSize(width: len * f, height: len * 0.38 * f),
                               at: CGPoint(x: x * f, y: y * f), rot: rot, z: 0)
            flipper.anchorPoint = CGPoint(x: 0, y: 0.5)
            flippers.append((flipper, rot))
        }
        let tail = part(Textures.leaf, skin, CGSize(width: 9 * f, height: 4 * f), at: CGPoint(x: -26 * f, y: 0), rot: .pi, z: 0)
        tail.anchorPoint = CGPoint(x: 0, y: 0.5)
        _ = part(Textures.circle, skin, CGSize(width: 14 * f, height: 12 * f), at: CGPoint(x: 29 * f, y: 0), z: 1)
        _ = part(Textures.shell, shellColor, CGSize(width: 54 * f, height: 45 * f), at: .zero, z: 2)
        for side in [-1.0, 1.0] as [CGFloat] {
            _ = part(Textures.circle, SKColor(white: 0.08, alpha: 1), CGSize(width: 2.6 * f, height: 2.6 * f),
                     at: CGPoint(x: 32 * f, y: side * 3.6 * f), z: 3)
        }

        node.position = p
        node.zPosition = 300
        underwater.addChild(node)
        recolor(submerged: true)
    }

    func remove() {
        node.removeAllActions()
        node.removeFromParent()
        shadow.removeFromParent()
    }

    func update(dt: CGFloat, bounds: CGRect, pads: [LilyPad], surface: SKNode) {
        time += dt

        switch state {
        case .swimming(let until):
            paddle(speed: 1)
            var turn = sin(time * 0.17 + seed) * 0.25 + sin(time * 0.07 + seed * 2) * 0.2
            turn += edgeTurn(bounds)
            swim(dt: dt, turn: turn)
            if time > until {
                if let pad = pads.randomElement() {
                    state = .toPad(pad)
                } else {
                    state = .swimming(until: time + 30)
                }
            }

        case .toPad(let pad):
            paddle(speed: 1.4)
            guard pad.node.parent != nil else { state = .swimming(until: time + 20); break }
            let target = pad.node.position
            let d = hypot(target.x - node.position.x, target.y - node.position.y)
            let want = atan2(target.y - node.position.y, target.x - node.position.x)
            swim(dt: dt, turn: angleDelta(want, heading) * 1.2, speed: 1.3)
            if d < pad.radius * 0.5 { climb(onto: pad, surface: surface) }

        case .resting(let pad, let until):
            paddle(speed: 0)
            guard pad.node.parent != nil else { dive(from: nil, surface: surface); break }
            let scenePos = pad.node.convert(node.position, to: surface)
            let o = Depth.offset(CGVector(dx: 16 * unit, dy: -22 * unit))
            shadow.position = CGPoint(x: scenePos.x + o.dx, y: scenePos.y + o.dy)
            shadow.alpha = 0.3 * Depth.shadowAlpha
            if time > until { dive(from: pad, surface: surface) }
        }
    }

    // MARK: Motion

    private func swim(dt: CGFloat, turn: CGFloat, speed boost: CGFloat = 1) {
        heading += max(-0.5, min(0.5, turn)) * dt
        let speed = 22 * unit * boost * (0.8 + 0.2 * sin(time * 1.6 + seed))
        node.position.x += cos(heading) * speed * dt
        node.position.y += sin(heading) * speed * dt
        node.zRotation = heading
        // Near the bottom, so its shadow stays close.
        let o = Depth.offset(CGVector(dx: 5 * unit, dy: -7 * unit))
        shadow.position = CGPoint(x: node.position.x + o.dx, y: node.position.y + o.dy)
        shadow.alpha = 0.25 * Depth.shadowAlpha
    }

    private func edgeTurn(_ b: CGRect) -> CGFloat {
        let p = node.position
        let margin = min(b.width, b.height) * 0.15
        let edge = min(p.x - b.minX, b.maxX - p.x, p.y - b.minY, b.maxY - p.y)
        guard edge < margin else { return 0 }
        return angleDelta(atan2(b.midY - p.y, b.midX - p.x), heading) * 2 * (1 - max(edge, -margin) / margin)
    }

    /// Slow alternating strokes; `speed` 0 tucks the flippers in at rest.
    private func paddle(speed: CGFloat) {
        for (k, f) in flippers.enumerated() {
            let side: CGFloat = f.rest > 0 ? 1 : -1
            let phase = time * 2.2 + (k < 2 ? 0 : .pi)
            f.sprite.zRotation = f.rest + side * sin(phase) * 0.35 * speed - side * (speed == 0 ? 0.25 : 0)
        }
    }

    // MARK: Pad

    private func climb(onto pad: LilyPad, surface: SKNode) {
        let scenePos = node.position
        node.removeFromParent()
        node.position = pad.node.convert(scenePos, from: surface)
        node.zRotation = heading - pad.node.zRotation
        node.zPosition = 4
        pad.node.addChild(node)
        recolor(submerged: false)
        Ripple.spawn(at: scenePos, in: surface, size: 120 * unit, rings: 2, strength: 0.45)
        state = .resting(pad, until: time + .random(in: 20...40))
    }

    private func dive(from pad: LilyPad?, surface: SKNode) {
        let scenePos = pad.map { $0.node.convert(node.position, to: surface) } ?? node.position
        if let pad { heading = node.zRotation + pad.node.zRotation }
        node.removeFromParent()
        node.position = scenePos
        node.zRotation = heading
        node.zPosition = 300
        underwater?.addChild(node)
        recolor(submerged: true)
        Ripple.spawn(at: scenePos, in: surface, size: 140 * unit, rings: 3, strength: 0.45)
        state = .swimming(until: time + .random(in: 40...80))
    }

    /// Underwater the turtle takes on the water's colour, like deep koi.
    private func recolor(submerged: Bool) {
        for p in parts {
            p.sprite.color = submerged ? (p.color.blended(withFraction: 0.35, of: water) ?? p.color) : p.color
        }
    }
}
