// Wind — how plants lean in the wind. Each plant's outer node carries its growth
// direction ("lean") and stiffness; it bends toward where the wind blows.

import SpriteKit

enum PlantLean {
    /// Bends every plant under `root` toward the wind. `strength` 1 = light breeze.
    static func apply(to root: SKNode?, windAngle: CGFloat, strength: CGFloat, enabled: Bool, dt: CGFloat) {
        guard let root else { return }
        let push = enabled ? min(1, strength / 3) : 0
        for plant in root.children {
            guard let lean = plant.userData?["lean"] as? CGFloat else { continue }
            let stiffness = plant.userData?["stiffness"] as? CGFloat ?? 1
            // Bend toward the wind: most when the wind blows across the plant.
            let target = sin(windAngle - lean) * push * 0.38 * stiffness
            plant.zRotation += (target - plant.zRotation) * min(1, dt * 1.6)
        }
    }
}

enum PlantCache {
    /// Resolution plant images are cached at; they're soft and moving, so lower is fine.
    static let scale: CGFloat = 0.6

    /// Moves a rasterized node's children into an inner node drawn at `scale`, and scales the
    /// node back up, so its cached image is smaller.
    static func shrink(_ node: SKEffectNode) {
        let inner = SKNode()
        for child in node.children {
            child.removeFromParent()
            inner.addChild(child)
        }
        inner.setScale(scale)
        node.addChild(inner)
        node.setScale(1 / scale)
    }
}
