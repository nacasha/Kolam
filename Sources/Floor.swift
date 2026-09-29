// Floor — the pond bottom, and the pond depth that everything's shadows follow.
//
// The floor is baked once per scene size into a small data texture:
//   R = mottled floor brightness (value noise + vignette), after the original page
//   G = dark pebble coverage, B = light pebble coverage
// The water shader colours it with the current preset, so changing the water
// colour never re-bakes it.

import SpriteKit

/// Pond depth, shared by everything that casts a shadow onto the floor.
enum Depth {
    /// 0 = shallow, 1 = deep. Drives shadows.
    static var value: CGFloat = 0.7
    /// Depth used for colour: the floor darkness when darkening is on, otherwise a
    /// fixed shallow look. Independent of `value`, which only moves shadows.
    static var visual: CGFloat = 0.7

    static func set(_ depth: CGFloat, darken: Bool, darkness: CGFloat) {
        value = depth
        visual = darken ? darkness : 0.15
    }

    /// Shadow settings (1 = default).
    static var shadowStrength: CGFloat = 1
    static var shadowDistance: CGFloat = 1
    /// Direction the light comes from, in radians (default: upper left).
    static var lightAngle: CGFloat = 125 * .pi / 180
    /// Softness multiplier for shadow edges.
    static var shadowBlur: CGFloat = 1

    /// Shadows land further from their object in deeper water.
    static var shadowScale: CGFloat { (0.35 + 1.5 * value) * shadowDistance }
    /// ...and are softer and fainter.
    static var shadowAlpha: CGFloat { (1 - 0.55 * value) * shadowStrength }

    /// Turns a base shadow offset (drawn for light from the upper left) into the
    /// offset for the current depth, distance and light direction.
    static func offset(_ v: CGVector) -> CGVector {
        let rotation = lightAngle - 125 * .pi / 180
        let c = cos(rotation) * shadowScale, s = sin(rotation) * shadowScale
        return CGVector(dx: v.dx * c - v.dy * s, dy: v.dx * s + v.dy * c)
    }
    static var shadowSpread: CGFloat { (1 + 0.25 * value) * (0.8 + 0.2 * shadowBlur) }
    /// How far the deepest koi fade into the water colour.
    static var koiFade: CGFloat { 0.12 + 0.5 * visual }
}

enum FloorStyle: String, CaseIterable {
    /// The original page's floor: mottled noise with scattered pebbles.
    case original
    /// Fine grain with rippled sand bars and a few small pebbles.
    case sand
    /// Rounded cobbles with dark gaps between them.
    case stones
    /// Dense small gravel.
    case gravel
    /// Soft patches of moss over a dark bed.
    case moss
    /// Large flat slate plates with thin seams.
    case slate
    /// Dry clay broken into cracked plates.
    case clay
    /// No floor detail, just water colour.
    case plain
}

enum Floor {
    /// Floor detail is soft under water, so half resolution is plenty.
    /// R = floor brightness, G = dark detail (pebbles, gaps), B = light detail.
    /// `lowRes` bakes at a quarter of the points, for low memory mode.
    static func bake(size: CGSize, style: FloorStyle, lowRes: Bool = false) -> SKTexture {
        let q: CGFloat = lowRes ? 0.25 : 0.5   // texture pixels per point
        let w = max(16, Int(size.width * q)), h = max(16, Int(size.height * q))
        let area = size.width * size.height

        let pebbleData: UnsafeMutablePointer<UInt8>?
        let pebbles: CGContext?
        switch style {
        case .original: pebbles = drawPebbles(w: w, h: h, count: Int(area / 14_400), radius: 6...24, q: q)
        case .sand: pebbles = drawPebbles(w: w, h: h, count: Int(area / 60_000), radius: 3...9, q: q)
        case .gravel: pebbles = drawPebbles(w: w, h: h, count: Int(area / 2_600), radius: 2...6, q: q)
        case .stones, .moss, .slate, .clay, .plain: pebbles = nil
        }
        pebbleData = pebbles?.data?.assumingMemoryBound(to: UInt8.self)

        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        let seed = Float.random(in: 0...1000)
        for py in 0..<h {
            for px in 0..<w {
                let x = Float(px) / Float(q), y = Float(py) / Float(q)
                let dx = (Float(px) / Float(w) - 0.5) * 1.4, dy = (Float(py) / Float(h) - 0.5) * 1.4
                let vignette = 1 - min(1, (dx * dx + dy * dy).squareRoot()) * 0.3
                var n: Float = 0.5, dark: Float = 0, light: Float = 0

                switch style {
                case .original:
                    // Original: three octaves of value noise (x/40, x/12, x/4 at 4 pt per unit).
                    n = noise(x / 160 + seed, y / 160) * 0.6 + noise(x / 48, y / 48 + seed) * 0.3 + noise(x / 16 + seed, y / 16) * 0.1
                    n = n * vignette + (hash(Float(px), Float(py)) - 0.5) * 0.03
                case .sand:
                    // Wavy sand bars bent by low-frequency noise, over fine grain.
                    let bend = noise(x / 240 + seed, y / 240) * 7
                    let bars = sin((x * 0.9 + y * 0.45) / 13 + bend)
                    n = 0.55 + (noise(x / 200, y / 200 + seed) - 0.5) * 0.35 + bars * 0.2
                    n = n * vignette + (hash(Float(px), Float(py)) - 0.5) * 0.09
                    light = max(0, bars - 0.55) * 0.9
                    dark = max(0, -bars - 0.6) * 0.5
                case .stones:
                    let c = cobble(x / 70 + seed, y / 70)
                    // Each stone its own shade, domed toward its centre, with noise on top.
                    let dome = 1 - pow(c.f1, 1.6)
                    n = (0.25 + c.shade * 0.6) * (0.55 + 0.45 * dome) + (noise(x / 20, y / 20 + seed) - 0.5) * 0.12
                    n *= vignette
                    dark = 1 - smoothstep(0.0, 0.16, c.edge)
                    light = max(0, 1 - hypot(c.fromCenter.x + 0.18, c.fromCenter.y - 0.18) * 3) * 0.35
                case .gravel:
                    n = 0.45 + (noise(x / 120 + seed, y / 120) - 0.5) * 0.3
                    n = n * vignette + (hash(Float(px), Float(py)) - 0.5) * 0.16
                case .moss:
                    let m = noise(x / 160 + seed, y / 160) * 0.7 + noise(x / 60, y / 60 + seed) * 0.3
                    n = (0.3 + (noise(x / 60, y / 60) - 0.5) * 0.2) * vignette
                    light = smoothstep(0.42, 0.68, m) * (0.6 + noise(x / 28, y / 28 + seed) * 0.4)
                    dark = (1 - smoothstep(0.3, 0.45, m)) * 0.35
                case .slate:
                    let c = cobble(x / 190 + seed, y / 150)
                    n = (0.3 + c.shade * 0.45) + (noise(x / 50, y / 50 + seed) - 0.5) * 0.1
                    n = n * vignette + (hash(Float(px), Float(py)) - 0.5) * 0.04
                    dark = 1 - smoothstep(0.0, 0.04, c.edge)
                case .clay:
                    let c = cobble(x / 55 + seed, y / 55)
                    n = 0.62 + (noise(x / 90 + seed, y / 90) - 0.5) * 0.3 + (c.shade - 0.5) * 0.12
                    n = n * vignette + (hash(Float(px), Float(py)) - 0.5) * 0.05
                    dark = 1 - smoothstep(0.0, 0.035, c.edge)
                    light = smoothstep(0.035, 0.07, c.edge) * (1 - smoothstep(0.07, 0.12, c.edge)) * 0.35
                case .plain:
                    n = 0.5
                }

                let i = (py * w + px) * 4
                pixels[i] = UInt8(max(0, min(1, n)) * 255)
                if let pebbleData {
                    // CGContext rows run top-down in memory; match the texture's orientation.
                    let j = ((h - 1 - py) * w + px) * 4
                    pixels[i + 1] = max(pebbleData[j + 1], UInt8(max(0, min(1, dark)) * 255))
                    pixels[i + 2] = max(pebbleData[j + 2], UInt8(max(0, min(1, light)) * 255))
                } else {
                    pixels[i + 1] = UInt8(max(0, min(1, dark)) * 255 * 0.85)
                    pixels[i + 2] = UInt8(max(0, min(1, light)) * 255)
                }
            }
        }

        let texture = SKTexture(data: Data(pixels), size: CGSize(width: w, height: h), flipped: false)
        texture.filteringMode = .linear
        return texture
    }

    /// Pebbles: G = dark, B = light, drawn with opaque colour so overlaps simply replace.
    private static func drawPebbles(w: Int, h: Int, count: Int, radius: ClosedRange<CGFloat>, q: CGFloat) -> CGContext {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for _ in 0..<count {
            let r = CGFloat.random(in: radius) * q
            let a = CGFloat.random(in: 0.08...0.2) * 2.2
            let dark = Bool.random()
            ctx.saveGState()
            ctx.translateBy(x: .random(in: 0...CGFloat(w)), y: .random(in: 0...CGFloat(h)))
            ctx.rotate(by: .random(in: 0..<(2 * .pi)))
            ctx.setFillColor(CGColor(red: 0, green: dark ? a : 0, blue: dark ? 0 : a, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: -r, y: -r * 0.75, width: r * 2, height: r * 2 * .random(in: 0.6...0.9)))
            ctx.restoreGState()
        }
        return ctx
    }

    /// Voronoi cobbles in cell units: distance to the nearest stone centre (f1), the gap
    /// width to the next stone (edge), that stone's shade, and the offset from its centre.
    private static func cobble(_ x: Float, _ y: Float) -> (f1: Float, edge: Float, shade: Float, fromCenter: SIMD2<Float>) {
        let cx = x.rounded(.down), cy = y.rounded(.down)
        var d1: Float = 9, d2: Float = 9, shade: Float = 0
        var offset = SIMD2<Float>(0, 0)
        for j in -1...1 {
            for i in -1...1 {
                let gx = cx + Float(i), gy = cy + Float(j)
                let px = gx + 0.15 + hash(gx, gy) * 0.7, py = gy + 0.15 + hash(gx * 3.1, gy * 1.7) * 0.7
                let d = hypot(x - px, y - py)
                if d < d1 {
                    d2 = d1
                    d1 = d
                    shade = hash(gx * 7.3, gy * 5.9)
                    offset = SIMD2(x - px, y - py)
                } else if d < d2 {
                    d2 = d
                }
            }
        }
        return (min(1, d1 / 0.7), d2 - d1, shade, offset)
    }

    private static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private static func hash(_ x: Float, _ y: Float) -> Float {
        let h = sin(x * 127.1 + y * 311.7) * 43758.5453
        return h - h.rounded(.down)
    }

    private static func noise(_ x: Float, _ y: Float) -> Float {
        let ix = x.rounded(.down), iy = y.rounded(.down)
        var fx = x - ix, fy = y - iy
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        let a = hash(ix, iy), b = hash(ix + 1, iy), c = hash(ix, iy + 1), d = hash(ix + 1, iy + 1)
        return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy
    }
}

extension Floor {
    /// A small coloured picture of a floor style in a water colour, for the settings window.
    /// Mirrors the water shader's floor colouring (without the moving light).
    static func preview(style: FloorStyle, water: WaterPreset, size: CGSize = CGSize(width: 150, height: 96)) -> CGImage? {
        // Bake at 2× so the preview shows the same scale of detail as the pond at 50%.
        guard let data = bake(size: CGSize(width: size.width * 2, height: size.height * 2), style: style).cgImage().dataProvider?.data,
              let src = CFDataGetBytePtr(data) else { return nil }
        let w = Int(size.width), h = Int(size.height)
        var out = [UInt8](repeating: 255, count: w * h * 4)
        let lo = water.lo / 255, hi = water.hi / 255, dark = water.spotDark / 255, light = water.spotLight / 255
        let plain = style == .plain
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let n = plain ? 0.5 : Float(src[i]) / 255
                var c = lo + (hi - lo) * n
                if !plain {
                    c += (dark - c) * (Float(src[i + 1]) / 255)
                    c += (light - c) * (Float(src[i + 2]) / 255)
                }
                c *= 0.85
                out[i] = UInt8(max(0, min(1, c.x)) * 255)
                out[i + 1] = UInt8(max(0, min(1, c.y)) * 255)
                out[i + 2] = UInt8(max(0, min(1, c.z)) * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
