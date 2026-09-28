// PondScene — the pond itself, bottom to top: shader water, shadows, small fish,
// koi, the surface (pads, ripples, falling items), vines, dragonflies, the
// time-of-day and weather light, lightning, and fireflies.

import SpriteKit

final class PondScene: SKScene {
    private let water = SKSpriteNode(color: .black, size: .zero)
    private let shadowLayer = SKNode()
    /// Everything under the surface, drawn through the wave refraction shader.
    private let underwater = SKEffectNode()
    /// Holds everything inside the effect node, scaled by the surface render scale; the
    /// effect node scales back up, so its offscreen texture is smaller (less memory, less GPU).
    private let underwaterScaled = SKNode()
    /// Clips the underwater content to exactly the screen, so the effect node's
    /// texture never changes size when a fish crosses an edge (that shook the pond).
    private let underwaterClip = SKCropNode()
    private let underwaterMask = SKSpriteNode(color: .white, size: .zero)
    /// Two invisible points far outside the screen. They pin the effect's frame (and so its
    /// texture) to one fixed rect; otherwise it resized whenever a fish poked past an edge,
    /// which shifted the whole distortion and misplaced ripples.
    private let frameAnchors = [SKSpriteNode(color: .clear, size: CGSize(width: 1, height: 1)),
                                SKSpriteNode(color: .clear, size: CGSize(width: 1, height: 1))]
    private var anchorMargin: CGFloat { (400 * unit).rounded() }
    private let surfaceLayer = SKNode()
    private var koi: [Koi] = []
    private var pads: [LilyPad] = []
    private let minnowLayer = SKNode()
    private var schools: [MinnowSchool] = []
    private var dragonflies: [Dragonfly] = []
    private var frog: Frog?
    private var vines: SKNode?
    private let food = Food()
    private var turtle: Turtle?
    private var geometry: PondGeometry
    private var reeds: SKNode?
    private let atmosphere = Atmosphere()
    private let moods = KoiMoods()
    private var causticOffset = CGVector.zero
    private var causticClock: CGFloat = 0
    private var config = PondConfig.current
    private var elapsed: CGFloat = 0
    private var lastTime: TimeInterval?

    private var unit: CGFloat { min(size.width, size.height) / 1100 }

    override init(size: CGSize) {
        geometry = PondGeometry(size: size)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
        anchorPoint = .zero

        water.anchorPoint = .zero
        water.shader = Shaders.makeWater(floor: Floor.bake(size: size, style: config.floorStyle, lowRes: config.floorLowRes))
        water.zPosition = -10
        shader = Style.make()
        underwaterMask.anchorPoint = .zero
        underwaterClip.maskNode = underwaterMask
        underwater.addChild(underwaterScaled)
        underwaterScaled.addChild(underwaterClip)
        frameAnchors.forEach(underwaterScaled.addChild)
        setSurfaceScale(config.surfaceScale)
        underwaterClip.addChild(water)
        underwater.shader = Wave.makeRefraction()
        underwater.shouldRasterize = false
        addChild(underwater)

        shadowLayer.zPosition = -5
        underwaterClip.addChild(shadowLayer)

        minnowLayer.zPosition = -2
        underwaterClip.addChild(minnowLayer)

        surfaceLayer.zPosition = 1000
        addChild(surfaceLayer)

        addChild(atmosphere.overlay)
        addChild(atmosphere.flash)
        addChild(atmosphere.fireflyLayer)

        applyShadowAndWave(config)
        layoutWater()
        Shaders.applyWater(config)
        setKoiCount(config.koiCount)
        spawnPads()
        spawnMinnows()
        setDragonflyCount(config.dragonflies)
        setFrog(config.frog)
        setTurtle(config.turtle)
        buildVines()
        buildReeds()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Settings

    /// Applies changed settings, rebuilding only what they affect.
    func apply(_ new: PondConfig) {
        guard new != config else { return }
        let old = config
        config = new

        applyShadowAndWave(new)
        Shaders.applyWater(new)
        if new.surfaceScale != old.surfaceScale { setSurfaceScale(new.surfaceScale) }
        if new.floorStyle != old.floorStyle || new.floorLowRes != old.floorLowRes {
            water.shader = Shaders.makeWater(floor: Floor.bake(size: size, style: new.floorStyle, lowRes: new.floorLowRes))
        }
        // Size and water colour are baked into each fish, so those rebuild the school.
        if new.koiSize != old.koiSize || new.water != old.water || new.depth != old.depth
            || new.depthDarken != old.depthDarken || new.shadowBlur != old.shadowBlur {
            setKoiCount(0)
        }
        setKoiCount(new.koiCount)

        if new.padsOn != old.padsOn || new.padClusters != old.padClusters || new.flowers != old.flowers {
            spawnPads()
        }
        if new.minnowsOn != old.minnowsOn || new.minnowSchools != old.minnowSchools || new.water != old.water {
            spawnMinnows()
        }
        setDragonflyCount(new.dragonflies)
        if new.frog != old.frog { setFrog(new.frog) }
        let shadowsChanged = new.depth != old.depth || new.shadowStrength != old.shadowStrength
            || new.shadowDistance != old.shadowDistance || new.lightAngle != old.lightAngle || new.shadowBlur != old.shadowBlur
        if new.reedsOn != old.reedsOn || new.reedAmount != old.reedAmount
            || new.cattails != old.cattails || shadowsChanged {
            buildReeds()
        }
        if new.turtle != old.turtle || new.water != old.water || new.depth != old.depth
            || new.depthDarken != old.depthDarken { setTurtle(new.turtle) }
        if new.vinesOn != old.vinesOn || new.depth != old.depth || new.shadowStrength != old.shadowStrength
            || new.shadowDistance != old.shadowDistance || new.lightAngle != old.lightAngle { buildVines() }
    }

    private func setSurfaceScale(_ r: CGFloat) {
        let r = max(0.3, min(1, r))
        underwaterScaled.setScale(r)
        underwater.setScale(1 / r)
    }

    private func applyShadowAndWave(_ c: PondConfig) {
        Depth.set(c.depth, darken: c.depthDarken)
        Depth.shadowStrength = c.shadowStrength
        Depth.shadowBlur = c.shadowBlur
        Depth.shadowDistance = c.shadowDistance
        Depth.lightAngle = c.lightAngle
        Wave.amplitude = c.wobbleOn ? 4 * unit * c.wobbleIntensity : 0
        Wave.length = 320 * unit * c.wobbleSize
        Wave.unit = unit
        Ripple.unit = unit
        Ripple.realistic = c.splashOn
        Ripple.strength = c.splashStrength
        Wave.maxStrength = c.splashOn ? 9 * unit * c.splashStrength * 1.3 : 0
        Wave.windRipples = c.windRipplesOn ? c.windRipples : 0
        Wave.keepEnabled = c.splashOn || c.wobbleOn || c.windRipplesOn
        Koi.surfacingOn = c.surfacingOn
        Koi.surfacingRate = c.surfacingRate
    }

    // MARK: Creatures

    private func spawnMinnows() {
        schools.forEach { $0.remove() }
        schools = []
        guard config.minnowsOn else { return }
        let color = SKColor(red: 0.62, green: 0.70, blue: 0.66, alpha: 1).blended(withFraction: 0.35, of: config.water.mid(depth: Depth.visual))!
        schools = (0..<config.minnowSchools).map { _ in
            MinnowSchool(at: CGPoint(x: .random(in: geometry.swimRect.minX...geometry.swimRect.maxX),
                                     y: .random(in: geometry.swimRect.minY...geometry.swimRect.maxY)),
                         count: .random(in: 7...12), unit: unit, color: color, parent: minnowLayer)
        }
    }

    private func setDragonflyCount(_ count: Int) {
        while dragonflies.count > count {
            let d = dragonflies.removeLast()
            d.node.removeFromParent()
            d.shadow.removeFromParent()
        }
        while dragonflies.count < count {
            let d = Dragonfly(at: CGPoint(x: .random(in: 0...size.width), y: .random(in: 0...size.height)), unit: unit)
            addChild(d.node)
            shadowLayer.addChild(d.shadow)
            dragonflies.append(d)
        }
    }

    private func setFrog(_ on: Bool) {
        frog?.remove()
        frog = nil
        guard on else { return }
        frog = Frog(unit: unit)
        frog?.seat(on: pads)
    }

    private func setTurtle(_ on: Bool) {
        turtle?.remove()
        turtle = nil
        guard on else { return }
        let r = geometry.swimRect
        turtle = Turtle(at: CGPoint(x: .random(in: r.minX...r.maxX), y: .random(in: r.minY...r.maxY)), unit: unit,
                        water: config.water.mid(depth: Depth.visual), underwater: underwaterClip, shadows: shadowLayer)
    }

    /// Reeds along the edges of the pond.
    private func buildReeds() {
        reeds?.removeFromParent()
        reeds = nil
        guard config.reedsOn else { return }
        let r = Reeds.build(geometry, unit: unit, amount: config.reedAmount, cattails: config.cattails)
        addChild(r)
        reeds = r
    }

    private func buildVines() {
        vines?.removeFromParent()
        vines = nil
        guard config.vinesOn else { return }
        let v = Vines.build(in: CGRect(origin: .zero, size: size), unit: unit)
        addChild(v)
        vines = v
    }

    // MARK: Koi

    private func setKoiCount(_ count: Int) {
        while koi.count > count {
            let fish = koi.removeLast()
            fish.node.removeFromParent()
            fish.shadowNode.removeFromParent()
        }
        while koi.count < count {
            // Cycle through varieties so any count shows a good mix.
            let variety = KoiVariety.all[(koi.count + Int.random(in: 0..<KoiVariety.all.count)) % KoiVariety.all.count]
            let depth = CGFloat.random(in: 0...1)
            let r = geometry.swimRect.insetBy(dx: geometry.swimRect.width * 0.1, dy: geometry.swimRect.height * 0.1)
            let pos = CGPoint(x: .random(in: r.minX...r.maxX), y: .random(in: r.minY...r.maxY))
            let fish = Koi(at: pos, scale: unit * config.koiSize * .random(in: 1.3...1.9), depth: depth,
                           variety: variety, water: config.water.mid(depth: Depth.visual))
            // Deeper fish sit lower in the stack so shallow ones swim over them.
            fish.node.zPosition = (1 - depth) * 900
            underwaterClip.addChild(fish.node)
            shadowLayer.addChild(fish.shadowNode)
            fish.onGulp = { [unowned self] p in
                Ripple.spawn(at: p, in: surfaceLayer, size: 55 * unit, rings: 2, strength: 0.4)
            }
            koi.append(fish)
        }
    }

    // MARK: Lily pads

    /// Clusters of 2–4 pads, some with flowers. Pads float above the fish.
    private func spawnPads() {
        pads.forEach { $0.node.removeFromParent(); $0.shadow.removeFromParent() }
        pads = []
        guard config.padsOn else { return }
        for _ in 0..<config.padClusters {
            let area = geometry.swimRect
            let center = CGPoint(x: .random(in: area.minX...area.maxX), y: .random(in: area.minY...area.maxY))
            for _ in 0..<Int.random(in: 2...4) {
                let pos = CGPoint(x: center.x + .random(in: -110...110) * unit,
                                  y: center.y + .random(in: -90...90) * unit)
                let flower = config.flowers && .random(in: 0...1) < 0.22
                let pad = LilyPad(at: pos, radius: .random(in: 34...62) * unit, flower: flower)
                shadowLayer.addChild(pad.shadow)
                surfaceLayer.addChild(pad.node)
                pads.append(pad)
            }
        }
        frog?.seat(on: pads)
    }

    // MARK: Interaction

    func dropFood(at point: CGPoint) {
        food.drop(at: point, unit: unit, surface: surfaceLayer, shadows: shadowLayer)
    }

    override func mouseDown(with event: NSEvent) {
        let point = event.location(in: self)
        Ripple.spawn(at: point, in: surfaceLayer, size: 240 * unit)
        if config.feedOn {
            food.drop(at: point, unit: unit, surface: surfaceLayer, shadows: shadowLayer)
            return
        }
        guard config.clickLure else { return }
        let reach = max(size.width, size.height) * 0.45
        koi.forEach { $0.notice(point, reach: reach) }
    }

    // MARK: Layout & frame loop

    override func didChangeSize(_ oldSize: CGSize) {
        layoutWater()
    }

    private func layoutWater() {
        underwaterMask.size = size
        frameAnchors[0].position = CGPoint(x: -anchorMargin + 0.5, y: -anchorMargin + 0.5)
        frameAnchors[1].position = CGPoint(x: size.width + anchorMargin - 0.5, y: size.height + anchorMargin - 0.5)
        water.size = size
        water.setValue(SKAttributeValue(vectorFloat2: vector_float2(Float(size.width), Float(size.height))),
                       forAttribute: "a_size")
    }

    override func update(_ currentTime: TimeInterval) {
        // Clamp so a long pause (covered, asleep) doesn't teleport the fish.
        let dt = CGFloat(min(currentTime - (lastTime ?? currentTime), 1.0 / 20))
        lastTime = currentTime
        elapsed += dt
        Wave.update(time: elapsed, effect: underwater, size: size)
        Style.update(self, config: config)
        let screen = CGRect(origin: .zero, size: size)
        let bounds = geometry.swimRect
        food.update(dt: dt, koi: koi, unit: unit) { [unowned self] p in
            Ripple.spawn(at: p, in: surfaceLayer, size: 70 * unit, rings: 2, strength: 0.5)
        }
        let koiDt = dt * config.koiSpeed
        for fish in koi {
            fish.update(dt: koiDt, bounds: bounds, others: koi)
        }
        for pad in pads {
            pad.update(dt: dt, time: elapsed, bounds: bounds)
        }
        for school in schools {
            school.update(dt: dt, bounds: bounds, koi: koi, follow: config.minnowFollow)
        }
        for d in dragonflies {
            d.update(dt: dt, bounds: screen)
        }
        frog?.update(dt: dt, pads: pads, surface: surfaceLayer)
        turtle?.update(dt: dt, bounds: bounds, pads: pads, surface: surfaceLayer)
        moods.update(dt: koiDt, koi: koi, bounds: bounds, unit: unit, moods: config.koiMoods, chase: config.koiChase)
        PlantLean.apply(to: reeds, windAngle: Wave.windAngle, strength: atmosphere.windStrength,
                        enabled: config.plantsLean, dt: dt)
        PlantLean.apply(to: vines, windAngle: Wave.windAngle, strength: atmosphere.windStrength,
                        enabled: config.plantsLean, dt: dt)
        // Caustics: drift downwind and flicker faster as the wind picks up.
        let flowing = config.causticsFlow ? min(4, atmosphere.windStrength) : 0
        causticOffset.dx += atmosphere.wind.dx * 0.35 * (flowing > 0 ? 1 : 0) * dt
        causticOffset.dy += atmosphere.wind.dy * 0.35 * (flowing > 0 ? 1 : 0) * dt
        causticClock += dt * (1 + 0.45 * flowing)
        Shaders.applyFlow(offset: causticOffset, clock: causticClock,
                          treeSize: config.treesOn ? 190 * unit * config.treeSize : 0)
        Floating.wind = atmosphere.wind
        Wave.windAngle = atan2(atmosphere.wind.dy, atmosphere.wind.dx)
        Wave.windStrength = atmosphere.windStrength
        // Plants sway faster in stronger wind.
        let sway = 0.6 + 0.5 * min(4, atmosphere.windStrength)
        reeds?.speed = sway
        vines?.speed = sway
        atmosphere.update(dt: dt, config: config, bounds: screen, pond: bounds, unit: unit, surface: surfaceLayer, shadows: shadowLayer)
    }
}

enum Shaders {
    private static let lo = SKUniform(name: "u_lo", vectorFloat3: .zero)
    private static let hi = SKUniform(name: "u_hi", vectorFloat3: .zero)
    private static let spotDark = SKUniform(name: "u_spot_dark", vectorFloat3: .zero)
    private static let spotLight = SKUniform(name: "u_spot_light", vectorFloat3: .zero)
    private static let depth = SKUniform(name: "u_depth", float: 0.7)
    private static let floorOn = SKUniform(name: "u_floor_on", float: 1)
    private static let lightColor = SKUniform(name: "u_light_color", vectorFloat3: .zero)
    private static let lightAmount = SKUniform(name: "u_light_amount", float: 0)
    private static let drift = SKUniform(name: "u_drift", float: 0)
    private static let sky = SKUniform(name: "u_sky", float: 0)
    private static let rain = SKUniform(name: "u_rain", float: 0)
    private static let night = SKUniform(name: "u_night", float: 0)

    /// Shared by every display's scene, so one update recolours them all.
    static func applyWater(_ config: PondConfig) {
        lo.vectorFloat3Value = config.water.lo / 255
        hi.vectorFloat3Value = config.water.hi / 255
        spotDark.vectorFloat3Value = config.water.spotDark / 255
        spotLight.vectorFloat3Value = config.water.spotLight / 255
        depth.floatValue = Float(Depth.visual)
        floorOn.floatValue = config.floorStyle == .plain ? 0 : 1
        lightColor.vectorFloat3Value = config.water.light
        lightAmount.floatValue = config.wavesOn ? Float(0.22 * config.waveIntensity) : 0
        drift.floatValue = config.driftOn ? Float(config.driftIntensity) : 0
        sky.floatValue = config.skyOn ? 1 : 0
    }

    private static let flow = SKUniform(name: "u_flow", vectorFloat4: .zero)
    private static let trees = SKUniform(name: "u_trees", vectorFloat4: .zero)

    /// Caustic drift (offset in points and a clock that runs faster in wind), and tree
    /// reflection size in points (0 = off).
    static func applyFlow(offset: CGVector, clock: CGFloat, treeSize: CGFloat) {
        flow.vectorFloat4Value = vector_float4(Float(offset.dx), Float(offset.dy), Float(clock), 0)
        trees.vectorFloat4Value = vector_float4(Float(treeSize), Float(clock), 0, 0)
    }

    static func applyAtmosphere(rain r: CGFloat, night n: CGFloat) {
        rain.floatValue = Float(r)
        night.floatValue = Float(n)
    }

    /// Procedural water over the baked floor: floor colours, a water column that
    /// thickens with depth, drifting caustic light, and surface reflections.
    /// Colour uniforms are shared by every display; each scene has its own floor texture.
    static func makeWater(floor: SKTexture) -> SKShader {
        let s = SKShader(source: """
        // Tileable caustics, after "Tileable Water Caustic" by Dave_Hoskins.
        float caustic(vec2 px, float period, float t) {
            vec2 p = mod(px / period * 6.28318, 6.28318) - 250.0;
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
            return clamp(pow(abs(c), 8.0), 0.0, 1.0);
        }

        // Height of a row of rounded tree crowns at position x (crowns about `spacing` apart).
        float crowns(float x, float spacing, float seed) {
            float c = floor(x / spacing);
            float h = 0.0;
            for (int k = -1; k <= 1; k++) {
                float id = c + float(k);
                float r1 = fract(sin(id * 127.1 + seed) * 43758.5453);
                float r2 = fract(sin(id * 311.7 + seed) * 12543.123);
                float centre = (id + 0.2 + r1 * 0.6) * spacing;
                float radius = spacing * (0.38 + r2 * 0.3);
                float height = 0.3 + 0.7 * r1 * r2 + 0.25 * r2;
                float u = (x - centre) / radius;
                h = max(h, sqrt(max(0.0, 1.0 - u * u)) * height);
            }
            return h;
        }

        float hash21(vec2 p) {
            p = fract(p * vec2(123.34, 456.21));
            p += dot(p, p + 45.32);
            return fract(p.x * p.y);
        }

        float vnoise(vec2 p) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            f = f * f * (3.0 - 2.0 * f);
            return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
                       mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
        }

        void main() {
            // Pond floor: mottled lo→hi colour with pebbles, lit from the top-left.
            vec4 fl = texture2D(u_floor, v_tex_coord);
            float n = mix(0.5, fl.r, u_floor_on);
            vec3 floorCol = mix(u_lo, u_hi, n);
            floorCol = mix(floorCol, u_spot_dark, fl.g * u_floor_on);
            floorCol = mix(floorCol, u_spot_light, fl.b * u_floor_on);
            floorCol *= 1.0 - (v_tex_coord.x * 0.5 + (1.0 - v_tex_coord.y) * 0.5) * 0.35;

            // Water column: deeper water hides the floor under its own tint and darkens it.
            vec3 col = mix(floorCol, u_lo * 0.6, u_depth * 0.55) * (0.95 - 0.6 * u_depth);

            vec2 px = v_tex_coord * a_size;
            // Rain and night mute the light on the water.
            float calm = (1.0 - 0.5 * u_rain - 0.6 * u_night) * (1.3 - u_depth);

            if (u_light_amount > 0.0) {
                // The clock runs faster in wind, and the pattern drifts downwind.
                float t = u_flow.z * 0.18 + 23.0;
                vec2 fp = px - u_flow.xy;
                // Two caustic layers at different scales and angles, so the tiling never lines up.
                vec2 q = mat2(0.8, -0.6, 0.6, 0.8) * (px - u_flow.xy * 0.7);
                float light = caustic(fp, 900.0, t) * 0.6 + caustic(q + 311.0, 610.0, t * 0.83 + 7.0) * 0.4;
                col += u_light_color * light * u_light_amount * calm;
            }

            // Drifting light: large soft patches of brightness wandering slowly.
            if (u_drift > 0.0) {
                float d = vnoise(px / 650.0 + vec2(u_time * 0.015, u_time * 0.011)) * 0.65
                        + vnoise(px / 300.0 - vec2(u_time * 0.02, -u_time * 0.01)) * 0.35;
                col += u_light_color * smoothstep(0.5, 0.85, d) * u_drift * 0.09 * calm;
            }

            // Sky reflections: long pale streaks, like clouds mirrored on the surface.
            if (u_sky > 0.0) {
                vec2 r = mat2(0.92, 0.38, -0.38, 0.92) * px;
                float s = vnoise(vec2(r.x / 1500.0 + u_time * 0.008, r.y / 220.0));
                vec3 skyCol = mix(vec3(0.70, 0.82, 0.88), vec3(0.20, 0.26, 0.45), u_night);
                col = mix(col, skyCol, smoothstep(0.55, 0.95, s) * u_sky * 0.10);
            }

            // Tree reflections: dark, leafy crowns mirrored along the top and upper sides,
            // swaying slowly. They're under the surface pass, so ripples bend them too.
            if (u_trees.x > 0.0) {
                float sz = u_trees.x;
                float tt = u_trees.y;
                float sway = sin(tt * 0.45) * 7.0 + sin(tt * 0.19 + 1.0) * 5.0;
                float top = a_size.y - px.y;
                float xx = px.x + sway;
                // Big crowns in front, smaller ones peeking out behind, lumpy leafy edges.
                float edgeN = (vnoise(vec2(xx / 22.0, top / 22.0)) - 0.5) * 30.0;
                float h = sz * max(crowns(xx, 300.0, 1.0), crowns(xx + 120.0, 170.0, 7.0) * 0.55) + edgeN;
                float m = 1.0 - smoothstep(h - 34.0, h + 10.0, top);
                float yy = px.y + sway * 0.6;
                float hs = sz * 0.7 * max(crowns(yy, 260.0, 3.0), crowns(yy + 80.0, 150.0, 9.0) * 0.55)
                         + (vnoise(vec2(yy / 22.0, px.x / 22.0)) - 0.5) * 30.0;
                float upper = smoothstep(a_size.y * 0.3, a_size.y * 0.8, px.y);
                m = max(m, (1.0 - smoothstep(hs - 34.0, hs + 10.0, px.x)) * upper);
                m = max(m, (1.0 - smoothstep(hs - 34.0, hs + 10.0, a_size.x - px.x)) * upper);
                // Gaps between leaves let the water show through.
                vec2 lp = (px + vec2(sway * 1.5, 0.0)) / 30.0;
                float leaves = vnoise(lp) * 0.6 + vnoise(lp * 2.7 + 9.0) * 0.4;
                m *= 0.6 + 0.4 * smoothstep(0.3, 0.75, leaves);
                vec3 treeCol = mix(vec3(0.04, 0.09, 0.05), vec3(0.01, 0.02, 0.04), u_night);
                col = mix(col, treeCol, m * 0.58);
            }

            gl_FragColor = vec4(col, 1.0);
        }
        """)
        s.attributes = [SKAttribute(name: "a_size", type: .vectorFloat2)]
        s.uniforms = [lo, hi, spotDark, spotLight, depth, floorOn, lightColor, lightAmount, drift, sky, rain, night, flow, trees,
                      SKUniform(name: "u_floor", texture: floor)]
        return s
    }
}
