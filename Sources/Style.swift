// Style — a full-screen pass over the whole scene: art styles (painterly, ink wash,
// pixel art) and a tilt-shift focus blur. Runs only when one of them is on.

import SpriteKit

enum ArtStyle: String { case natural, painterly, ink, pixel }

enum Style {
    static func isActive(_ c: PondConfig) -> Bool { c.artStyle != .natural || c.tiltOn }

    /// Everything is inlined in main(): SpriteKit's GLSL→Metal translation rejects
    /// uniforms referenced from helper functions.
    static func make() -> SKShader {
        let s = SKShader(source: """
        void main() {
            // Scene points for this pixel (the effect texture can extend past the screen).
            vec2 p = u_origin + v_tex_coord * u_tex;
            vec2 texel = 1.0 / u_tex;
            vec2 uv = v_tex_coord;

            // Pixel art: sample one point per block.
            if (u_style > 2.5) {
                vec2 q = (floor(p / u_px) + 0.5) * u_px;
                uv = (q - u_origin) / u_tex;
            }

            // Tilt-shift: blur grows with distance from the in-focus band.
            float blur = 0.0;
            if (u_tilt > 0.0) {
                float ty = p.y / u_size.y;
                float away = max(0.0, abs(ty - u_focus) - u_band);
                blur = u_tilt * smoothstep(0.0, 0.3, away) * 16.0;
            }

            vec4 c;
            if (blur > 0.4) {
                c = texture2D(u_texture, uv);
                for (int i = 0; i < 12; i++) {
                    float a = float(i) * 0.5236;
                    float r = mod(float(i), 2.0) < 0.5 ? 1.0 : 0.55;
                    c += texture2D(u_texture, uv + vec2(cos(a), sin(a)) * r * blur * texel);
                }
                c /= 13.0;
            } else if (u_style > 0.5 && u_style < 1.5) {
                // Painterly: simplified Kuwahara — take the calmest of four quadrants.
                vec3 best = vec3(0.0);
                float bestVar = 1e9;
                for (int k = 0; k < 4; k++) {
                    vec2 sg = vec2(k == 0 || k == 2 ? 1.0 : -1.0, k < 2 ? 1.0 : -1.0);
                    vec3 m = vec3(0.0);
                    vec3 m2 = vec3(0.0);
                    for (int i = 0; i < 2; i++) {
                        for (int j = 0; j < 2; j++) {
                            vec2 o = sg * vec2(float(i) + 0.5, float(j) + 0.5) * u_paint * texel;
                            vec3 sm = texture2D(u_texture, uv + o).rgb;
                            m += sm;
                            m2 += sm * sm;
                        }
                    }
                    m /= 4.0;
                    vec3 v = m2 / 4.0 - m * m;
                    float var = v.r + v.g + v.b;
                    if (var < bestVar) { bestVar = var; best = m; }
                }
                c = vec4(best, 1.0);
            } else {
                c = texture2D(u_texture, uv);
            }

            vec3 col = c.rgb;
            float grain = fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453);

            if (u_style > 0.5 && u_style < 1.5) {
                // Painterly: a touch more colour, and canvas weave.
                float l = dot(col, vec3(0.299, 0.587, 0.114));
                col = mix(vec3(l), col, 1.15);
                float weave = sin(p.x * 1.9) * sin(p.y * 1.9);
                col *= 0.97 + 0.03 * weave + 0.02 * (grain - 0.5);
            } else if (u_style > 1.5 && u_style < 2.5) {
                // Ink wash: darkness from brightness and edges, in a few ink tones on paper.
                float l = dot(col, vec3(0.299, 0.587, 0.114));
                float lx = dot(texture2D(u_texture, uv + vec2(1.5, 0.0) * texel).rgb, vec3(0.333))
                         - dot(texture2D(u_texture, uv - vec2(1.5, 0.0) * texel).rgb, vec3(0.333));
                float ly = dot(texture2D(u_texture, uv + vec2(0.0, 1.5) * texel).rgb, vec3(0.333))
                         - dot(texture2D(u_texture, uv - vec2(0.0, 1.5) * texel).rgb, vec3(0.333));
                float edge = clamp(length(vec2(lx, ly)) * 4.0, 0.0, 1.0);
                // Water is dark, so map its range to light washes; only the darkest
                // things (black koi, deep seams) become solid ink.
                float ink = clamp((0.34 - l) * 2.4, 0.0, 1.0);
                ink = floor(ink * 5.0 + 0.5) / 5.0 * 0.85;
                ink = max(ink, edge);
                vec3 paper = vec3(0.93, 0.90, 0.83) * (0.97 + 0.05 * grain);
                col = mix(paper, vec3(0.09, 0.09, 0.11), ink * 0.9);
            } else if (u_style > 2.5) {
                // Pixel art: a limited palette.
                // Limited palette with ordered dithering, so dark water doesn't band.
                vec2 cell = mod(floor(p / u_px), 2.0);
                float bayer = (cell.x * 2.0 + cell.y * 3.0 - cell.x * cell.y * 4.0) / 4.0 - 0.375;
                col = floor(col * 20.0 + 0.5 + bayer * 0.5) / 20.0;
            }

            gl_FragColor = vec4(col, 1.0);
        }
        """)
        s.uniforms = [
            SKUniform(name: "u_origin", vectorFloat2: .zero),
            SKUniform(name: "u_tex", vectorFloat2: vector_float2(1, 1)),
            SKUniform(name: "u_size", vectorFloat2: vector_float2(1, 1)),
            SKUniform(name: "u_style", float: 0),
            SKUniform(name: "u_px", float: 4),
            SKUniform(name: "u_paint", float: 3),
            SKUniform(name: "u_tilt", float: 0),
            SKUniform(name: "u_focus", float: 0.5),
            SKUniform(name: "u_band", float: 0.15),
        ]
        return s
    }

    static func update(_ scene: SKScene, config c: PondConfig) {
        scene.shouldEnableEffects = isActive(c)
        guard scene.shouldEnableEffects, let shader = scene.shader else { return }
        // Measured: the scene's own effect texture covers exactly the view, unlike an
        // SKEffectNode inside it (which covers its content's frame).
        let frame = CGRect(origin: .zero, size: scene.size)
        let styleValue: Float
        switch c.artStyle {
        case .natural: styleValue = 0
        case .painterly: styleValue = 1
        case .ink: styleValue = 2
        case .pixel: styleValue = 3
        }
        shader.uniformNamed("u_origin")?.vectorFloat2Value = vector_float2(Float(frame.minX), Float(frame.minY))
        shader.uniformNamed("u_tex")?.vectorFloat2Value = vector_float2(Float(max(1, frame.width)), Float(max(1, frame.height)))
        shader.uniformNamed("u_size")?.vectorFloat2Value = vector_float2(Float(scene.size.width), Float(scene.size.height))
        shader.uniformNamed("u_style")?.floatValue = styleValue
        shader.uniformNamed("u_px")?.floatValue = Float(c.pixelSize)
        shader.uniformNamed("u_paint")?.floatValue = Float(3 * min(scene.size.width, scene.size.height) / 1100)
        shader.uniformNamed("u_tilt")?.floatValue = c.tiltOn ? Float(c.tiltStrength) : 0
        shader.uniformNamed("u_focus")?.floatValue = Float(c.tiltFocus)
        shader.uniformNamed("u_band")?.floatValue = Float(c.tiltBand)
    }
}
