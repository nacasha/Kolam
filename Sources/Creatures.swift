// Creatures — small fish schools, dragonflies and a frog; plus vines at the pond edges.

import SpriteKit

func angleDelta(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
    if d > .pi { d -= 2 * .pi }
    if d < -.pi { d += 2 * .pi }
    return d
}

private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

private func sprite(_ texture: SKTexture, _ color: SKColor, _ size: CGSize, alpha: CGFloat = 1, z: CGFloat = 0) -> SKSpriteNode {
    let s = SKSpriteNode(texture: texture)
    s.color = color
    s.colorBlendFactor = 1
    s.size = size
    s.alpha = alpha
    s.zPosition = z
    return s
}

// MARK: - Small fish

/// A school of small fish. An invisible leader wanders (or chases the nearest koi);
/// each fish springs toward its own slot around the leader, so the school stretches and bunches.
final class MinnowSchool {
    private struct Member {
        let node: SKSpriteNode
        var pos: CGPoint
        var vel: CGVector
        let slot: CGVector
        let seed: CGFloat
    }

    private var members: [Member] = []
    private var leader: CGPoint
    private var heading = CGFloat.random(in: 0..<(2 * .pi))
    private var time: CGFloat = 0
    private let seed = CGFloat.random(in: 0...1000)
    private let unit: CGFloat

    init(at p: CGPoint, count: Int, unit u: CGFloat, color: SKColor, parent: SKNode) {
        leader = p
        unit = u
        for _ in 0..<count {
            let s = CGFloat.random(in: 0.8...1.2)
            let node = sprite(Textures.leaf, color, CGSize(width: 16 * u * s, height: 5 * u * s), alpha: 0.75)
            let slot = CGVector(dx: .random(in: -70...20) * u, dy: .random(in: -35...35) * u)
            let pos = CGPoint(x: p.x + slot.dx, y: p.y + slot.dy)
            node.position = pos
            parent.addChild(node)
            members.append(Member(node: node, pos: pos, vel: .zero, slot: slot, seed: .random(in: 0...100)))
        }
    }

    func remove() { members.forEach { $0.node.removeFromParent() } }

    func update(dt: CGFloat, bounds: CGRect, koi: [Koi], follow: Bool) {
        time += dt
        var turn = sin(time * 0.5 + seed) * 0.8 + sin(time * 0.21 + seed * 2) * 0.5
        var speed = 55 * unit

        let margin = min(bounds.width, bounds.height) * 0.12
        let edge = min(leader.x - bounds.minX, bounds.maxX - leader.x, leader.y - bounds.minY, bounds.maxY - leader.y)
        if edge < margin {
            let toCenter = atan2(bounds.midY - leader.y, bounds.midX - leader.x)
            turn += angleDelta(toCenter, heading) * 2 * (1 - max(edge, -margin) / margin)
        }
        if follow, let k = koi.min(by: { dist($0.head, leader) < dist($1.head, leader) }) {
            let d = dist(k.head, leader)
            if d < 450 * unit {
                turn += angleDelta(atan2(k.head.y - leader.y, k.head.x - leader.x), heading) * 1.8
                speed = d < 60 * unit ? 30 * unit : 85 * unit
            }
        }
        heading += turn * dt
        leader.x += cos(heading) * speed * dt
        leader.y += sin(heading) * speed * dt

        let c = cos(heading), s = sin(heading)
        for i in members.indices {
            var m = members[i]
            let jx = sin(time * 1.7 + m.seed) * 6 * unit, jy = cos(time * 1.3 + m.seed) * 6 * unit
            let tx = leader.x + m.slot.dx * c - m.slot.dy * s + jx
            let ty = leader.y + m.slot.dx * s + m.slot.dy * c + jy
            m.vel.dx += ((tx - m.pos.x) * 3 - m.vel.dx * 2) * dt
            m.vel.dy += ((ty - m.pos.y) * 3 - m.vel.dy * 2) * dt
            m.pos.x += m.vel.dx * dt
            m.pos.y += m.vel.dy * dt
            m.node.position = m.pos
            if hypot(m.vel.dx, m.vel.dy) > 2 * unit { m.node.zRotation = atan2(m.vel.dy, m.vel.dx) }
            members[i] = m
        }
    }
}

// MARK: - Dragonfly

/// Hovers in place, then darts to a nearby spot, like a real dragonfly.
final class Dragonfly {
    let node = SKNode()
    let shadow: SKSpriteNode
    private var wings: [SKSpriteNode] = []
    private var pos: CGPoint
    private var target: CGPoint
    private var heading = CGFloat.random(in: 0..<(2 * .pi))
    private var hoverLeft = CGFloat.random(in: 0.5...3)
    private var time: CGFloat = 0
    private let seed = CGFloat.random(in: 0...100)
    private let unit: CGFloat

    init(at p: CGPoint, unit u: CGFloat) {
        pos = p
        target = p
        unit = u
        let color = [
            SKColor(red: 0.20, green: 0.70, blue: 0.75, alpha: 1),
            SKColor(red: 0.25, green: 0.45, blue: 0.90, alpha: 1),
            SKColor(red: 0.85, green: 0.25, blue: 0.20, alpha: 1),
            SKColor(red: 0.90, green: 0.65, blue: 0.20, alpha: 1),
        ].randomElement()!
        let f = u * 1.8

        let tail = sprite(Textures.circle, color, CGSize(width: 30 * f, height: 3.4 * f), z: 2)
        tail.anchorPoint = CGPoint(x: 1, y: 0.5)
        let thorax = sprite(Textures.circle, color.blended(withFraction: 0.3, of: .black)!, CGSize(width: 8 * f, height: 5.5 * f), z: 3)
        thorax.position = CGPoint(x: 2 * f, y: 0)
        let head = sprite(Textures.circle, color.blended(withFraction: 0.45, of: .black)!, CGSize(width: 5 * f, height: 5.5 * f), z: 3)
        head.position = CGPoint(x: 6.5 * f, y: 0)

        for (x, side, tilt) in [(3.5, 1.0, 0.2), (3.5, -1.0, 0.2), (0.0, 1.0, 0.5), (0.0, -1.0, 0.5)] as [(CGFloat, CGFloat, CGFloat)] {
            let wing = sprite(Textures.petal, .white, CGSize(width: 4.5 * f, height: 19 * f), alpha: 0.4, z: 1)
            wing.anchorPoint = CGPoint(x: 0.5, y: 0)
            wing.position = CGPoint(x: x * f, y: 0)
            wing.zRotation = side > 0 ? tilt : .pi - tilt
            wings.append(wing)
        }
        ([tail, thorax, head] + wings).forEach(node.addChild)
        node.zPosition = 1200

        shadow = sprite(Textures.softCircle, .black, CGSize(width: 44 * f, height: 30 * f), alpha: 0.16)
    }

    func update(dt: CGFloat, bounds: CGRect) {
        time += dt
        for (k, w) in wings.enumerated() {
            w.yScale = 0.55 + 0.45 * abs(sin(time * 90 + seed + CGFloat(k) * 0.8))
        }
        if hoverLeft > 0 {
            hoverLeft -= dt
            pos.x += sin(time * 7 + seed) * 10 * unit * dt
            pos.y += cos(time * 6 + seed) * 10 * unit * dt
            if hoverLeft <= 0 {
                let area = bounds.insetBy(dx: 60 * unit, dy: 60 * unit)
                let a = CGFloat.random(in: 0..<(2 * .pi)), r = CGFloat.random(in: 120...380) * unit
                target = CGPoint(x: min(max(pos.x + cos(a) * r, area.minX), area.maxX),
                                 y: min(max(pos.y + sin(a) * r, area.minY), area.maxY))
            }
        } else {
            let dx = target.x - pos.x, dy = target.y - pos.y, d = hypot(dx, dy)
            heading += angleDelta(atan2(dy, dx), heading) * min(1, dt * 10)
            let speed = min(520 * unit, d * 3.5 + 40 * unit)
            pos.x += cos(heading) * speed * dt
            pos.y += sin(heading) * speed * dt
            if d < 8 * unit { hoverLeft = .random(in: 1.2...5) }
        }
        node.position = pos
        node.zRotation = heading
        let o = Depth.offset(CGVector(dx: 45 * unit, dy: -60 * unit))
        shadow.position = CGPoint(x: pos.x + o.dx, y: pos.y + o.dy)
        shadow.alpha = 0.16 * Depth.shadowAlpha
        shadow.zRotation = heading
    }
}

// MARK: - Frog

/// Sits on a lily pad (riding along as it drifts) and now and then hops to a nearby one.
final class Frog {
    let node = SKNode()
    private weak var pad: LilyPad?
    private var nextHop = CGFloat.random(in: 6...14)
    private var hopping = false
    private let unit: CGFloat

    init(unit u: CGFloat) {
        unit = u
        let f = u * 1.7
        let dark = SKColor(red: 0.20, green: 0.38, blue: 0.14, alpha: 1)
        let skin = SKColor(red: 0.36, green: 0.60, blue: 0.23, alpha: 1)

        var parts: [SKSpriteNode] = []
        let contact = sprite(Textures.softCircle, .black, CGSize(width: 40 * f, height: 36 * f), alpha: 0.35, z: -1)
        parts.append(contact)
        for side in [-1.0, 1.0] as [CGFloat] {
            let back = sprite(Textures.leaf, dark, CGSize(width: 20 * f, height: 7 * f))
            back.anchorPoint = CGPoint(x: 0, y: 0.5)
            back.position = CGPoint(x: -6 * f, y: side * 6 * f)
            back.zRotation = side * (.pi - 0.7)
            let front = sprite(Textures.leaf, dark, CGSize(width: 10 * f, height: 4 * f))
            front.anchorPoint = CGPoint(x: 0, y: 0.5)
            front.position = CGPoint(x: 6 * f, y: side * 7 * f)
            front.zRotation = side * 0.9
            let eye = sprite(Textures.circle, SKColor(white: 0.95, alpha: 1), CGSize(width: 6.5 * f, height: 6.5 * f), z: 3)
            eye.position = CGPoint(x: 11 * f, y: side * 6 * f)
            let pupil = sprite(Textures.circle, .black, CGSize(width: 3.2 * f, height: 3.2 * f), z: 4)
            pupil.position = CGPoint(x: 12 * f, y: side * 6 * f)
            parts += [back, front, eye, pupil]
        }
        let body = sprite(Textures.circle, skin, CGSize(width: 24 * f, height: 20 * f), z: 1)
        let head = sprite(Textures.circle, skin, CGSize(width: 15 * f, height: 16 * f), z: 1)
        head.position = CGPoint(x: 9 * f, y: 0)
        let spot1 = sprite(Textures.circle, dark, CGSize(width: 5 * f, height: 5 * f), z: 2)
        spot1.position = CGPoint(x: -4 * f, y: 3 * f)
        let spot2 = sprite(Textures.circle, dark, CGSize(width: 4 * f, height: 4 * f), z: 2)
        spot2.position = CGPoint(x: -1 * f, y: -4 * f)
        parts += [body, head, spot1, spot2]
        parts.forEach(node.addChild)
        node.zPosition = 3
    }

    /// Sits on a random pad, or disappears if there are none. Called whenever pads are rebuilt.
    func seat(on pads: [LilyPad]) {
        node.removeAllActions()
        node.removeFromParent()
        node.setScale(1)
        hopping = false
        guard let p = pads.randomElement() else { pad = nil; return }
        pad = p
        node.position = CGPoint(x: .random(in: -6...6) * unit, y: .random(in: -6...6) * unit)
        node.zRotation = .random(in: 0..<(2 * .pi))
        p.node.addChild(node)
    }

    func remove() {
        node.removeAllActions()
        node.removeFromParent()
        pad = nil
    }

    func update(dt: CGFloat, pads: [LilyPad], surface: SKNode) {
        guard let current = pad, !hopping, pads.count > 1 else { return }
        nextHop -= dt
        guard nextHop <= 0 else { return }
        nextHop = .random(in: 8...20)
        let here = current.node.position
        let others = pads.filter { $0 !== current }
        let near = others.filter { dist($0.node.position, here) < 420 * unit }
        guard let target = near.randomElement() ?? others.min(by: { dist($0.node.position, here) < dist($1.node.position, here) })
        else { return }
        hop(from: current, to: target, surface: surface)
    }

    private func hop(from: LilyPad, to: LilyPad, surface: SKNode) {
        hopping = true
        let start = from.node.convert(node.position, to: surface)
        let rotation = node.zRotation + from.node.zRotation
        node.removeFromParent()
        node.position = start
        node.zRotation = rotation
        node.zPosition = 20
        surface.addChild(node)

        let end = to.node.position
        let face = atan2(end.y - start.y, end.x - start.x)
        let duration = 0.75
        let move = SKAction.move(to: end, duration: duration)
        move.timingMode = .easeInEaseOut
        let arc = SKAction.sequence([.scale(to: 1.4, duration: duration / 2), .scale(to: 1, duration: duration / 2)])
        node.run(.sequence([.rotate(toAngle: face, duration: 0.2, shortestUnitArc: true), .group([move, arc])])) {
            [weak self] in
            guard let self else { return }
            let landing = self.node.position
            self.node.removeFromParent()
            self.node.position = surface.convert(landing, to: to.node)
            self.node.zRotation -= to.node.zRotation
            self.node.zPosition = 3
            to.node.addChild(self.node)
            self.pad = to
            self.hopping = false
            Ripple.spawn(at: landing, in: surface, size: 90 * self.unit, rings: 2, strength: 0.4)
        }
    }
}

// MARK: - Vines

/// Leafy vines creeping in from the screen edges. Built once; each sways gently.
enum Vines {
    static func build(in bounds: CGRect, unit u: CGFloat) -> SKNode {
        let root = SKNode()
        root.zPosition = 1050
        let count = max(4, Int((bounds.width + bounds.height) * 2 / (700 * u)))
        for _ in 0..<count { root.addChild(vine(in: bounds, unit: u)) }
        return root
    }

    private static func vine(in b: CGRect, unit u: CGFloat) -> SKNode {
        let start: CGPoint
        var angle: CGFloat = .random(in: -1.1...1.1)
        switch Int.random(in: 0..<4) {
        case 0: start = CGPoint(x: .random(in: b.minX...b.maxX), y: b.maxY + 8 * u); angle += -.pi / 2
        case 1: start = CGPoint(x: .random(in: b.minX...b.maxX), y: b.minY - 8 * u); angle += .pi / 2
        case 2: start = CGPoint(x: b.minX - 8 * u, y: .random(in: b.minY...b.maxY))
        default: start = CGPoint(x: b.maxX + 8 * u, y: .random(in: b.minY...b.maxY)); angle += .pi
        }

        // Walk a gently curling path from the edge.
        let step = 5 * u
        let steps = Int(CGFloat.random(in: 160...420) / 5)
        let curl = CGFloat.random(in: -0.06...0.06)
        let seed = CGFloat.random(in: 0...100)
        var points: [CGPoint] = []
        var angles: [CGFloat] = []
        var p = CGPoint.zero
        for i in 0..<steps {
            points.append(p)
            angles.append(angle)
            angle += curl + sin(CGFloat(i) * 0.15 + seed) * 0.03
            p = CGPoint(x: p.x + cos(angle) * step, y: p.y + sin(angle) * step)
        }

        let container = SKNode()
        container.position = start
        let path = CGMutablePath()
        path.addLines(between: points)

        let stemShadow = SKShapeNode(path: path)
        let so = Depth.offset(CGVector(dx: 8 * u, dy: -10 * u))
        let lo = Depth.offset(CGVector(dx: 7 * u, dy: -9 * u))
        stemShadow.strokeColor = SKColor(white: 0, alpha: 0.25 * Depth.shadowAlpha)
        stemShadow.lineWidth = 3 * u
        stemShadow.position = CGPoint(x: so.dx, y: so.dy)
        stemShadow.zPosition = -1
        let stem = SKShapeNode(path: path)
        stem.strokeColor = SKColor(red: 0.17, green: 0.30, blue: 0.14, alpha: 1)
        stem.lineWidth = 2.6 * u
        stem.lineCap = .round
        container.addChild(stemShadow)
        container.addChild(stem)

        let greens = [
            SKColor(red: 0.26, green: 0.48, blue: 0.20, alpha: 1),
            SKColor(red: 0.32, green: 0.55, blue: 0.24, alpha: 1),
            SKColor(red: 0.21, green: 0.40, blue: 0.17, alpha: 1),
        ]
        var side: CGFloat = 1
        for i in stride(from: 3, to: points.count, by: 4) {
            let t = CGFloat(i) / CGFloat(points.count)
            let s = (1.25 - 0.6 * t) * .random(in: 0.85...1.15)
            let size = CGSize(width: 24 * u * s, height: 11 * u * s)
            let rotation = angles[i] + side * 0.9
            let leaf = sprite(Textures.leaf, greens.randomElement()!, size, z: 2)
            leaf.anchorPoint = CGPoint(x: 0, y: 0.5)
            leaf.position = points[i]
            leaf.zRotation = rotation
            let leafShadow = sprite(Textures.leaf, .black, size, alpha: 0.2 * Depth.shadowAlpha, z: -1)
            leafShadow.anchorPoint = CGPoint(x: 0, y: 0.5)
            leafShadow.position = CGPoint(x: points[i].x + lo.dx, y: points[i].y + lo.dy)
            leafShadow.zRotation = rotation
            container.addChild(leafShadow)
            container.addChild(leaf)
            side = -side
        }

        let sway = SKAction.rotate(byAngle: 0.025, duration: .random(in: 3...4.5))
        sway.timingMode = .easeInEaseOut
        container.run(.repeatForever(.sequence([sway, sway.reversed()])))
        // Vines are long and rooted at the bank: they lean a little, pivoting at the root.
        let outer = SKNode()
        outer.position = container.position
        container.position = .zero
        outer.addChild(container)
        outer.userData = ["lean": angles.first ?? 0, "stiffness": 0.35]
        return outer
    }
}
