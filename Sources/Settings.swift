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
            "timeOfDay": "clock",
            "cycleMinutes": 20.0,
            "windAmount": 100.0,
            "lightning": true,
            "windAuto": true,
            "windRipplesOn": true,
            "windRipples": 100.0,
            "plantsLean": true,
            "causticsFlow": true,
            "treesOn": true,
            "treeSize": 100.0,
            "koiMoods": true,
            "koiChase": true,
            "windDirection": 0.0,
            "season": "auto",
            "fallingOn": true,
            "fallingAmount": 100.0,
            "iceOn": true,
            "iceAmount": 100.0,
            "debrisOn": true,
            "debrisAmount": 100.0,
            "fireflies": true,
            "fireflyAmount": 100.0,
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
            "floorDarkness": 70.0,
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
            "reedsOn": true,
            "reedAmount": 100.0,
            "cattails": true,
            "floorLowRes": false,
            "surfaceScale": 75.0,
            "surfacingOn": true,
            "surfacingRate": 100.0,
            "artStyle": "natural",
            "pixelSize": 4.0,
            "ditherPalette": "gameboy",
            "halftoneSize": 8.0,
            "mosaicSize": 22.0,
            "tiltOn": false,
            "tiltStrength": 100.0,
            "tiltFocus": 50.0,
            "tiltBand": 15.0,
    ]

    static func registerDefaults() {
        d.register(defaults: defaults)
        d.removeObject(forKey: "pondShape")   // shaped ponds were removed
        // "Low memory mode" was split into individual switches; carry its effect over.
        if d.object(forKey: "lowMemory") != nil {
            if d.bool(forKey: "lowMemory") {
                d.set(true, forKey: "floorLowRes")
                for key in ["wobbleOn", "splashOn", "windRipplesOn"] { d.set(false, forKey: key) }
            }
            d.removeObject(forKey: "lowMemory")
        }
        // Weather used to include "night"; it's a time of day now.
        if d.string(forKey: "weather") == "night" {
            d.set("clear", forKey: "weather")
            d.set("night", forKey: "timeOfDay")
        }
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

    /// Displays the pond is turned off on, by display UUID. Stored as the off list so a
    /// display that's never been seen before gets a pond.
    static var disabledDisplays: Set<String> {
        get { Set(d.stringArray(forKey: "disabledDisplays") ?? []) }
        set { d.set(newValue.sorted(), forKey: "disabledDisplays") }
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
    var timeMode: TimeMode
    var cycleMinutes: CGFloat
    var windAmount: CGFloat
    var lightning: Bool
    /// Direction the wind blows toward, in radians; nil = wanders on its own.
    var windDirection: CGFloat?
    var windRipplesOn: Bool
    var windRipples: CGFloat
    var plantsLean: Bool
    var causticsFlow: Bool
    var treesOn: Bool
    var treeSize: CGFloat
    var koiMoods: Bool
    var koiChase: Bool
    var season: Season?
    var fallingOn: Bool
    var fallingAmount: Double
    var iceOn: Bool
    var iceAmount: CGFloat
    var debrisOn: Bool
    var debrisAmount: CGFloat
    var fireflies: Bool
    var fireflyAmount: CGFloat
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
    var floorDarkness: CGFloat
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
    var reedsOn: Bool
    var reedAmount: CGFloat
    var cattails: Bool
    var floorLowRes: Bool
    var surfaceScale: CGFloat
    var surfacingOn: Bool
    var surfacingRate: CGFloat
    var artStyle: ArtStyle
    var pixelSize: CGFloat
    var ditherPalette: DitherPalette
    var halftoneSize: CGFloat
    var mosaicSize: CGFloat
    var tiltOn: Bool
    var tiltStrength: CGFloat
    var tiltFocus: CGFloat
    var tiltBand: CGFloat

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
            timeMode: TimeMode(d.string(forKey: "timeOfDay")),
            cycleMinutes: CGFloat(d.double(forKey: "cycleMinutes")),
            windAmount: CGFloat(d.double(forKey: "windAmount") / 100),
            lightning: d.bool(forKey: "lightning"),
            windDirection: d.bool(forKey: "windAuto") ? nil : CGFloat(d.double(forKey: "windDirection")) * .pi / 180,
            windRipplesOn: d.bool(forKey: "windRipplesOn"),
            windRipples: CGFloat(d.double(forKey: "windRipples") / 100),
            plantsLean: d.bool(forKey: "plantsLean"),
            causticsFlow: d.bool(forKey: "causticsFlow"),
            treesOn: d.bool(forKey: "treesOn"),
            treeSize: CGFloat(d.double(forKey: "treeSize") / 100),
            koiMoods: d.bool(forKey: "koiMoods"),
            koiChase: d.bool(forKey: "koiChase"),
            season: Season(rawValue: d.string(forKey: "season") ?? ""),
            fallingOn: d.bool(forKey: "fallingOn"),
            fallingAmount: d.double(forKey: "fallingAmount") / 100,
            iceOn: d.bool(forKey: "iceOn"),
            iceAmount: CGFloat(d.double(forKey: "iceAmount") / 100),
            debrisOn: d.bool(forKey: "debrisOn"),
            debrisAmount: CGFloat(d.double(forKey: "debrisAmount") / 100),
            fireflies: d.bool(forKey: "fireflies"),
            fireflyAmount: CGFloat(d.double(forKey: "fireflyAmount") / 100),
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
            floorDarkness: CGFloat(d.double(forKey: "floorDarkness") / 100),
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
            reedsOn: d.bool(forKey: "reedsOn"),
            reedAmount: CGFloat(d.double(forKey: "reedAmount") / 100),
            cattails: d.bool(forKey: "cattails"),
            floorLowRes: d.bool(forKey: "floorLowRes"),
            surfaceScale: CGFloat(d.double(forKey: "surfaceScale") / 100),
            surfacingOn: d.bool(forKey: "surfacingOn"),
            surfacingRate: CGFloat(d.double(forKey: "surfacingRate") / 100),
            artStyle: ArtStyle(rawValue: d.string(forKey: "artStyle") ?? "") ?? .natural,
            pixelSize: CGFloat(d.double(forKey: "pixelSize")),
            ditherPalette: DitherPalette(rawValue: d.string(forKey: "ditherPalette") ?? "") ?? .gameboy,
            halftoneSize: CGFloat(d.double(forKey: "halftoneSize")),
            mosaicSize: CGFloat(d.double(forKey: "mosaicSize")),
            tiltOn: d.bool(forKey: "tiltOn"),
            tiltStrength: CGFloat(d.double(forKey: "tiltStrength") / 100),
            tiltFocus: CGFloat(d.double(forKey: "tiltFocus") / 100),
            tiltBand: CGFloat(d.double(forKey: "tiltBand") / 100))
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
        WaterPreset(name: "turquoise", lo: [24, 140, 150], hi: [100, 212, 210], spotDark: [8, 70, 80], spotLight: [170, 240, 235]),
        WaterPreset(name: "emerald", lo: [14, 100, 64], hi: [64, 178, 118], spotDark: [4, 50, 30], spotLight: [140, 220, 170]),
        WaterPreset(name: "glacier", lo: [70, 120, 140], hi: [160, 204, 214], spotDark: [40, 80, 100], spotLight: [215, 238, 244]),
        WaterPreset(name: "tea", lo: [80, 62, 28], hi: [158, 128, 66], spotDark: [40, 28, 10], spotLight: [200, 175, 120]),
        WaterPreset(name: "stone", lo: [60, 66, 64], hi: [128, 136, 130], spotDark: [30, 34, 32], spotLight: [180, 186, 180]),
        WaterPreset(name: "midnight", lo: [14, 20, 52], hi: [40, 56, 112], spotDark: [4, 6, 22], spotLight: [80, 96, 160]),
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

/// Time of day: follow the Mac's clock, loop through a whole day, or hold one time.
enum TimeMode: Equatable {
    case clock
    case cycle
    case fixed(TimeOfDay)

    init(_ raw: String?) {
        switch raw {
        case "cycle": self = .cycle
        case let r?: self = TimeOfDay(rawValue: r).map(TimeMode.fixed) ?? .clock
        default: self = .clock
        }
    }
}
