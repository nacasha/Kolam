// Style — a full-screen pass over the whole scene: art styles (painterly, ink wash,
// pixel art, watercolour, woodblock, dither, halftone, mosaic) and a tilt-shift
// focus blur. Runs only when one of them is on.

import SpriteKit

enum ArtStyle: String { case natural, painterly, ink, pixel, watercolor, woodblock, dither, halftone, mosaic }

/// Colour ramps for the dither style: darkest and lightest tone, and how many steps.
enum DitherPalette: String, CaseIterable {
    case gameboy, mono, sepia

    var dark: vector_float3 {
        switch self {
        case .gameboy: return vector_float3(0.06, 0.22, 0.06)
        case .mono: return vector_float3(0.08, 0.08, 0.10)
        case .sepia: return vector_float3(0.17, 0.10, 0.06)
        }
    }
    var light: vector_float3 {
        switch self {
        case .gameboy: return vector_float3(0.61, 0.74, 0.06)
        case .mono: return vector_float3(0.93, 0.91, 0.85)
        case .sepia: return vector_float3(0.95, 0.87, 0.70)
        }
    }
    var levels: Float { self == .mono ? 2 : 4 }
}

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
            float st = floor(u_style + 0.5);
            vec3 lw = vec3(0.299, 0.587, 0.114);

            // Pixel art and dither: sample one point per block.
            if (st == 3.0 || st == 6.0) {
                vec2 q = (floor(p / u_px) + 0.5) * u_px;
                uv = (q - u_origin) / u_tex;
            }

            // Halftone: a 45° grid of dots, each coloured from its centre.
            float hd = 0.0;
            if (st == 7.0) {
                vec2 r = vec2(p.x - p.y, p.x + p.y) * 0.7071;
                vec2 cc = (floor(r / u_dot) + 0.5) * u_dot;
                hd = length(r - cc) / u_dot;
                vec2 cw = vec2(cc.x + cc.y, cc.y - cc.x) * 0.7071;
                uv = (cw - u_origin) / u_tex;
            }

            // Mosaic: jittered Voronoi tiles, each coloured from its seed point.
            float mEdge = 99.0;
            float mTone = 0.0;
            if (st == 8.0) {
                vec2 g = p / u_tile;
                vec2 gi = floor(g);
                float f1 = 9.0;
                float f2 = 9.0;
                vec2 seed = gi + 0.5;
                for (int i = -1; i <= 1; i++) {
                    for (int j = -1; j <= 1; j++) {
                        vec2 cp = gi + vec2(float(i), float(j));
                        vec2 h = fract(sin(vec2(dot(cp, vec2(127.1, 311.7)), dot(cp, vec2(269.5, 183.3)))) * 43758.5453);
                        vec2 pt = cp + 0.15 + h * 0.7;
                        float d = length(g - pt);
                        if (d < f1) { f2 = f1; f1 = d; seed = pt; } else if (d < f2) { f2 = d; }
                    }
                }
                mEdge = (f2 - f1) * u_tile;
                mTone = fract(sin(dot(seed, vec2(41.3, 289.1))) * 43758.5453);
                uv = (seed * u_tile - u_origin) / u_tex;
            }

            // Tilt-shift: blur grows with distance from the in-focus band.
            float blur = 0.0;
            if (u_tilt > 0.0) {
                float ty = p.y / u_size.y;
                float away = max(0.0, abs(ty - u_focus) - u_band);
                blur = u_tilt * smoothstep(0.0, 0.3, away) * 16.0;
            }

            vec4 c;
            float wcEdge = 0.0;
            if (blur > 0.4) {
                c = texture2D(u_texture, uv);
                for (int i = 0; i < 12; i++) {
                    float a = float(i) * 0.5236;
                    float r = mod(float(i), 2.0) < 0.5 ? 1.0 : 0.55;
                    c += texture2D(u_texture, uv + vec2(cos(a), sin(a)) * r * blur * texel);
                }
                c /= 13.0;
            } else if (st == 1.0) {
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
            } else if (st == 4.0) {
                // Watercolour: wobble the lookup so colour bleeds, then soften it.
                vec2 w = vec2(sin(p.y * 0.031 + sin(p.x * 0.017) * 2.0),
                              cos(p.x * 0.029 + sin(p.y * 0.021) * 2.0)) * u_paint * 1.2;
                vec2 wuv = uv + w * texel;
                vec3 m = vec3(0.0);
                for (int i = -1; i <= 1; i++) {
                    for (int j = -1; j <= 1; j++) {
                        m += texture2D(u_texture, wuv + vec2(float(i), float(j)) * u_paint * 1.4 * texel).rgb;
                    }
                }
                m /= 9.0;
                wcEdge = length(texture2D(u_texture, wuv).rgb - m);
                c = vec4(m, 1.0);
            } else {
                c = texture2D(u_texture, uv);
            }

            vec3 col = c.rgb;
            float grain = fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453);

            if (st == 1.0) {
                // Painterly: a touch more colour, and canvas weave.
                float l = dot(col, lw);
                col = mix(vec3(l), col, 1.15);
                float weave = sin(p.x * 1.9) * sin(p.y * 1.9);
                col *= 0.97 + 0.03 * weave + 0.02 * (grain - 0.5);
            } else if (st == 2.0) {
                // Ink wash: darkness from brightness and edges, in a few ink tones on paper.
                float l = dot(col, lw);
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
            } else if (st == 3.0) {
                // Pixel art: a limited palette.
                // Limited palette with ordered dithering, so dark water doesn't band.
                vec2 cell = mod(floor(p / u_px), 2.0);
                float bayer = (cell.x * 2.0 + cell.y * 3.0 - cell.x * cell.y * 4.0) / 4.0 - 0.375;
                col = floor(col * 20.0 + 0.5 + bayer * 0.5) / 20.0;
            } else if (st == 4.0) {
                // Watercolour: layered washes, pigment pooling at edges, blotchy
                // granulation, and transparent paint over white paper.
                float l = dot(col, lw);
                col = mix(vec3(l), col, 1.1);
                col = mix(col, floor(col * 7.0 + 0.5) / 7.0, 0.5);
                col *= 1.0 - clamp(wcEdge * 3.0, 0.0, 0.35);
                float blot = sin(p.x * 0.013 + sin(p.y * 0.011) * 3.0) * sin(p.y * 0.017 + sin(p.x * 0.009) * 2.0);
                col *= 0.96 + 0.05 * blot;
                col = mix(col, vec3(0.97, 0.95, 0.90), 0.14) * (0.96 + 0.06 * grain);
            } else if (st == 5.0) {
                // Woodblock: flat printed colour, carved outlines, wood grain and washi.
                float lx = dot(texture2D(u_texture, uv + vec2(1.5, 0.0) * texel).rgb, lw)
                         - dot(texture2D(u_texture, uv - vec2(1.5, 0.0) * texel).rgb, lw);
                float ly = dot(texture2D(u_texture, uv + vec2(0.0, 1.5) * texel).rgb, lw)
                         - dot(texture2D(u_texture, uv - vec2(0.0, 1.5) * texel).rgb, lw);
                float edge = clamp((length(vec2(lx, ly)) - 0.04) * 6.0, 0.0, 1.0);
                vec3 g = pow(max(col, vec3(0.0)), vec3(0.7));
                g = mix(vec3(dot(g, lw)), g, 1.25);
                g = floor(clamp(g, 0.0, 1.0) * 4.0 + 0.5) / 4.0;
                col = pow(g, vec3(1.0 / 0.7));
                float fibre = fract(sin(dot(floor(p * vec2(0.5, 0.08)), vec2(12.9898, 78.233))) * 43758.5453);
                float wood = sin(p.y * 0.25 + sin(p.x * 0.013) * 8.0 + sin(p.x * 0.041) * 2.0);
                col = col * vec3(0.96, 0.93, 0.86) + vec3(0.03, 0.025, 0.015);
                col *= 0.95 + 0.03 * wood + 0.04 * fibre;
                col = mix(col, vec3(0.10, 0.10, 0.15), edge * 0.85);
            } else if (st == 6.0) {
                // Dither: brightness through a 4×4 Bayer matrix onto a small palette.
                float l = clamp(pow(max(dot(col, lw), 0.0), 0.75) * 1.25, 0.0, 1.0);
                vec2 cell = floor(p / u_px);
                vec2 c1 = mod(cell, 2.0);
                vec2 c2 = mod(floor(cell / 2.0), 2.0);
                float b1 = c1.x * 2.0 + c1.y * 3.0 - c1.x * c1.y * 4.0;
                float b2 = c2.x * 2.0 + c2.y * 3.0 - c2.x * c2.y * 4.0;
                float bayer = (4.0 * b1 + b2 + 0.5) / 16.0;
                float n = u_levels - 1.0;
                float lv = clamp(floor(l * n + bayer), 0.0, n) / n;
                col = mix(u_dark, u_light, lv);
            } else if (st == 7.0) {
                // Halftone: dot area grows with darkness; ink dots on off-white paper.
                float l = clamp(dot(col, lw) * 1.6, 0.0, 1.0);
                float radius = 0.72 * sqrt(1.0 - l);
                float aa = 1.0 / u_dot;
                float dotMask = 1.0 - smoothstep(radius - aa, radius + aa, hd);
                vec3 inkCol = clamp(mix(vec3(dot(col, lw)), col, 1.4) * 0.75, 0.0, 1.0);
                vec3 paper = vec3(0.95, 0.93, 0.87);
                col = mix(mix(paper, col, 0.15), inkCol, dotMask) * (0.97 + 0.04 * grain);
            } else if (st == 8.0) {
                // Mosaic: each tile a slightly different shade of glass, bevelled, in grout.
                float grout = 0.6 * u_paint;
                float l = dot(col, lw);
                col = mix(vec3(l), col, 1.15) * (0.92 + 0.16 * mTone);
                col *= 0.94 + 0.12 * smoothstep(grout, grout * 4.0, mEdge);
                col = mix(vec3(0.13, 0.12, 0.11), col, smoothstep(grout * 0.6, grout * 1.2, mEdge));
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
            SKUniform(name: "u_dot", float: 8),
            SKUniform(name: "u_tile", float: 22),
            SKUniform(name: "u_dark", vectorFloat3: DitherPalette.gameboy.dark),
            SKUniform(name: "u_light", vectorFloat3: DitherPalette.gameboy.light),
            SKUniform(name: "u_levels", float: 4),
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
        case .watercolor: styleValue = 4
        case .woodblock: styleValue = 5
        case .dither: styleValue = 6
        case .halftone: styleValue = 7
        case .mosaic: styleValue = 8
        }
        shader.uniformNamed("u_origin")?.vectorFloat2Value = vector_float2(Float(frame.minX), Float(frame.minY))
        shader.uniformNamed("u_tex")?.vectorFloat2Value = vector_float2(Float(max(1, frame.width)), Float(max(1, frame.height)))
        shader.uniformNamed("u_size")?.vectorFloat2Value = vector_float2(Float(scene.size.width), Float(scene.size.height))
        shader.uniformNamed("u_style")?.floatValue = styleValue
        shader.uniformNamed("u_px")?.floatValue = Float(c.pixelSize)
        shader.uniformNamed("u_paint")?.floatValue = Float(3 * min(scene.size.width, scene.size.height) / 1100)
        shader.uniformNamed("u_dot")?.floatValue = Float(c.halftoneSize)
        shader.uniformNamed("u_tile")?.floatValue = Float(c.mosaicSize)
        shader.uniformNamed("u_dark")?.vectorFloat3Value = c.ditherPalette.dark
        shader.uniformNamed("u_light")?.vectorFloat3Value = c.ditherPalette.light
        shader.uniformNamed("u_levels")?.floatValue = c.ditherPalette.levels
        shader.uniformNamed("u_tilt")?.floatValue = c.tiltOn ? Float(c.tiltStrength) : 0
        shader.uniformNamed("u_focus")?.floatValue = Float(c.tiltFocus)
        shader.uniformNamed("u_band")?.floatValue = Float(c.tiltBand)
    }
}
