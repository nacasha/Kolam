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
