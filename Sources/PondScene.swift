// PondScene — the pond itself: shader water, then shadows, then koi.

import SpriteKit

final class PondScene: SKScene {
    private let water = SKSpriteNode(color: .black, size: .zero)
    private let shadowLayer = SKNode()
    private var koi: [Koi] = []
    private var lastTime: TimeInterval?

    static let waterColor = SKColor(red: 0.03, green: 0.13, blue: 0.12, alpha: 1)

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
        anchorPoint = .zero

        water.anchorPoint = .zero
        water.shader = Shaders.water
        water.zPosition = -10
        addChild(water)

        shadowLayer.zPosition = -5
        addChild(shadowLayer)

        layoutWater()
        spawnKoi()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutWater()
    }

    private func layoutWater() {
        water.size = size
        water.setValue(SKAttributeValue(vectorFloat2: vector_float2(Float(size.width), Float(size.height))),
                       forAttribute: "a_size")
    }

    /// Roughly one koi per 600k square points, e.g. 8 on a 3440×1440 display.
    private func spawnKoi() {
        let count = max(4, min(10, Int(size.width * size.height / 600_000)))
        let varieties = KoiVariety.all.shuffled()
        let depths = (0..<count).map { _ in CGFloat.random(in: 0...1) }.sorted(by: >)
        let unit = min(size.width, size.height) / 1100

        for (k, depth) in depths.enumerated() {
            let pos = CGPoint(x: .random(in: size.width * 0.15...size.width * 0.85),
                              y: .random(in: size.height * 0.15...size.height * 0.85))
            let fish = Koi(at: pos, scale: unit * .random(in: 0.85...1.3), depth: depth,
                           variety: varieties[k % varieties.count], water: Self.waterColor)
            // Deeper fish sit lower in the stack so shallow ones swim over them.
            fish.node.zPosition = CGFloat(k) * 10
            addChild(fish.node)
            shadowLayer.addChild(fish.shadowNode)
            koi.append(fish)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        // Clamp so a long pause (covered, asleep) doesn't teleport the fish.
        let dt = CGFloat(min(currentTime - (lastTime ?? currentTime), 1.0 / 20))
        lastTime = currentTime
        let bounds = CGRect(origin: .zero, size: size)
        for fish in koi {
            fish.update(dt: dt, bounds: bounds, others: koi)
        }
    }
}

enum Shaders {
    /// Procedural water: a dark green base with drifting caustic light.
    /// Everything runs on the GPU; the CPU only advances u_time.
    static let water: SKShader = {
        let s = SKShader(source: """
        void main() {
            vec2 px = v_tex_coord * a_size;
            float t = u_time * 0.18 + 23.0;

            // Tileable caustics (period = 520px), after "Tileable Water Caustic" by Dave_Hoskins.
            vec2 p = mod(px / 520.0 * 6.28318, 6.28318) - 250.0;
            vec2 i = p;
            float c = 1.0;
            float inten = 0.005;
            for (int n = 0; n < 4; n++) {
                float tt = t * (1.0 - (3.5 / float(n + 1)));
                i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
                c += 1.0 / length(vec2(p.x / (sin(i.x + tt) / inten), p.y / (cos(i.y + tt) / inten)));
            }
            c /= 4.0;
            c = 1.17 - pow(c, 1.4);
            float light = clamp(pow(abs(c), 8.0), 0.0, 1.0);

            // Depth gradient: lighter toward the top edge, darker at the bottom.
            vec3 deep    = vec3(0.016, 0.086, 0.078);
            vec3 shallow = vec3(0.043, 0.180, 0.160);
            vec3 col = mix(deep, shallow, smoothstep(0.0, 1.0, v_tex_coord.y));
            col += vec3(0.30, 0.50, 0.42) * light * 0.28;

            gl_FragColor = vec4(col, 1.0);
        }
        """)
        s.attributes = [SKAttribute(name: "a_size", type: .vectorFloat2)]
        return s
    }()
}
