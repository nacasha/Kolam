// Debris — small things adrift on the surface: loose rafts of pollen or dust that
// the wind pushes across the pond, and air bubbles that rise from the floor, float
// a moment and pop.

import SpriteKit

extension Textures {
    /// A soap-thin bubble: a pale rim with a small highlight toward the light.
    static let bubble = make(size: CGSize(width: 64, height: 64)) { ctx, r in
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.75))
        ctx.setLineWidth(5)
        ctx.strokeEllipse(in: r.insetBy(dx: 5, dy: 5))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.12))
        ctx.fillEllipse(in: r.insetBy(dx: 7, dy: 7))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: 16, y: 36, width: 11, height: 9))
    }
}

final class Debris {
    private final class Speck {
        let node: SKSpriteNode
        let bubble: Bool
        var life: CGFloat
        let fullLife: CGFloat
        var floating = Floating()
        let seed = CGFloat.random(in: 0...100)
        var popped = false

        init(node: SKSpriteNode, bubble: Bool, life: CGFloat) {
            self.node = node
            self.bubble = bubble
            self.life = life
            fullLife = life
        }
    }

    private var specks: [Speck] = []
    private var pollenDue: CGFloat = 0
    private var bubbleDue: CGFloat = 0
    private var time: CGFloat = 0

    private static func colors(_ season: Season) -> [SKColor] {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SKColor { SKColor(red: r, green: g, blue: b, alpha: 1) }
        switch season {
        case .spring: return [rgb(1.0, 0.92, 0.52), rgb(0.98, 0.96, 0.80), rgb(1.0, 0.86, 0.40)]
        case .summer: return [rgb(0.92, 0.90, 0.50), rgb(0.85, 0.88, 0.62)]
        case .autumn: return [rgb(0.78, 0.64, 0.42), rgb(0.66, 0.52, 0.34)]
        case .winter: return [rgb(0.90, 0.92, 0.95)]
        }
    }

    /// Pollen is heaviest in spring and scarce in winter.
    private static func pollenRate(_ season: Season) -> CGFloat {
        switch season {
        case .spring: return 1.4
        case .summer: return 1
        case .autumn: return 0.6
        case .winter: return 0.25
        }
    }

    /// `ice` is how far the ice reaches in from the screen edges, in points.
    func update(dt: CGFloat, on: Bool, amount: CGFloat, season: Season, ice: CGFloat,
                screen: CGRect, pond: CGRect, unit u: CGFloat, surface: SKNode) {
        time += dt
        let areaM = screen.width * screen.height / 1_000_000
        let open = screen.insetBy(dx: ice, dy: ice)
        func point(in r: CGRect) -> CGPoint {
            CGPoint(x: .random(in: r.minX...r.maxX), y: .random(in: r.minY...r.maxY))
        }

        if on {
            // Pollen: a loose raft of specks every few seconds.
            pollenDue += 0.35 * Self.pollenRate(season) * amount * areaM * dt
            while pollenDue >= 1 {
                pollenDue -= 1
                guard specks.count < 400 else { pollenDue = 0; break }
                let center = point(in: pond)
                let colors = Self.colors(season)
                for _ in 0..<Int.random(in: 4...10) {
                    let node = SKSpriteNode(texture: Textures.softCircle)
                    node.color = colors.randomElement()!
                    node.colorBlendFactor = 1
                    let s = CGFloat.random(in: 2.5...5) * u
                    node.size = CGSize(width: s, height: s)
                    node.position = CGPoint(x: center.x + .random(in: -32...32) * u, y: center.y + .random(in: -24...24) * u)
                    node.zPosition = 4
                    node.alpha = 0
                    surface.addChild(node)
                    specks.append(Speck(node: node, bubble: false, life: .random(in: 25...50)))
                }
            }

            // Bubbles: a few at a time, only where the water is open.
            if open.width > 40 * u, open.height > 40 * u {
                bubbleDue += 0.5 * amount * areaM * dt
                while bubbleDue >= 1 {
                    bubbleDue -= 1
                    guard specks.count < 400 else { bubbleDue = 0; break }
                    let center = point(in: open.intersection(pond).isEmpty ? open : open.intersection(pond))
                    for k in 0..<Int.random(in: 1...4) {
                        let node = SKSpriteNode(texture: Textures.bubble)
                        let s = CGFloat.random(in: 5...11) * u
                        node.size = CGSize(width: s, height: s)
                        node.position = CGPoint(x: center.x + .random(in: -8...8) * u, y: center.y + .random(in: -8...8) * u)
                        node.zPosition = 4
                        node.alpha = 0
                        node.setScale(0.3)
                        // Rise one after another, not all at once.
                        node.run(.sequence([.wait(forDuration: Double(k) * 0.35),
                                            .group([.fadeAlpha(to: 0.8, duration: 0.25), .scale(to: 1, duration: 0.3)])]))
                        surface.addChild(node)
                        specks.append(Speck(node: node, bubble: true, life: .random(in: 3...10) + CGFloat(k) * 0.35))
                    }
                }
            }
        }

        let keep = screen.insetBy(dx: -100 * u, dy: -100 * u)
        specks.removeAll { s in
            s.life -= dt
            s.floating.step(s.node, dt: dt)
            if s.bubble {
                if s.life <= 0 && !s.popped {
                    s.popped = true
                    s.node.removeAllActions()
                    s.node.run(.sequence([.group([.scale(to: 1.5, duration: 0.12), .fadeOut(withDuration: 0.12)]),
                                          .removeFromParent()]))
                    Ripple.spawn(at: s.node.position, in: surface, size: s.node.size.width * 2.5, rings: 1,
                                 strength: 0.18, realistic: false)
                }
                return s.popped
            }
            // Pollen wanders a little on its own, and fades in and out.
            s.node.position.x += sin(time * 0.4 + s.seed) * 2 * u * dt
            s.node.position.y += cos(time * 0.33 + s.seed * 1.7) * 2 * u * dt
            s.node.alpha = 0.75 * min(1, (s.fullLife - s.life) / 2, s.life / 4)
            guard s.life <= 0 || !keep.contains(s.node.position) || !on else { return false }
            s.node.removeFromParent()
            return true
        }
    }
}
