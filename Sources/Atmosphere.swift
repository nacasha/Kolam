// Atmosphere — weather and seasons, and what they bring: raindrop ripples,
// fireflies at night, falling petals/leaves/snow, and a darkening overlay.

import SpriteKit

enum Weather: String, CaseIterable { case clear, cloudy, rain, storm, windy }

/// Fixed times of day, as hours on a 24-hour clock.
enum TimeOfDay: String, CaseIterable {
    case dawn, morning, day, afternoon, sunset, dusk, night

    var hour: CGFloat {
        switch self {
        case .dawn: return 6
        case .morning: return 8.5
        case .day: return 12.5
        case .afternoon: return 15.5
        case .sunset: return 18.3
        case .dusk: return 19.4
        case .night: return 23
        }
    }
}

/// Lighting for an hour of the day: a colour the whole scene is multiplied by,
/// and how "night" it is (drives fireflies and the water's moonlit sky).
struct DayLight {
    let tint: SIMD3<Float>
    let night: CGFloat

    init(hour h: CGFloat) {
        // Key colours through the day; the tint blends between the two nearest.
        let keys: [(CGFloat, SIMD3<Float>)] = [
            (0, [0.30, 0.34, 0.52]), (4.8, [0.30, 0.34, 0.52]),
            (6, [0.86, 0.72, 0.78]),      // dawn: pink-violet
            (7.5, [1.0, 0.90, 0.80]),     // early morning: warm
            (9.5, [0.98, 0.99, 1.0]),     // morning: fresh
            (13, [1.0, 1.0, 1.0]),        // midday
            (16, [1.0, 0.94, 0.84]),      // afternoon: golden
            (18.3, [1.0, 0.66, 0.46]),    // sunset: orange
            (19.4, [0.60, 0.52, 0.70]),   // dusk: purple
            (20.6, [0.30, 0.34, 0.52]),   // night: blue
            (24, [0.30, 0.34, 0.52]),
        ]
        let hh = (h.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        var k = 0
        while k < keys.count - 2, keys[k + 1].0 <= hh { k += 1 }
        let (h0, c0) = keys[k], (h1, c1) = keys[k + 1]
        let t = Float(max(0, min(1, (hh - h0) / max(0.001, h1 - h0))))
        let s = t * t * (3 - 2 * t)
        tint = c0 + (c1 - c0) * s
        // Night: full after 20.6h and before 4.8h, fading across dusk and dawn.
        let n: CGFloat
        if hh >= 20.6 || hh < 4.8 { n = 1 }
        else if hh > 19 { n = (hh - 19) / 1.6 }
        else if hh < 6.2 { n = 1 - (hh - 4.8) / 1.4 }
        else { n = 0 }
        night = max(0, min(1, n))
    }
}

/// auto = rains when the weather says so; always = rain in any weather; never = no rain,
/// and auto weather skips its rainy phase.
enum RainMode: String { case auto, always, never }
enum Season: String, CaseIterable { case spring, summer, autumn, winter }

extension Textures {
    /// Almond-shaped leaf pointing along +x, with a faint midrib.
    static let leaf = make(size: CGSize(width: 64, height: 28)) { ctx, r in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1, y: r.midY))
        path.addQuadCurve(to: CGPoint(x: r.maxX - 1, y: r.midY), control: CGPoint(x: r.midX, y: r.maxY + 8))
        path.addQuadCurve(to: CGPoint(x: 1, y: r.midY), control: CGPoint(x: r.midX, y: r.minY - 8))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setBlendMode(.destinationOut)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.3))
        ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: 4, y: r.midY))
        ctx.addLine(to: CGPoint(x: r.maxX - 6, y: r.midY))
        ctx.strokePath()
    }
}

struct SeasonStyle {
    let kind: Floater.Kind
    /// Items per second per million square points, at 100% amount.
    let rate: CGFloat
    let colors: [SKColor]

    static func of(_ season: Season) -> SeasonStyle {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SKColor { SKColor(red: r, green: g, blue: b, alpha: 1) }
        switch season {
        case .spring:
            return SeasonStyle(kind: .petal, rate: 0.7,
                               colors: [rgb(0.99, 0.78, 0.84), rgb(0.97, 0.66, 0.76), rgb(1.0, 0.90, 0.93)])
        case .summer:
            return SeasonStyle(kind: .leaf, rate: 0.15,
                               colors: [rgb(0.36, 0.60, 0.26), rgb(0.46, 0.68, 0.30)])
        case .autumn:
            return SeasonStyle(kind: .leaf, rate: 0.6,
                               colors: [rgb(0.90, 0.45, 0.14), rgb(0.80, 0.24, 0.12), rgb(0.93, 0.68, 0.22), rgb(0.55, 0.32, 0.16)])
        case .winter:
            return SeasonStyle(kind: .snow, rate: 2.5, colors: [rgb(0.96, 0.98, 1.0)])
        }
    }
}

// MARK: - Falling item

/// A petal, leaf or snowflake: falls (drawn larger, shadow far away), lands on
/// the water, drifts with the wind, then fades. Snow melts right after landing.
final class Floater {
    enum Kind { case petal, leaf, snow }

    let node: SKSpriteNode
    let shadow: SKSpriteNode
    let kind: Kind
    private var height: CGFloat = 1
    private var life: CGFloat
    private let fullLife: CGFloat
    private let spin = CGFloat.random(in: -1...1)
    private let fallTime = CGFloat.random(in: 2.5...4.5)
    private let seed = CGFloat.random(in: 0...100)
    private let unit: CGFloat
    private var t: CGFloat = 0
    private var landed = false
    private var floating = Floating()

    var isDead: Bool { life <= 0 }

    init(kind: Kind, color: SKColor, at p: CGPoint, unit u: CGFloat) {
        self.kind = kind
        unit = u
        let texture: SKTexture, size: CGSize
        switch kind {
        case .petal: (texture, size) = (Textures.petal, CGSize(width: 7 * u, height: 12 * u))
        case .leaf: (texture, size) = (Textures.leaf, CGSize(width: 22 * u, height: 10 * u))
        case .snow: (texture, size) = (Textures.softCircle, CGSize(width: 7 * u, height: 7 * u))
        }
        let s = CGFloat.random(in: 0.75...1.3)
        node = SKSpriteNode(texture: texture)
        node.color = color
        node.colorBlendFactor = 1
        node.size = CGSize(width: size.width * s, height: size.height * s)
        node.position = p
        node.zRotation = .random(in: 0..<(2 * .pi))
        node.zPosition = 10

        shadow = SKSpriteNode(texture: texture)
        shadow.color = .black
        shadow.colorBlendFactor = 1
        shadow.size = node.size

        fullLife = kind == .snow ? 1.4 : .random(in: 18...30)
        life = fullLife
        update(dt: 0, wind: .zero)
    }

    /// Returns true on the frame the item touches the water.
    @discardableResult
    func update(dt: CGFloat, wind: CGVector) -> Bool {
        t += dt
        var touched = false
        let flutter: CGFloat = kind == .snow ? 0.3 : 1
        if !landed {
            height -= dt / fallTime
            // Flutter sideways while falling; higher up, the wind carries it faster.
            node.position.x += (wind.dx * (1 + height * 2) + sin(t * 2.2 + seed) * 18 * unit * flutter) * dt
            node.position.y += wind.dy * (1 + height * 2) * dt
            node.zRotation += spin * 2.5 * flutter * dt
            if height <= 0 {
                height = 0
                landed = true
                touched = true
            }
        } else {
            node.position.x += wind.dx * 0.4 * dt
            node.position.y += wind.dy * 0.4 * dt
            node.zRotation += spin * 0.15 * dt
            life -= dt
            floating.step(node, dt: dt)
        }

        let fade = landed ? min(1, life / (kind == .snow ? fullLife : 3)) : min(1, (1 - height) * 4)
        node.setScale(1 + height * 0.8)
        node.alpha = (kind == .snow ? 0.85 : 1) * fade
        let lift = (6 + height * 70) * unit
        let o = Depth.offset(CGVector(dx: lift * 0.6, dy: -lift))
        shadow.position = CGPoint(x: node.position.x + o.dx, y: node.position.y + o.dy)
        shadow.zRotation = node.zRotation
        shadow.setScale(1 + height * 0.8)
        shadow.alpha = 0.22 * (1 - height * 0.7) * fade * Depth.shadowAlpha
        return touched
    }
}

// MARK: - Firefly

final class Firefly {
    let node = SKSpriteNode(texture: Textures.softCircle)
    private var base: CGPoint
    private let seed = CGFloat.random(in: 0...1000)
    private let unit: CGFloat
    private var t: CGFloat = 0

    init(in bounds: CGRect, unit u: CGFloat) {
        unit = u
        base = CGPoint(x: .random(in: bounds.minX...bounds.maxX), y: .random(in: bounds.minY...bounds.maxY))
        node.color = SKColor(red: 0.82, green: 1.0, blue: 0.45, alpha: 1)
        node.colorBlendFactor = 1
        node.blendMode = .add
        let s = CGFloat.random(in: 22...34) * u
        node.size = CGSize(width: s, height: s)
        node.alpha = 0
    }

    func update(dt: CGFloat, night: CGFloat, bounds: CGRect) {
        t += dt
        base.x += sin(t * 0.3 + seed) * 25 * unit * dt
        base.y += cos(t * 0.23 + seed * 1.3) * 25 * unit * dt
        if !bounds.contains(base) { base = CGPoint(x: bounds.midX + .random(in: -1...1) * bounds.width / 2.5,
                                                   y: bounds.midY + .random(in: -1...1) * bounds.height / 2.5) }
        node.position = CGPoint(x: base.x + sin(t * 1.3 + seed) * 12 * unit, y: base.y + cos(t * 1.1 + seed) * 10 * unit)
        let blink = pow(max(0, sin(t * 0.9 + seed)), 3)
        node.alpha = night * (0.12 + 0.88 * blink)
    }
}

// MARK: - Atmosphere

final class Atmosphere {
    /// Multiplied over the whole pond: time-of-day colour, dimmed by clouds and rain.
    let overlay = SKSpriteNode(color: .white, size: .zero)
    /// Lightning: a white flash added on top.
    let flash = SKSpriteNode(color: .white, size: .zero)
    let fireflyLayer = SKNode()

    /// 0…1 blend weights, eased so changes fade over several seconds.
    private(set) var rain: CGFloat = 0
    private(set) var night: CGFloat = 0
    private(set) var clouds: CGFloat = 0
    private(set) var wind = CGVector.zero
    /// Current wind strength multiplier (1 = a light breeze), including gusts.
    private(set) var windStrength: CGFloat = 1
    private var tint = SIMD3<Float>(1, 1, 1)

    private var windAngle = CGFloat.random(in: 0..<(2 * .pi))
    private var windLevel: CGFloat = 1
    private var weatherIndex = 0
    private var seasonIndex = 0
    private var weatherClock: CGFloat = 0
    private var seasonClock: CGFloat = 0
    private var cycleHour: CGFloat = 7
    private var floaters: [Floater] = []
    private var fireflies: [Firefly] = []
    private var rainDue: CGFloat = 0
    private var rainTime: CGFloat = 0
    private var fallDue: CGFloat = 0
    private var nextLightning: CGFloat = 5
    private var time: CGFloat = 0

    /// Auto mode timings, as in the original page.
    private static let weatherPeriod: CGFloat = 75
    private static let seasonPeriod: CGFloat = 240
    /// Auto weather order: mostly fair, now and then rain or a storm.
    private static let autoWeather: [Weather] = [.clear, .cloudy, .rain, .clear, .windy, .cloudy, .storm, .clear]

    init() {
        overlay.anchorPoint = .zero
        overlay.zPosition = 1500
        overlay.blendMode = .multiply
        overlay.colorBlendFactor = 1
        flash.anchorPoint = .zero
        flash.zPosition = 1510
        flash.blendMode = .add
        flash.alpha = 0
        fireflyLayer.zPosition = 3000
    }

    func weather(_ c: PondConfig) -> Weather { c.weather ?? Self.autoWeather[weatherIndex] }
    func season(_ c: PondConfig) -> Season { c.season ?? Season.allCases[seasonIndex] }

    /// Hour of day (0–24) for the current setting.
    func hour(_ c: PondConfig, dt: CGFloat) -> CGFloat {
        switch c.timeMode {
        case .clock:
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
            return CGFloat(parts.hour ?? 12) + CGFloat(parts.minute ?? 0) / 60 + CGFloat(parts.second ?? 0) / 3600
        case .cycle:
            cycleHour = (cycleHour + dt * 24 / max(60, c.cycleMinutes * 60)).truncatingRemainder(dividingBy: 24)
            return cycleHour
        case .fixed(let t):
            return t.hour
        }
    }

    /// `pond` is where rain and falling items land (the water, not the bank).
    func update(dt: CGFloat, config c: PondConfig, bounds: CGRect, pond: CGRect, unit u: CGFloat, surface: SKNode, shadows: SKNode) {
        time += dt
        weatherClock += dt
        if weatherClock > Self.weatherPeriod {
            weatherClock = 0
            weatherIndex = (weatherIndex + 1) % Self.autoWeather.count
            let w = Self.autoWeather[weatherIndex]
            if c.rainMode == .never, w == .rain || w == .storm {
                weatherIndex = (weatherIndex + 1) % Self.autoWeather.count
            }
        }
        seasonClock += dt
        if seasonClock > Self.seasonPeriod {
            seasonClock = 0
            seasonIndex = (seasonIndex + 1) % Season.allCases.count
        }

        let w = weather(c)
        let k = 1 - exp(-dt * 0.35)

        // Rain.
        let raining: Bool
        switch c.rainMode {
        case .auto: raining = w == .rain || w == .storm
        case .always: raining = true
        case .never: raining = false
        }
        rain += ((raining ? (w == .storm ? 1.6 : 1) : 0) - rain) * k
        rainTime += dt
        let shower = c.rainVary ? 0.6 + 0.4 * sin(rainTime * 0.13) * sin(rainTime * 0.047 + 1.3) : 1
        let dim = c.rainDim ? min(1.4, rain) * min(1.3, 0.6 + 0.4 * c.rainIntensity) : 0

        // Clouds: dims and cools the light.
        let cloudTarget: CGFloat = w == .cloudy ? 0.6 : (w == .storm ? 1 : (w == .rain ? 0.7 : 0))
        clouds += (cloudTarget - clouds) * k

        // Time of day.
        let light = DayLight(hour: hour(c, dt: dt))
        tint += (light.tint - tint) * Float(k * 2)
        night += (light.night - night) * k * 2

        // Wind: a base strength from the setting, stronger when windy or stormy, with gusts.
        let weatherWind: CGFloat = w == .windy ? 3.5 : (w == .storm ? 2.8 : (w == .rain ? 1.4 : 1))
        windLevel += (c.windAmount * weatherWind - windLevel) * k
        let gust = w == .windy || w == .storm
            ? 1 + 0.7 * max(0, sin(time * 0.37) * sin(time * 0.91 + 1.7)) : 1
        windStrength = windLevel * gust
        windAngle += .random(in: -1...1) * (w == .windy ? 0.25 : 0.6) * dt
        wind = CGVector(dx: cos(windAngle) * 14 * u * windStrength, dy: sin(windAngle) * 10 * u * windStrength)

        // Overall light: time-of-day tint, darkened by clouds and rain.
        let dull = Float(1 - clouds * 0.18 - dim * 0.1)
        let grey = SIMD3<Float>(0.92, 0.95, 1.0)
        let t = tint * (grey + (SIMD3<Float>(1, 1, 1) - grey) * (1 - Float(clouds))) * dull
        overlay.size = bounds.size
        overlay.color = SKColor(red: CGFloat(t.x), green: CGFloat(t.y), blue: CGFloat(t.z), alpha: 1)
        overlay.isHidden = t.x > 0.995 && t.y > 0.995 && t.z > 0.995
        Shaders.applyAtmosphere(rain: max(dim, clouds * 0.5), night: night)

        // Lightning in storms: a double flicker every so often.
        flash.size = bounds.size
        if w == .storm && c.lightning {
            nextLightning -= dt
            if nextLightning <= 0 {
                nextLightning = .random(in: 6...18)
                let peak = CGFloat.random(in: 0.25...0.5)
                flash.removeAllActions()
                flash.run(.sequence([
                    .fadeAlpha(to: peak, duration: 0.04), .fadeAlpha(to: 0.05, duration: 0.08),
                    .fadeAlpha(to: peak * 0.8, duration: 0.05), .fadeOut(withDuration: 0.5),
                ]))
            }
        }

        let areaM = bounds.width * bounds.height / 1_000_000
        func randomPoint(_ inset: CGFloat = 0) -> CGPoint {
            CGPoint(x: .random(in: pond.minX - inset...pond.maxX + inset),
                    y: .random(in: pond.minY - inset...pond.maxY + inset))
        }

        // Raindrops.
        if rain > 0.02 {
            // Wave ripples are bigger and there are only so many slots, so fewer, heavier drops.
            let perM: CGFloat = Ripple.realistic ? 3.5 : 14
            rainDue += rain * shower * c.rainIntensity * perM * areaM * dt
            while rainDue >= 1 {
                rainDue -= 1
                Ripple.drop(at: randomPoint(), in: surface, size: .random(in: 50...110) * u * c.rainDropSize)
            }
        }

        // Falling petals, leaves or snow; wind shakes more loose.
        if c.fallingOn {
            let style = SeasonStyle.of(season(c))
            fallDue += style.rate * CGFloat(c.fallingAmount) * areaM * dt * min(3, 0.7 + 0.3 * windStrength)
            while fallDue >= 1 {
                fallDue -= 1
                guard floaters.count < 220 else { fallDue = 0; break }
                let f = Floater(kind: style.kind, color: style.colors.randomElement()!, at: randomPoint(60 * u), unit: u)
                surface.addChild(f.node)
                shadows.addChild(f.shadow)
                floaters.append(f)
            }
        }
        let keep = bounds.insetBy(dx: -200 * u, dy: -200 * u)
        floaters.removeAll { f in
            if f.update(dt: dt, wind: wind), f.kind != .snow {
                Ripple.spawn(at: f.node.position, in: surface, size: 34 * u, rings: 1, strength: 0.25, realistic: false)
            }
            guard f.isDead || !keep.contains(f.node.position) else { return false }
            f.node.removeFromParent()
            f.shadow.removeFromParent()
            return true
        }

        // Fireflies, only while it's (becoming) night and not raining hard.
        let flyLevel = night * (1 - min(1, rain))
        let wantFlies = c.fireflies && flyLevel > 0.01
        if wantFlies && fireflies.isEmpty {
            fireflies = (0..<max(8, Int(4 * areaM))).map { _ in Firefly(in: bounds, unit: u) }
            fireflies.forEach { fireflyLayer.addChild($0.node) }
        }
        if !c.fireflies && !fireflies.isEmpty {
            fireflyLayer.removeAllChildren()
            fireflies = []
        }
        fireflyLayer.isHidden = !wantFlies
        if wantFlies {
            fireflies.forEach { $0.update(dt: dt, night: flyLevel, bounds: bounds) }
        }
    }
}
