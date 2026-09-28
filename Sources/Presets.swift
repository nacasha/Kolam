// Presets — whole looks saved as a set of settings. Built-in presets list only
// what they change; everything else resets to the default.

import Foundation

struct Preset {
    let name: String
    let values: [String: Any]
}

enum Presets {
    private static let d = UserDefaults.standard
    private static let userKey = "userPresets"
    /// App behaviour, not part of the pond's look.
    private static let excluded: Set<String> = ["fps", "interactive", "showStats", "paused", "floorLowRes"]

    static var sceneKeys: [String] { Settings.defaults.keys.filter { !excluded.contains($0) }.sorted() }

    static let builtIn: [Preset] = [
        Preset(name: "Default", values: [:]),
        Preset(name: "Golden sunset", values: [
            "weather": "clear", "timeOfDay": "sunset", "season": "summer", "water": "jade", "rainMode": "never",
            "depthDarken": false,
        ]),
        Preset(name: "Thunderstorm", values: [
            "weather": "storm", "timeOfDay": "dusk", "water": "deep", "rainIntensity": 180.0, "dragonflies": 0.0,
        ]),
        Preset(name: "Sunny spring", values: [
            "weather": "clear", "timeOfDay": "morning", "season": "spring", "water": "jade", "depth": 40.0, "depthDarken": false,
            "floorStyle": "original", "rainMode": "never",
        ]),
        Preset(name: "Rainy night", values: [
            "weather": "rain", "timeOfDay": "night", "rainMode": "always", "rainIntensity": 150.0, "water": "deep",
            "depth": 80.0, "fireflies": true, "dragonflies": 0.0,
        ]),
        Preset(name: "Autumn pond", values: [
            "weather": "windy", "timeOfDay": "afternoon", "season": "autumn", "water": "moss", "floorStyle": "stones",
            "fallingAmount": 160.0, "rainMode": "never",
        ]),
        Preset(name: "Winter", values: [
            "weather": "cloudy", "timeOfDay": "day", "season": "winter", "water": "ink", "floorStyle": "slate", "padClusters": 2.0,
            "dragonflies": 0.0, "frog": false, "turtle": false, "fireflies": false, "reedAmount": 60.0,
        ]),
        Preset(name: "Zen minimal", values: [
            "weather": "clear", "rainMode": "never", "water": "deep", "floorStyle": "sand", "koiCount": 5.0,
            "padClusters": 2.0, "minnowsOn": false, "dragonflies": 0.0, "frog": false, "turtle": false,
            "vinesOn": false, "reedsOn": false, "fallingOn": false, "wobbleOn": false,
        ]),
        Preset(name: "Wild pond", values: [
            "floorStyle": "moss", "koiCount": 14.0, "padClusters": 9.0,
            "minnowSchools": 6.0, "dragonflies": 4.0, "reedAmount": 180.0, "vinesOn": true,
        ]),
    ]

    static var userNames: [String] {
        (d.dictionary(forKey: userKey) ?? [:]).keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Resets every pond setting to its default, then applies the preset's values.
    static func apply(_ values: [String: Any]) {
        for key in sceneKeys {
            if let v = values[key] { d.set(v, forKey: key) } else { d.removeObject(forKey: key) }
        }
    }

    static func applyUser(_ name: String) {
        guard let values = (d.dictionary(forKey: userKey) ?? [:])[name] as? [String: Any] else { return }
        apply(values)
    }

    static func saveCurrent(as name: String) {
        var all = d.dictionary(forKey: userKey) ?? [:]
        var values: [String: Any] = [:]
        for key in sceneKeys {
            if let v = d.object(forKey: key) { values[key] = v }
        }
        all[name] = values
        d.set(all, forKey: userKey)
    }

    static func delete(_ name: String) {
        var all = d.dictionary(forKey: userKey) ?? [:]
        all[name] = nil
        d.set(all, forKey: userKey)
    }
}
