// Wave — the moving surface. Underwater things are seen through it (the scene
// refracts them with a shader using this same field), and floating things bob on it.
// Besides the gentle swell, clicks send out ring waves ("splashes") that travel,
// spread and die down, bending everything they pass over.

import SpriteKit

enum Wave {
    /// Swell displacement in points (0 = off).
    static var amplitude: CGFloat = 0
    /// Swell wavelength in points.
    static var length: CGFloat = 90
    static var time: CGFloat = 0
    /// Scene unit (points per 1100th of the short screen side), for splash sizes.
    static var unit: CGFloat = 1

    // MARK: Splashes

    private struct Splash {
        let center: CGPoint
        let start: CGFloat
        let strength: CGFloat
    }

    /// The shader has a fixed number of splash slots; the oldest is dropped first.
    static let maxSplashes = 6
    private static var splashes: [Splash] = []
    private static let splashLife: CGFloat = 4
    /// Peak displacement of the strongest splash, used to keep edges from sampling outside.
    private static var splashPeak: CGFloat { splashes.map(\.strength).max() ?? 0 }

    static var isActive: Bool { amplitude > 0 || !splashes.isEmpty }

    /// A ring wave starting at `point`; `strength` is its peak displacement in points.
    static func splash(at point: CGPoint, strength: CGFloat) {
        guard strength > 0 else { return }
        splashes.append(Splash(center: point, start: time, strength: strength))
        if splashes.count > maxSplashes { splashes.removeFirst() }
    }

    // Ring shape: travels outward at `speed`, a short packet of `wavelength`, fading with age.
    private static var speed: CGFloat { 170 * unit }
    private static var wavelength: CGFloat { 30 * unit }
    private static var width: CGFloat { 38 * unit }

    private static func splashOffset(at p: CGPoint) -> CGVector {
        var v = CGVector.zero
        for s in splashes {
            let age = time - s.start
            let dx = p.x - s.center.x, dy = p.y - s.center.y
            let d = max(0.001, hypot(dx, dy))
            let x = d - age * speed
            let envelope = exp(-(x * x) / (width * width)) * exp(-age * 0.9) * min(1, age * 8)
            let w = sin(x / wavelength * 2 * .pi) * envelope * s.strength
            v.dx += dx / d * w
            v.dy += dy / d * w
        }
        return v
    }

    /// Sideways displacement of the surface at a point.
    static func offset(at p: CGPoint) -> CGVector {
        var v = CGVector.zero
        if amplitude > 0 {
            let t = time, l = length / (2 * .pi)
            v.dx = (sin(p.y / l + t * 0.35) + 0.5 * sin((p.x + p.y) / (l * 1.7) - t * 0.5)) * amplitude
            v.dy = (cos(p.x / l - t * 0.3) + 0.5 * cos((p.x - p.y) / (l * 2.3) + t * 0.42)) * amplitude
        }
        if !splashes.isEmpty {
            let s = splashOffset(at: p)
            v.dx += s.dx
            v.dy += s.dy
        }
        return v
    }

    /// Advances the clock, drops finished splashes and feeds the refraction shader.
    static func update(time now: CGFloat, effect: SKEffectNode, size: CGSize) {
        time = now
        splashes.removeAll { now - $0.start > splashLife }
        effect.shouldEnableEffects = isActive
        guard isActive, let shader = effect.shader else { return }
        shader.uniformNamed("u_size")?.vectorFloat2Value = vector_float2(Float(size.width), Float(size.height))
        shader.uniformNamed("u_amp")?.floatValue = Float(amplitude)
        shader.uniformNamed("u_length")?.floatValue = Float(length)
        shader.uniformNamed("u_wtime")?.floatValue = Float(now)
        shader.uniformNamed("u_margin")?.floatValue = Float((amplitude * 1.5 + splashPeak) * 2 + 1)
        shader.uniformNamed("u_ring")?.vectorFloat3Value = vector_float3(Float(speed), Float(wavelength), Float(width))
        for k in 0..<maxSplashes {
            // x, y, age, strength (strength 0 = empty slot).
            var value = vector_float4(0, 0, 0, 0)
            if k < splashes.count {
                let s = splashes[k]
                value = vector_float4(Float(s.center.x), Float(s.center.y), Float(now - s.start), Float(s.strength))
            }
            shader.uniformNamed("u_splash\(k)")?.vectorFloat4Value = value
        }
    }

    /// Refraction for everything under the surface. Mirrors `offset(at:)`.
    static func makeRefraction() -> SKShader {
        // Inlined per slot: SpriteKit's GLSL→Metal translation rejects `inout`
        // parameters and uniforms referenced from helper functions.
        let splashBlocks = (0..<maxSplashes).map { k in """
            {
                vec4 s = u_splash\(k);
                if (s.w > 0.0) {
                    vec2 v = p - s.xy;
                    float dist = max(0.001, length(v));
                    float x = dist - s.z * u_ring.x;
                    float envelope = exp(-(x * x) / (u_ring.z * u_ring.z)) * exp(-s.z * 0.9) * min(1.0, s.z * 8.0);
                    float phase = x / u_ring.y * 6.28318;
                    d += v / dist * sin(phase) * envelope * s.w;
                    // The ring's slope catches the light: bright on one flank, dark on the other.
                    shade += cos(phase) * envelope * min(1.0, s.w / 8.0);
                }
            }
        """ }.joined(separator: "\n")
        let s = SKShader(source: """
        void main() {
            vec2 p = v_tex_coord * u_size;
            float t = u_wtime;
            float l = u_length / 6.28318;
            vec2 d = vec2(sin(p.y / l + t * 0.35) + 0.5 * sin((p.x + p.y) / (l * 1.7) - t * 0.5),
                          cos(p.x / l - t * 0.3) + 0.5 * cos((p.x - p.y) / (l * 2.3) + t * 0.42)) * u_amp;
            float shade = 0.0;
        \(splashBlocks)
            // Fade the distortion out near the screen edges so it never samples
            // outside the pond (which would show black).
            vec2 edge = min(p, u_size - p);
            float fade = smoothstep(0.0, u_margin * 3.0, min(edge.x, edge.y));
            vec2 uv = v_tex_coord + d * fade / u_size;
            vec4 c = texture2D(u_texture, clamp(uv, 0.5 / u_size, 1.0 - 0.5 / u_size));
            c.rgb += shade * 0.07 * fade * c.a;
            gl_FragColor = c;
        }
        """)
        s.uniforms = [
            SKUniform(name: "u_size", vectorFloat2: vector_float2(1, 1)),
            SKUniform(name: "u_amp", float: 0),
            SKUniform(name: "u_length", float: 90),
            SKUniform(name: "u_wtime", float: 0),
            SKUniform(name: "u_margin", float: 1),
            SKUniform(name: "u_ring", vectorFloat3: vector_float3(170, 30, 38)),
        ] + (0..<maxSplashes).map { SKUniform(name: "u_splash\($0)", vectorFloat4: .zero) }
        return s
    }
}
