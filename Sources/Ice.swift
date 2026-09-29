// Ice — in winter the pond freezes in from its edges: a ragged frosty rim that forms
// slowly over a minute or so and melts again when the season turns. Drawn above the
// fish (they swim under it) and below the surface layer (leaves and pads sit on it).

import SpriteKit

final class Ice {
    let node = SKSpriteNode(color: .clear, size: .zero)
    private let amount = SKUniform(name: "u_ice", float: 0)
    private let unit = SKUniform(name: "u_unit", float: 1)
    private let size = SKUniform(name: "u_size", vectorFloat2: vector_float2(1, 1))

    init() {
        node.anchorPoint = .zero
        node.zPosition = 500
        node.isHidden = true
        let s = SKShader(source: """
        // No uniforms in helpers: SpriteKit's GLSL→Metal translation rejects them.
        float iceHash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
        float iceNoise(vec2 p) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            f = f * f * (3.0 - 2.0 * f);
            return mix(mix(iceHash(i), iceHash(i + vec2(1.0, 0.0)), f.x),
                       mix(iceHash(i + vec2(0.0, 1.0)), iceHash(i + vec2(1.0, 1.0)), f.x), f.y);
        }

        void main() {
            vec2 p = v_tex_coord * u_size;
            vec2 q = p / u_unit;
            // Distance to the nearest screen edge, in pond units.
            float edge = min(min(p.x, p.y), min(u_size.x - p.x, u_size.y - p.y)) / u_unit;
            // A ragged frontier: broad bays plus smaller jags.
            float n = iceNoise(q * 0.012) * 0.65 + iceNoise(q * 0.045) * 0.35;
            float inside = u_ice * (50.0 + 230.0 * n) - edge;

            // No early return: SpriteKit's Metal translation needs main() to fall through.
            float body = smoothstep(-4.0, 6.0, inside);
            // Thicker and whiter toward the shore, clearer at the growing edge.
            float thick = clamp(inside / 150.0, 0.0, 1.0);
            float frost = iceNoise(q * 0.35) * 0.5 + iceNoise(q * 1.3) * 0.3 + iceHash(floor(p)) * 0.2;

            // Cracks: the borders between jittered cells.
            vec2 g = q / 42.0;
            vec2 gi = floor(g);
            float f1 = 9.0;
            float f2 = 9.0;
            for (int i = -1; i <= 1; i++) {
                for (int j = -1; j <= 1; j++) {
                    vec2 cp = gi + vec2(float(i), float(j));
                    vec2 pt = cp + vec2(iceHash(cp), iceHash(cp + 17.0));
                    float d = length(g - pt);
                    if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) { f2 = d; }
                }
            }
            float crack = (1.0 - smoothstep(0.0, 0.05, f2 - f1)) * smoothstep(10.0, 40.0, inside);

            vec3 col = mix(vec3(0.76, 0.87, 0.95), vec3(0.96, 0.98, 1.0), thick * 0.7 + frost * 0.3);
            float a = body * (0.30 + 0.45 * thick + 0.15 * frost);
            // A bright rim where new ice meets open water.
            float rim = smoothstep(-4.0, 0.0, inside) * (1.0 - smoothstep(0.0, 9.0, inside));
            col = mix(col, vec3(1.0), rim * 0.6);
            a = max(a, rim * 0.6);
            col = mix(col, vec3(0.52, 0.66, 0.78), crack * 0.6);
            a = clamp(a + crack * 0.15, 0.0, 0.92) * step(-4.0, inside);
            gl_FragColor = vec4(col * a, a);
        }
        """)
        s.uniforms = [amount, unit, size]
        node.shader = s
    }

    /// `level` is 0 (open water) … about 1.5 (ice well into the pond).
    func update(level: CGFloat, screen: CGSize, unit u: CGFloat) {
        node.isHidden = level < 0.005
        guard !node.isHidden else { return }
        node.size = screen
        amount.floatValue = Float(level)
        unit.floatValue = Float(u)
        size.vectorFloat2Value = vector_float2(Float(screen.width), Float(screen.height))
    }

    /// Roughly how far the ice reaches in from the edges, in points: half its
    /// ragged range, so things avoiding it err toward open water.
    static func reach(level: CGFloat, unit u: CGFloat) -> CGFloat { level * 165 * u }
}
