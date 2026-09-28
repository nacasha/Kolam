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
    /// Keep the effect running even with nothing moving, so ripples starting or ending
    /// never switch the underwater layer between two render paths (a visible pop).
    static var keepEnabled = false
    /// Largest splash strength in use, so the edge fade can stay a fixed size.
    static var maxStrength: CGFloat = 0

    // MARK: Splashes

    private struct Splash {
        let center: CGPoint
        let start: CGFloat
        let strength: CGFloat
        /// Size of the ring relative to a click's (speed, wavelength and width all scale).
        let scale: CGFloat
        /// How fast it dies down, per second.
        let decay: CGFloat
        let life: CGFloat
    }

    /// The shader has a fixed number of splash slots; the oldest is dropped first.
    static let maxSplashes = 32
    private static var splashes: [Splash] = []

    static var isActive: Bool { amplitude > 0 || !splashes.isEmpty }

    /// A ring wave starting at `point`; `strength` is its peak displacement in points.
    /// `scale` < 1 makes a smaller, quicker ring (raindrops use about 0.4).
    static func splash(at point: CGPoint, strength: CGFloat, scale: CGFloat = 1) {
        guard strength > 0 else { return }
        let decay = 0.9 / max(0.3, scale)
        let new = Splash(center: point, start: time, strength: strength, scale: scale,
                         decay: decay, life: min(4, 3.6 / decay + 0.4))
        guard splashes.count >= maxSplashes else { splashes.append(new); return }
        // Full: replace the faintest ripple, but only if it's fainter than the new one;
        // otherwise skip the new one. Never cut off a ripple that's still clearly visible.
        func remaining(_ s: Splash) -> CGFloat { s.strength * exp(-(time - s.start) * s.decay) }
        guard let k = splashes.indices.min(by: { remaining(splashes[$0]) < remaining(splashes[$1]) }),
              remaining(splashes[k]) < strength * 0.15 else { return }
        splashes[k] = new
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
            let x = d - age * speed * s.scale
            let wd = width * s.scale
            guard abs(x) < wd * 3 else { continue }
            let envelope = exp(-(x * x) / (wd * wd)) * exp(-age * s.decay) * min(1, age * 8)
            let w = sin(x / (wavelength * s.scale) * 2 * .pi) * envelope * s.strength
            v.dx += dx / d * w
            v.dy += dy / d * w
        }
        return v
    }

    /// Outward push from the ripples passing a point: the direction away from each ripple's
    /// centre, weighted by how strongly its wave packet is there right now (no oscillation).
    static func push(at p: CGPoint) -> CGVector {
        var v = CGVector.zero
        for s in splashes {
            let age = time - s.start
            let dx = p.x - s.center.x, dy = p.y - s.center.y
            let d = max(0.001, hypot(dx, dy))
            let x = d - age * speed * s.scale
            let wd = width * s.scale
            guard abs(x) < wd * 3 else { continue }
            let envelope = exp(-(x * x) / (wd * wd)) * exp(-age * s.decay) * min(1, age * 8)
            // Strongest near the centre of small, fresh ripples.
            let w = envelope * s.strength * speed * s.scale / wavelength * 5
            v.dx += dx / d * w
            v.dy += dy / d * w
        }
        return v
    }

    /// Just the gentle swell, for bobbing.
    static func swell(at p: CGPoint) -> CGVector {
        guard amplitude > 0 else { return .zero }
        let t = time, l = length / (2 * .pi)
        return CGVector(dx: (sin(p.y / l + t * 0.35) + 0.5 * sin((p.x + p.y) / (l * 1.7) - t * 0.5)) * amplitude,
                        dy: (cos(p.x / l - t * 0.3) + 0.5 * cos((p.x - p.y) / (l * 2.3) + t * 0.42)) * amplitude)
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
        splashes.removeAll { now - $0.start > $0.life }
        effect.shouldEnableEffects = isActive || keepEnabled
        guard effect.shouldEnableEffects, let shader = effect.shader else { return }
        shader.uniformNamed("u_size")?.vectorFloat2Value = vector_float2(Float(size.width), Float(size.height))
        // The effect's texture covers its content's frame, which can reach past the screen
        // (fish crossing an edge), so map texture coordinates back to scene points explicitly.
        let frame = effect.calculateAccumulatedFrame()
        shader.uniformNamed("u_origin")?.vectorFloat2Value = vector_float2(Float(frame.minX), Float(frame.minY))
        shader.uniformNamed("u_tex")?.vectorFloat2Value = vector_float2(Float(max(1, frame.width)), Float(max(1, frame.height)))
        shader.uniformNamed("u_amp")?.floatValue = Float(amplitude)
        shader.uniformNamed("u_length")?.floatValue = Float(length)
        shader.uniformNamed("u_wtime")?.floatValue = Float(now)
        // Fixed by the settings, not by which ripples are active, so the edge fade never jumps.
        shader.uniformNamed("u_margin")?.floatValue = Float((amplitude * 1.5 + maxStrength) * 2 + 1)
        shader.uniformNamed("u_ring")?.vectorFloat3Value = vector_float3(Float(speed), Float(wavelength), Float(width))
        // Two splashes per 4×4 matrix (Metal caps a shader at 31 uniform buffers):
        // columns = [value, shape] of splash 2m, then [value, shape] of splash 2m + 1.
        var columns = [vector_float4](repeating: .zero, count: maxSplashes * 2)
        for k in 0..<maxSplashes {
            // value = x, y, age, strength (strength 0 = empty slot); shape = scale, decay.
            var value = vector_float4(0, 0, 0, 0)
            var shape = vector_float4(1, 1, 0, 0)
            if k < splashes.count {
                let s = splashes[k]
                value = vector_float4(Float(s.center.x), Float(s.center.y), Float(now - s.start), Float(s.strength))
                shape = vector_float4(Float(s.scale), Float(s.decay), 0, 0)
            }
            columns[k * 2] = value
            columns[k * 2 + 1] = shape
        }
        for m in 0..<maxSplashes / 2 {
            shader.uniformNamed("u_splashes\(m)")?.matrixFloat4x4Value =
                matrix_float4x4(columns[m * 4], columns[m * 4 + 1], columns[m * 4 + 2], columns[m * 4 + 3])
        }
    }

    /// Refraction for everything under the surface. Mirrors `offset(at:)`.
    static func makeRefraction() -> SKShader {
        // Inlined per slot: SpriteKit's GLSL→Metal translation rejects `inout`
        // parameters and uniforms referenced from helper functions.
        let splashBlocks = (0..<maxSplashes).map { k in """
            {
                vec4 s = u_splashes\(k / 2)[\(k % 2 * 2)];
                if (s.w > 0.0) {
                    vec4 q = u_splashes\(k / 2)[\(k % 2 * 2 + 1)];
                    vec2 v = p - s.xy;
                    float dist = max(0.001, length(v));
                    float x = dist - s.z * u_ring.x * q.x;
                    float wd = u_ring.z * q.x;
                    if (abs(x) < wd * 3.0) {
                        float envelope = exp(-(x * x) / (wd * wd)) * exp(-s.z * q.y) * min(1.0, s.z * 8.0);
                        float phase = x / (u_ring.y * q.x) * 6.28318;
                        d += v / dist * sin(phase) * envelope * s.w;
                        // The ring's slope catches the light: bright on one flank, dark on the other.
                        shade += cos(phase) * envelope * min(1.0, s.w / (8.0 * q.x));
                    }
                }
            }
        """ }.joined(separator: "\n")
        let s = SKShader(source: """
        void main() {
            vec2 p = u_origin + v_tex_coord * u_tex;
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
            vec2 uv = v_tex_coord + d * fade / u_tex;
            vec4 c = texture2D(u_texture, clamp(uv, 0.5 / u_tex, 1.0 - 0.5 / u_tex));
            c.rgb += clamp(shade, -1.5, 1.5) * 0.09 * fade * c.a;
            gl_FragColor = c;
        }
        """)
        s.uniforms = [
            SKUniform(name: "u_size", vectorFloat2: vector_float2(1, 1)),
            SKUniform(name: "u_origin", vectorFloat2: vector_float2(0, 0)),
            SKUniform(name: "u_tex", vectorFloat2: vector_float2(1, 1)),
            SKUniform(name: "u_amp", float: 0),
            SKUniform(name: "u_length", float: 90),
            SKUniform(name: "u_wtime", float: 0),
            SKUniform(name: "u_margin", float: 1),
            SKUniform(name: "u_ring", vectorFloat3: vector_float3(170, 30, 38)),
        ] + (0..<maxSplashes / 2).map { SKUniform(name: "u_splashes\($0)", matrixFloat4x4: matrix_float4x4()) }
        return s
    }
}

/// How something floating moves on the water: ripples push it away and it keeps
/// drifting until the water's drag slows it; the swell rocks it gently in place.
struct Floating {
    var velocity = CGVector.zero
    var spin: CGFloat = 0
    private var bob = CGVector.zero
    /// 1 = a petal-sized thing; heavier things (big pads) move less.
    var mass: CGFloat = 1

    /// Wind blowing across the surface, in points per second (set by the atmosphere).
    static var wind = CGVector.zero

    mutating func step(_ node: SKNode, dt: CGFloat) {
        var push = Wave.push(at: node.position)
        push.dx += Floating.wind.dx * 0.25
        push.dy += Floating.wind.dy * 0.25
        velocity.dx += push.dx / mass * dt
        velocity.dy += push.dy / mass * dt
        // A little spin from being shoved off-centre.
        spin += (push.dx - push.dy) / mass * dt * 0.0006
        let drag = exp(-dt * 0.9)
        velocity.dx *= drag
        velocity.dy *= drag
        spin *= exp(-dt * 1.2)
        node.position.x += velocity.dx * dt
        node.position.y += velocity.dy * dt
        node.zRotation += spin * dt

        // Smoothed swell bob, applied as a change so it never accumulates.
        let target = Wave.swell(at: node.position)
        let k = min(1, dt * 3)
        let next = CGVector(dx: bob.dx + (target.dx - bob.dx) * k, dy: bob.dy + (target.dy - bob.dy) * k)
        node.position.x += (next.dx - bob.dx) * 0.6
        node.position.y += (next.dy - bob.dy) * 0.6
        bob = next
    }
}
