// Food — pellets dropped by a click. They float and drift on the surface; the
// nearest free koi claims each one, swims over and eats it with a little pop.

import SpriteKit

final class Food {
    private final class Pellet {
        let node: SKSpriteNode
        let shadow: SKSpriteNode
        var life: CGFloat = .random(in: 28...40)
        var bob = CGVector.zero
        let drift: CGVector
        weak var claimer: Koi?

        init(node: SKSpriteNode, shadow: SKSpriteNode, drift: CGVector) {
            self.node = node
            self.shadow = shadow
            self.drift = drift
        }
    }

    private var pellets: [Pellet] = []
    private static let maxPellets = 60

    func drop(at p: CGPoint, unit u: CGFloat, surface: SKNode, shadows: SKNode) {
        for k in 0..<Int.random(in: 5...8) {
            let a = CGFloat.random(in: 0..<(2 * .pi)), r = CGFloat.random(in: 0...45) * u
            let pos = CGPoint(x: p.x + cos(a) * r, y: p.y + sin(a) * r)
            let s = 10 * u * .random(in: 0.8...1.2)

            let node = SKSpriteNode(texture: Textures.circle)
            node.color = SKColor(red: 0.55, green: 0.36, blue: 0.18, alpha: 1)
            node.colorBlendFactor = 1
            node.size = CGSize(width: s, height: s * 0.85)
            node.position = pos
            node.zRotation = .random(in: 0..<(2 * .pi))
            node.zPosition = 8
            node.alpha = 0
            node.setScale(1.8)
            surface.addChild(node)

            let shadow = SKSpriteNode(texture: Textures.softCircle)
            shadow.color = .black
            shadow.colorBlendFactor = 1
            shadow.size = CGSize(width: s * 1.6, height: s * 1.6)
            shadow.alpha = 0
            shadows.addChild(shadow)

            // Fall in one by one, each landing with a tiny ripple.
            let delay = Double(k) * 0.05
            node.run(.sequence([
                .wait(forDuration: delay),
                .group([.fadeIn(withDuration: 0.2), .scale(to: 1, duration: 0.22)]),
                .run { Ripple.spawn(at: node.position, in: surface, size: 34 * u, rings: 1, strength: 0.35) },
            ]))
            shadow.run(.sequence([.wait(forDuration: delay + 0.2), .fadeAlpha(to: 0.3 * Depth.shadowAlpha, duration: 0.1)]))

            let drift = CGVector(dx: .random(in: -3...3) * u, dy: .random(in: -3...3) * u)
            pellets.append(Pellet(node: node, shadow: shadow, drift: drift))
        }
        while pellets.count > Self.maxPellets { remove(pellets.removeFirst()) }
    }

    func clear() {
        pellets.forEach(remove)
        pellets = []
    }

    /// `eaten` is called with each pellet's position as a koi eats it.
    func update(dt: CGFloat, koi: [Koi], unit u: CGFloat, eaten: (CGPoint) -> Void) {
        guard !pellets.isEmpty else { return }

        // Drift, bob on the waves, and slowly dissolve.
        for p in pellets {
            p.life -= dt
            p.node.position.x += p.drift.dx * dt
            p.node.position.y += p.drift.dy * dt
            let wave = Wave.offset(at: p.node.position)
            p.node.position.x += (wave.dx - p.bob.dx) * 0.6
            p.node.position.y += (wave.dy - p.bob.dy) * 0.6
            p.bob = wave
            if p.life < 3 { p.node.alpha = max(0, p.life / 3) }
            let o = Depth.offset(CGVector(dx: 6 * u, dy: -8 * u))
            p.shadow.position = CGPoint(x: p.node.position.x + o.dx, y: p.node.position.y + o.dy)
        }

        // Eat anything within reach of a mouth.
        pellets.removeAll { p in
            guard let fish = koi.first(where: { hypot($0.head.x - p.node.position.x, $0.head.y - p.node.position.y) < $0.reach })
            else {
                if p.life <= 0 { remove(p); return true }
                return false
            }
            _ = fish
            eaten(p.node.position)
            p.shadow.removeFromParent()
            p.node.removeAllActions()
            p.node.run(.sequence([.group([.scale(to: 0.2, duration: 0.15), .fadeOut(withDuration: 0.15)]), .removeFromParent()]))
            return true
        }

        // Each pellet is claimed by the nearest koi that isn't already after one.
        var busy = Set(pellets.compactMap { $0.claimer.map(ObjectIdentifier.init) })
        let reach = 900 * u
        for p in pellets where p.claimer == nil {
            let free = koi.filter { !busy.contains(ObjectIdentifier($0)) }
            guard let nearest = free.min(by: { dist($0.head, p.node.position) < dist($1.head, p.node.position) }),
                  dist(nearest.head, p.node.position) < reach else { continue }
            p.claimer = nearest
            busy.insert(ObjectIdentifier(nearest))
        }
        for p in pellets {
            p.claimer?.chase(p.node.position)
        }
    }

    private func remove(_ p: Pellet) {
        p.node.removeFromParent()
        p.shadow.removeFromParent()
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
