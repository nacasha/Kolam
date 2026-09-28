// Settings — everything lives in UserDefaults so the SwiftUI panel (@AppStorage)
// and the scene read the same values. Changes are picked up through
// UserDefaults.didChangeNotification and applied live.

import SpriteKit

enum Settings {
    private static let d = UserDefaults.standard

    /// Must match the @AppStorage defaults in SettingsView.
    static let defaults: [String: Any] = [
            "water": "deep",
            "wavesOn": true,
            "waveIntensity": 100.0,
            "koiCount": 8.0,
            "koiSpeed": 100.0,
            "koiSize": 100.0,
            "padsOn": true,
            "padClusters": 5.0,
            "flowers": true,
            "clickLure": true,
            "fps": 0,
            "weather": "auto",
            "season": "auto",
            "fallingOn": true,
            "fallingAmount": 100.0,
            "fireflies": true,
            "driftOn": true,
            "driftIntensity": 100.0,
            "skyOn": true,
            "vinesOn": true,
            "dragonflies": 2.0,
            "frog": true,
            "minnowsOn": true,
            "minnowSchools": 3.0,
            "minnowFollow": true,
            "depth": 70.0,
            "rainMode": "auto",
            "rainIntensity": 100.0,
            "rainDropSize": 100.0,
            "rainVary": true,
            "rainDim": true,
            "floorStyle": "original",
            "depthDarken": true,
            "shadowStrength": 100.0,
            "shadowBlur": 100.0,
            "shadowDistance": 100.0,
            "lightAngle": 125.0,
            "wobbleOn": true,
            "wobbleIntensity": 60.0,
            "wobbleSize": 100.0,
            "splashOn": true,
            "splashStrength": 100.0,
                "feedOn": true,
            "turtle": true,
            "pondShape": "full",
            "reedsOn": true,
            "reedAmount": 100.0,
            "cattails": true,
    ]

    static func registerDefaults() {
        d.register(defaults: defaults)
    }

    static var paused: Bool {
        get { d.bool(forKey: "paused") }
        set { d.set(newValue, forKey: "paused") }
    }

    /// Wallpaper takes clicks (window sits just above desktop icons, still below apps).
    static var interactive: Bool {
        get { d.bool(forKey: "interactive") }
        set { d.set(newValue, forKey: "interactive") }
    }

    static var showStats: Bool {
        get { d.bool(forKey: "showStats") }
        set { d.set(newValue, forKey: "showStats") }
    }

    /// 0 = the display's maximum refresh rate.
    static var fps: Int { d.integer(forKey: "fps") }
}

/// The settings the scene cares about, compared as a whole to see what changed.
struct PondConfig: Equatable {
    var water: WaterPreset
    var wavesOn: Bool
    var waveIntensity: Double
    var koiCount: Int
    var koiSpeed: Double
    var koiSize: Double
    var padsOn: Bool
    var padClusters: Int
    var flowers: Bool
    var clickLure: Bool
    /// nil = auto (cycles on its own).
    var weather: Weather?
    var season: Season?
    var fallingOn: Bool
    var fallingAmount: Double
    var fireflies: Bool
    var driftOn: Bool
    var driftIntensity: Double
    var skyOn: Bool
    var vinesOn: Bool
    var dragonflies: Int
    var frog: Bool
    var minnowsOn: Bool
    var minnowSchools: Int
    var minnowFollow: Bool
    var depth: CGFloat
    var rainMode: RainMode
    var rainIntensity: CGFloat
    var rainDropSize: CGFloat
    var rainVary: Bool
    var rainDim: Bool
    var floorStyle: FloorStyle
    var depthDarken: Bool
    var shadowStrength: CGFloat
    var shadowBlur: CGFloat
    var shadowDistance: CGFloat
    var lightAngle: CGFloat
    var wobbleOn: Bool
    var wobbleIntensity: CGFloat
    var wobbleSize: CGFloat
    var splashOn: Bool
    var splashStrength: CGFloat
    var feedOn: Bool
    var turtle: Bool
    var pondShape: PondShape
    var reedsOn: Bool
    var reedAmount: CGFloat
    var cattails: Bool

    static var current: PondConfig {
        let d = UserDefaults.standard
        return PondConfig(
            water: WaterPreset.named(d.string(forKey: "water")),
            wavesOn: d.bool(forKey: "wavesOn"),
            waveIntensity: d.double(forKey: "waveIntensity") / 100,
            koiCount: Int(d.double(forKey: "koiCount")),
            koiSpeed: d.double(forKey: "koiSpeed") / 100,
            koiSize: d.double(forKey: "koiSize") / 100,
            padsOn: d.bool(forKey: "padsOn"),
            padClusters: Int(d.double(forKey: "padClusters")),
            flowers: d.bool(forKey: "flowers"),
            clickLure: d.bool(forKey: "clickLure"),
            weather: Weather(rawValue: d.string(forKey: "weather") ?? ""),
            season: Season(rawValue: d.string(forKey: "season") ?? ""),
            fallingOn: d.bool(forKey: "fallingOn"),
            fallingAmount: d.double(forKey: "fallingAmount") / 100,
            fireflies: d.bool(forKey: "fireflies"),
            driftOn: d.bool(forKey: "driftOn"),
            driftIntensity: d.double(forKey: "driftIntensity") / 100,
            skyOn: d.bool(forKey: "skyOn"),
            vinesOn: d.bool(forKey: "vinesOn"),
            dragonflies: Int(d.double(forKey: "dragonflies")),
            frog: d.bool(forKey: "frog"),
            minnowsOn: d.bool(forKey: "minnowsOn"),
            minnowSchools: Int(d.double(forKey: "minnowSchools")),
            minnowFollow: d.bool(forKey: "minnowFollow"),
            depth: CGFloat(d.double(forKey: "depth") / 100),
            rainMode: RainMode(rawValue: d.string(forKey: "rainMode") ?? "") ?? .auto,
            rainIntensity: CGFloat(d.double(forKey: "rainIntensity") / 100),
            rainDropSize: CGFloat(d.double(forKey: "rainDropSize") / 100),
            rainVary: d.bool(forKey: "rainVary"),
            rainDim: d.bool(forKey: "rainDim"),
            floorStyle: FloorStyle(rawValue: d.string(forKey: "floorStyle") ?? "") ?? .original,
            depthDarken: d.bool(forKey: "depthDarken"),
            shadowStrength: CGFloat(d.double(forKey: "shadowStrength") / 100),
            shadowBlur: CGFloat(d.double(forKey: "shadowBlur") / 100),
            shadowDistance: CGFloat(d.double(forKey: "shadowDistance") / 100),
            lightAngle: CGFloat(d.double(forKey: "lightAngle")) * .pi / 180,
            wobbleOn: d.bool(forKey: "wobbleOn"),
            wobbleIntensity: CGFloat(d.double(forKey: "wobbleIntensity") / 100),
            wobbleSize: CGFloat(d.double(forKey: "wobbleSize") / 100),
            splashOn: d.bool(forKey: "splashOn"),
            splashStrength: CGFloat(d.double(forKey: "splashStrength") / 100),
            feedOn: d.bool(forKey: "feedOn"),
            turtle: d.bool(forKey: "turtle"),
            pondShape: PondShape(rawValue: d.string(forKey: "pondShape") ?? "") ?? .full,
            reedsOn: d.bool(forKey: "reedsOn"),
            reedAmount: CGFloat(d.double(forKey: "reedAmount") / 100),
            cattails: d.bool(forKey: "cattails"))
    }
}

/// Water colours, taken from the original page's presets: floor lo/hi and pebble colours (RGB).
struct WaterPreset: Equatable {
    let name: String
    let lo: SIMD3<Float>
    let hi: SIMD3<Float>
    let spotDark: SIMD3<Float>
    let spotLight: SIMD3<Float>

    static let all: [WaterPreset] = [
        WaterPreset(name: "jade", lo: [38, 140, 118], hi: [92, 200, 166], spotDark: [10, 60, 45], spotLight: [150, 230, 200]),
        WaterPreset(name: "deep", lo: [14, 62, 60], hi: [36, 124, 112], spotDark: [0, 10, 8], spotLight: [70, 110, 95]),
        WaterPreset(name: "lagoon", lo: [18, 100, 135], hi: [70, 176, 200], spotDark: [5, 40, 60], spotLight: [150, 220, 240]),
        WaterPreset(name: "moss", lo: [38, 64, 38], hi: [88, 118, 66], spotDark: [15, 25, 10], spotLight: [120, 140, 90]),
        WaterPreset(name: "ink", lo: [8, 18, 30], hi: [26, 46, 66], spotDark: [0, 5, 12], spotLight: [60, 80, 110]),
    ]

    /// Overall brightness of the pond at a given depth (0 shallow … 1 deep).
    static func brightness(_ depth: CGFloat) -> Float { Float(0.95 - 0.6 * depth) }

    static func named(_ name: String?) -> WaterPreset {
        all.first { $0.name == name } ?? all[1]
    }

    /// Colour of the caustic light: the bright end, pushed toward white.
    var light: SIMD3<Float> { hi / 255 * 0.6 + 0.2 }
    /// Mid-water colour at a given depth; deeper koi fade toward it.
    func mid(depth: CGFloat) -> SKColor {
        let c = (lo + hi) / 2 / 255 * Self.brightness(depth)
        return SKColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }
    /// Swatch for the settings panel.
    var swatch: SKColor {
        SKColor(red: CGFloat(hi.x / 255), green: CGFloat(hi.y / 255), blue: CGFloat(hi.z / 255), alpha: 1)
    }
}
