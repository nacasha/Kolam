// Intro — the pond fills in when the app starts instead of appearing all at once:
// water first, then plants, pads, fish and the rest, each kind in its own wave.

import SpriteKit

enum Intro {
    /// When each kind of thing starts to appear, in seconds after launch.
    enum Stage {
        static let water: TimeInterval = 0
        static let plants: TimeInterval = 0.7
        static let pads: TimeInterval = 1.3
        static let koi: TimeInterval = 1.9
        static let minnows: TimeInterval = 2.5
        static let frog: TimeInterval = 2.6
        static let turtle: TimeInterval = 2.9
        static let dragonflies: TimeInterval = 3.3
    }

    private static let key = "intro"

    /// Fades `node` in after `delay`, growing from `from` × its current scale.
    static func reveal(_ node: SKNode, after delay: TimeInterval, duration: TimeInterval = 0.9, from: CGFloat = 1) {
        let alpha = node.alpha
        let sx = node.xScale, sy = node.yScale
        node.alpha = 0
        var grow: [SKAction] = [.fadeAlpha(to: alpha, duration: duration)]
        if from != 1 {
            node.xScale = sx * from
            node.yScale = sy * from
            let scale = SKAction.group([.scaleX(to: sx, duration: duration), .scaleY(to: sy, duration: duration)])
            scale.timingMode = .easeOut
            grow.append(scale)
        }
        let group = SKAction.group(grow)
        group.timingMode = .easeOut
        node.run(.sequence([.wait(forDuration: delay), group]), withKey: key)
    }

    /// Reveals each node in turn, spread evenly over `spread` seconds from `start`,
    /// in a shuffled order so a kind doesn't sweep in from one side.
    static func cascade(_ nodes: [SKNode], from start: TimeInterval, spread: TimeInterval,
                        duration: TimeInterval = 0.9, grow: CGFloat = 1) {
        let order = nodes.shuffled()
        let step = order.count > 1 ? spread / TimeInterval(order.count - 1) : 0
        for (k, node) in order.enumerated() {
            reveal(node, after: start + step * TimeInterval(k), duration: duration, from: grow)
        }
    }
}
