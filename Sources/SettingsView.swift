// SettingsView — the settings window: a searchable sidebar of categories, and one
// page per category. Every control writes straight to UserDefaults; the pond
// applies changes live.

import ServiceManagement
import SwiftUI

// MARK: - Pages

enum SettingsPage: String, CaseIterable, Identifiable {
    case presets, look, water, light
    case koi, wildlife, plants
    case time, weather, season
    case interaction, performance, general

    var id: String { rawValue }

    enum Group: String, CaseIterable { case scene = "Scene", life = "Life", environment = "Environment", app = "App" }

    var group: Group {
        switch self {
        case .presets, .look, .water, .light: return .scene
        case .koi, .wildlife, .plants: return .life
        case .time, .weather, .season: return .environment
        case .interaction, .performance, .general: return .app
        }
    }

    var title: String {
        switch self {
        case .presets: return "Presets"
        case .look: return "Look"
        case .water: return "Water"
        case .light: return "Light & Shadow"
        case .koi: return "Koi"
        case .wildlife: return "Wildlife"
        case .plants: return "Plants"
        case .time: return "Time of Day"
        case .weather: return "Weather"
        case .season: return "Season"
        case .interaction: return "Interaction"
        case .performance: return "Performance"
        case .general: return "General"
        }
    }

    var subtitle: String {
        switch self {
        case .presets: return "Switch the whole pond's look in one click, or save your own."
        case .look: return "Art style and camera focus for the whole scene."
        case .water: return "Colour, floor, depth and how the surface moves."
        case .light: return "Where the light comes from and how shadows fall."
        case .koi: return "How many koi, how they look and behave."
        case .wildlife: return "Small fish, dragonflies, the frog and the turtle."
        case .plants: return "Lily pads, reeds and vines."
        case .time: return "Lighting through the day, from dawn to night."
        case .weather: return "Clouds, rain, storms and wind."
        case .season: return "What falls from above: petals, leaves or snow."
        case .interaction: return "What happens when you click the pond."
        case .performance: return "Frame rate and memory use."
        case .general: return "Startup and diagnostics."
        }
    }

    var symbol: String {
        switch self {
        case .presets: return "sparkles"
        case .look: return "paintpalette.fill"
        case .water: return "drop.fill"
        case .light: return "sun.max.fill"
        case .koi: return "fish.fill"
        case .wildlife: return "ladybug.fill"
        case .plants: return "leaf.fill"
        case .time: return "clock.fill"
        case .weather: return "cloud.sun.rain.fill"
        case .season: return "leaf.arrow.triangle.circlepath"
        case .interaction: return "hand.tap.fill"
        case .performance: return "gauge.with.dots.needle.bottom.50percent"
        case .general: return "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .presets: return .purple
        case .look: return .pink
        case .water: return .blue
        case .light: return .orange
        case .koi: return Color(red: 0.93, green: 0.42, blue: 0.2)
        case .wildlife: return .green
        case .plants: return Color(red: 0.3, green: 0.62, blue: 0.3)
        case .time: return .indigo
        case .weather: return .teal
        case .season: return .brown
        case .interaction: return .cyan
        case .performance: return .red
        case .general: return .gray
        }
    }

    /// Settings a page's Reset button restores.
    var keys: [String] {
        switch self {
        case .presets: return []
        case .look: return ["artStyle", "pixelSize", "tiltOn", "tiltStrength", "tiltFocus", "tiltBand"]
        case .water: return ["water", "floorStyle", "depth", "depthDarken", "wavesOn", "waveIntensity",
                             "driftOn", "driftIntensity", "skyOn", "wobbleOn", "wobbleIntensity", "wobbleSize"]
        case .light: return ["lightAngle", "shadowStrength", "shadowBlur", "shadowDistance"]
        case .koi: return ["koiCount", "koiSpeed", "koiSize", "surfacingOn", "surfacingRate"]
        case .wildlife: return ["minnowsOn", "minnowSchools", "minnowFollow", "dragonflies", "frog", "turtle"]
        case .plants: return ["padsOn", "padClusters", "flowers", "reedsOn", "reedAmount", "cattails", "vinesOn"]
        case .time: return ["timeOfDay", "cycleMinutes", "fireflies"]
        case .weather: return ["weather", "windAmount", "windAuto", "windDirection", "windRipplesOn", "windRipples", "lightning", "rainMode", "rainIntensity", "rainDropSize", "rainVary", "rainDim"]
        case .season: return ["season", "fallingOn", "fallingAmount"]
        case .interaction: return ["feedOn", "clickLure", "splashOn", "splashStrength"]
        case .performance: return ["fps", "lowMemory"]
        case .general: return ["showStats"]
        }
    }

    /// Extra words the sidebar search matches.
    var keywords: String {
        switch self {
        case .presets: return "save theme"
        case .look: return "art painterly ink pixel tilt shift blur focus style"
        case .water: return "colour color turquoise emerald glacier tea stone midnight floor stones sand gravel moss slate clay depth distortion wobble caustic light patterns reflection"
        case .light: return "shadow blur distance strength direction angle sun"
        case .koi: return "fish count speed size surface gulp"
        case .wildlife: return "minnows small fish dragonfly frog turtle"
        case .plants: return "lily pads flowers reeds cattails vines"
        case .time: return "day night dawn sunset dusk morning afternoon clock cycle fireflies"
        case .weather: return "rain storm thunder lightning wind windy cloudy clouds"
        case .season: return "spring summer autumn winter snow petals leaves falling"
        case .interaction: return "click food feed ripple splash interactive"
        case .performance: return "fps frame rate memory low"
        case .general: return "login startup stats"
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return "\(title) \(subtitle) \(keywords)".lowercased().contains(q)
    }
}

// MARK: - Window content

struct SettingsView: View {
    @AppStorage("settingsPage") private var pageRaw = SettingsPage.presets.rawValue
    @State private var search = ""

    private var page: Binding<SettingsPage?> {
        Binding(get: { SettingsPage(rawValue: pageRaw) ?? .presets }, set: { pageRaw = ($0 ?? .presets).rawValue })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: page) {
                ForEach(SettingsPage.Group.allCases, id: \.self) { group in
                    let pages = SettingsPage.allCases.filter { $0.group == group && $0.matches(search) }
                    if !pages.isEmpty {
                        Section(group.rawValue) {
                            ForEach(pages) { p in
                                Label { Text(p.title) } icon: { IconBadge(symbol: p.symbol, color: p.color, size: 20) }
                                    .tag(p)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search settings")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            let current = page.wrappedValue ?? .presets
            PageView(page: current)
                .id(current)
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

/// Page header plus the page's settings.
struct PageView: View {
    let page: SettingsPage

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    IconBadge(symbol: page.symbol, color: page.color, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(page.title).font(.title2.weight(.semibold))
                        Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !page.keys.isEmpty {
                        Button {
                            page.keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .help("Restore this page's settings to their defaults")
                    }
                }
                .padding(.vertical, 4)
            }
            content
        }
        .formStyle(.grouped)
        .navigationTitle(page.title)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .presets: PresetsPage()
        case .look: LookPage()
        case .water: WaterPage()
        case .light: LightPage()
        case .koi: KoiPage()
        case .wildlife: WildlifePage()
        case .plants: PlantsPage()
        case .time: TimePage()
        case .weather: WeatherPage()
        case .season: SeasonPage()
        case .interaction: InteractionPage()
        case .performance: PerformancePage()
        case .general: GeneralPage()
        }
    }
}

/// Default value of a numeric setting, for slider reset hints.
private func def(_ key: String) -> Double? { Settings.defaults[key] as? Double }

// MARK: - Scene

struct PresetsPage: View {
    @State private var userPresets = Presets.userNames
    @State private var name = ""
    @State private var applied: String?

    private func symbol(_ name: String) -> (String, Color) {
        switch name {
        case "Default": return ("circle.dashed", .gray)
        case "Golden sunset": return ("sunset.fill", .orange)
        case "Thunderstorm": return ("cloud.bolt.rain.fill", .indigo)
        case "Sunny spring": return ("sun.max.fill", .yellow)
        case "Rainy night": return ("cloud.moon.rain.fill", .blue)
        case "Autumn pond": return ("leaf.fill", .brown)
        case "Winter": return ("snowflake", .cyan)
        case "Zen minimal": return ("circle.circle", .teal)
        case "Wild pond": return ("tortoise.fill", .green)
        default: return ("star.fill", .purple)
        }
    }

    var body: some View {
        Section("Built-in") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(Presets.builtIn, id: \.name) { preset in
                    let (sym, color) = symbol(preset.name)
                    Button {
                        Presets.apply(preset.values)
                        applied = preset.name
                    } label: {
                        HStack(spacing: 10) {
                            IconBadge(symbol: sym, color: color, size: 30)
                            Text(preset.name).lineLimit(1)
                            Spacer(minLength: 0)
                            if applied == preset.name {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        Section {
            if userPresets.isEmpty {
                Text("Nothing saved yet. Set up the pond the way you like it, then save it here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(userPresets, id: \.self) { preset in
                HStack {
                    RowLabel(title: preset, symbol: "star.fill")
                    Spacer()
                    Button("Apply") { Presets.applyUser(preset); applied = preset }
                    Button(role: .destructive) {
                        Presets.delete(preset)
                        userPresets = Presets.userNames
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Delete \(preset)")
                }
            }
            HStack {
                TextField("Name", text: $name, prompt: Text("My pond"))
                    .textFieldStyle(.roundedBorder)
                Button {
                    Presets.saveCurrent(as: name.trimmingCharacters(in: .whitespaces))
                    name = ""
                    userPresets = Presets.userNames
                } label: { Label("Save current", systemImage: "square.and.arrow.down") }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Saved")
        } footer: {
            Text("Applying a preset replaces all pond settings. Frame rate, Interactive and Low memory stay as they are.")
                .foregroundStyle(.secondary)
        }
    }
}

struct LookPage: View {
    @AppStorage("artStyle") private var artStyle = "natural"
    @AppStorage("pixelSize") private var pixelSize = 4.0
    @AppStorage("tiltOn") private var tiltOn = false
    @AppStorage("tiltStrength") private var tiltStrength = 100.0
    @AppStorage("tiltFocus") private var tiltFocus = 50.0
    @AppStorage("tiltBand") private var tiltBand = 15.0

    var body: some View {
        Section("Art style") {
            ChipPicker(choices: [
                Choice(tag: "natural", title: "Natural", symbol: "camera.fill"),
                Choice(tag: "painterly", title: "Painterly", symbol: "paintbrush.pointed.fill"),
                Choice(tag: "ink", title: "Ink wash", symbol: "scribble.variable"),
                Choice(tag: "pixel", title: "Pixel art", symbol: "square.grid.3x3.fill"),
            ], selection: $artStyle)
            if artStyle == "pixel" {
                SliderRow(title: "Pixel size", symbol: "square.grid.2x2", value: $pixelSize, range: 2...12, unit: " pt",
                          defaultValue: def("pixelSize"))
            }
        }
        Section {
            ToggleRow(title: "Tilt-shift focus", symbol: "camera.aperture",
                      note: "Blurs the top and bottom so the pond looks like a miniature.", isOn: $tiltOn)
            if tiltOn {
                SliderRow(title: "Blur", symbol: "drop.halffull", value: $tiltStrength, range: 20...200, step: 10,
                          defaultValue: def("tiltStrength"))
                SliderRow(title: "Focus position", symbol: "arrow.up.and.down", value: $tiltFocus, range: 10...90, step: 5,
                          defaultValue: def("tiltFocus"))
                SliderRow(title: "In-focus band", symbol: "rectangle.center.inset.filled", value: $tiltBand, range: 0...40, step: 5,
                          defaultValue: def("tiltBand"))
            }
        } header: {
            Text("Camera")
        } footer: {
            if artStyle != "natural" || tiltOn {
                Text("Art styles and tilt-shift add one full-screen pass (about 180 MB more memory).").foregroundStyle(.secondary)
            }
        }
    }
}

struct WaterPage: View {
    @AppStorage("water") private var water = "deep"
    @AppStorage("floorStyle") private var floorStyle = "original"
    @AppStorage("depth") private var depth = 70.0
    @AppStorage("depthDarken") private var depthDarken = true
    @AppStorage("wavesOn") private var wavesOn = true
    @AppStorage("waveIntensity") private var waveIntensity = 100.0
    @AppStorage("driftOn") private var driftOn = true
    @AppStorage("driftIntensity") private var driftIntensity = 100.0
    @AppStorage("skyOn") private var skyOn = true
    @AppStorage("wobbleOn") private var wobbleOn = true
    @AppStorage("wobbleIntensity") private var wobbleIntensity = 60.0
    @AppStorage("wobbleSize") private var wobbleSize = 100.0
    @AppStorage("lowMemory") private var lowMemory = false

    var body: some View {
        Section("Colour") {
            SwatchPicker(selection: $water)
        }
        Section("Pond floor") {
            FloorPicker(selection: $floorStyle, water: water)
            SliderRow(title: "Depth", symbol: "arrow.down.to.line", value: $depth, range: 0...100, step: 5, defaultValue: def("depth"))
            ToggleRow(title: "Darken deep water", symbol: "moon.haze",
                      note: depthDarken ? "Deeper water hides the floor and gets darker."
                                        : "Depth only moves shadows; the pond keeps its brightness.",
                      isOn: $depthDarken)
        }
        Section("Surface") {
            ToggleRow(title: "Light patterns", symbol: "sparkles", note: "Bright caustic lines on the floor.", isOn: $wavesOn)
            if wavesOn {
                SliderRow(title: "Intensity", value: $waveIntensity, range: 10...200, step: 10, defaultValue: def("waveIntensity"))
            }
            ToggleRow(title: "Drifting light", symbol: "light.max", isOn: $driftOn)
            if driftOn {
                SliderRow(title: "Intensity", value: $driftIntensity, range: 10...200, step: 10, defaultValue: def("driftIntensity"))
            }
            ToggleRow(title: "Sky reflections", symbol: "cloud", isOn: $skyOn)
        }
        Section {
            if lowMemory {
                InfoBanner(symbol: "memorychip", text: "Water distortion is off while Low memory mode is on.",
                           action: ("Turn off", { lowMemory = false }))
            }
            ToggleRow(title: "Water distortion", symbol: "water.waves",
                      note: "Everything under the surface wobbles as seen through moving water.", isOn: $wobbleOn)
                .disabled(lowMemory)
            if wobbleOn && !lowMemory {
                SliderRow(title: "Intensity", value: $wobbleIntensity, range: 10...250, step: 10, defaultValue: def("wobbleIntensity"))
                SliderRow(title: "Wave size", value: $wobbleSize, range: 40...250, step: 10, defaultValue: def("wobbleSize"))
            }
        } header: {
            Text("Movement")
        }
    }
}

struct LightPage: View {
    @AppStorage("lightAngle") private var lightAngle = 125.0
    @AppStorage("shadowStrength") private var shadowStrength = 100.0
    @AppStorage("shadowBlur") private var shadowBlur = 100.0
    @AppStorage("shadowDistance") private var shadowDistance = 100.0

    private var direction: String {
        let names = ["right", "upper right", "top", "upper left", "left", "lower left", "bottom", "lower right"]
        return names[Int(((lightAngle + 22.5).truncatingRemainder(dividingBy: 360)) / 45) % 8]
    }

    var body: some View {
        Section("Light") {
            HStack(spacing: 18) {
                LightDial(angle: $lightAngle)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Light from the \(direction)").font(.headline)
                    Text("Drag the sun around the dial. Every shadow falls the opposite way.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("\(Int(lightAngle))°").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        Section("Shadows") {
            SliderRow(title: "Strength", symbol: "circle.lefthalf.filled", value: $shadowStrength, range: 0...200, step: 10,
                      defaultValue: def("shadowStrength"))
            if shadowStrength > 0 {
                SliderRow(title: "Softness", symbol: "aqi.medium", value: $shadowBlur, range: 20...250, step: 10,
                          defaultValue: def("shadowBlur"))
                SliderRow(title: "Distance", symbol: "arrow.down.right", value: $shadowDistance, range: 0...250, step: 10,
                          defaultValue: def("shadowDistance"))
            }
        }
    }
}

// MARK: - Life

struct KoiPage: View {
    @AppStorage("koiCount") private var koiCount = 8.0
    @AppStorage("koiSpeed") private var koiSpeed = 100.0
    @AppStorage("koiSize") private var koiSize = 100.0
    @AppStorage("surfacingOn") private var surfacingOn = true
    @AppStorage("surfacingRate") private var surfacingRate = 100.0

    var body: some View {
        Section("School") {
            SliderRow(title: "Koi", symbol: "number", value: $koiCount, range: 1...24, unit: "", defaultValue: def("koiCount"))
            SliderRow(title: "Speed", symbol: "hare", value: $koiSpeed, range: 20...150, step: 5, defaultValue: def("koiSpeed"))
            SliderRow(title: "Size", symbol: "arrow.up.left.and.arrow.down.right", value: $koiSize, range: 50...160, step: 10,
                      defaultValue: def("koiSize"))
            if koiCount > 16 {
                InfoBanner(symbol: "gauge.with.dots.needle.67percent", text: "Many koi cost more CPU. Around 8–12 keeps the pond light.",
                           tint: .yellow)
            }
        }
        Section("Behaviour") {
            ToggleRow(title: "Surface to gulp air", symbol: "bubbles.and.sparkles",
                      note: "Now and then a koi rises and gulps with a small ripple.", isOn: $surfacingOn)
            if surfacingOn {
                SliderRow(title: "How often", value: $surfacingRate, range: 20...300, step: 10, defaultValue: def("surfacingRate"))
            }
        }
    }
}

struct WildlifePage: View {
    @AppStorage("minnowsOn") private var minnowsOn = true
    @AppStorage("minnowSchools") private var minnowSchools = 3.0
    @AppStorage("minnowFollow") private var minnowFollow = true
    @AppStorage("dragonflies") private var dragonflies = 2.0
    @AppStorage("frog") private var frog = true
    @AppStorage("turtle") private var turtle = true
    @AppStorage("padsOn") private var padsOn = true

    var body: some View {
        Section("In the water") {
            ToggleRow(title: "Small fish", symbol: "fish", isOn: $minnowsOn)
            if minnowsOn {
                SliderRow(title: "Schools", value: $minnowSchools, range: 1...8, unit: "", defaultValue: def("minnowSchools"))
                ToggleRow(title: "Follow the koi", isOn: $minnowFollow)
            }
            ToggleRow(title: "Turtle", symbol: "tortoise.fill", note: "Swims the bottom and climbs onto lily pads to rest.", isOn: $turtle)
        }
        Section("Above the water") {
            SliderRow(title: "Dragonflies", symbol: "wind", value: $dragonflies, range: 0...6, unit: "", defaultValue: def("dragonflies"))
            ToggleRow(title: "Frog", symbol: "hare.fill", note: "Sits on lily pads and hops between them.", isOn: $frog)
            if (frog || turtle) && !padsOn {
                InfoBanner(symbol: "leaf", text: "The frog needs lily pads, and the turtle rests on them.",
                           action: ("Turn on pads", { padsOn = true }))
            }
        }
    }
}

struct PlantsPage: View {
    @AppStorage("padsOn") private var padsOn = true
    @AppStorage("padClusters") private var padClusters = 5.0
    @AppStorage("flowers") private var flowers = true
    @AppStorage("reedsOn") private var reedsOn = true
    @AppStorage("reedAmount") private var reedAmount = 100.0
    @AppStorage("cattails") private var cattails = true
    @AppStorage("vinesOn") private var vinesOn = true

    var body: some View {
        Section("On the water") {
            ToggleRow(title: "Lily pads", symbol: "circle.hexagongrid.fill", isOn: $padsOn)
            if padsOn {
                SliderRow(title: "Clusters", value: $padClusters, range: 1...12, unit: "", defaultValue: def("padClusters"))
                ToggleRow(title: "Flowers", symbol: "camera.macro", isOn: $flowers)
            }
        }
        Section("Along the edge") {
            ToggleRow(title: "Reeds", symbol: "laurel.leading", isOn: $reedsOn)
            if reedsOn {
                SliderRow(title: "Amount", value: $reedAmount, range: 20...250, step: 10, defaultValue: def("reedAmount"))
                ToggleRow(title: "Cattails", isOn: $cattails)
            }
            ToggleRow(title: "Vines", symbol: "leaf.arrow.triangle.circlepath", isOn: $vinesOn)
        }
    }
}

// MARK: - Environment

struct TimePage: View {
    @AppStorage("timeOfDay") private var timeOfDay = "clock"
    @AppStorage("cycleMinutes") private var cycleMinutes = 20.0
    @AppStorage("fireflies") private var fireflies = true

    private var mode: String { timeOfDay == "clock" || timeOfDay == "cycle" ? timeOfDay : "fixed" }

    var body: some View {
        Section("Mode") {
            ChipPicker(choices: [
                Choice(tag: "clock", title: "My Mac's clock", symbol: "clock"),
                Choice(tag: "cycle", title: "Cycle", symbol: "arrow.2.circlepath"),
                Choice(tag: "fixed", title: "Fixed time", symbol: "pin.fill"),
            ], selection: Binding(get: { mode }, set: { new in
                if new == "fixed" { if mode != "fixed" { timeOfDay = "day" } } else { timeOfDay = new }
            }), minWidth: 120)
            if mode == "clock" {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    LabeledContent {
                        Text(context.date.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                    } label: { RowLabel(title: "Now", symbol: "clock.badge.checkmark") }
                }
            }
            if mode == "cycle" {
                SliderRow(title: "A full day takes", symbol: "timer", value: $cycleMinutes, range: 2...120, step: 2, unit: " min",
                          defaultValue: def("cycleMinutes"))
            }
        }
        if mode == "fixed" {
            Section("Time") {
                ChipPicker(choices: [
                    Choice(tag: "dawn", title: "Dawn", symbol: "sunrise.fill"),
                    Choice(tag: "morning", title: "Morning", symbol: "sun.haze.fill"),
                    Choice(tag: "day", title: "Day", symbol: "sun.max.fill"),
                    Choice(tag: "afternoon", title: "Afternoon", symbol: "sun.min.fill"),
                    Choice(tag: "sunset", title: "Sunset", symbol: "sunset.fill"),
                    Choice(tag: "dusk", title: "Dusk", symbol: "moon.haze.fill"),
                    Choice(tag: "night", title: "Night", symbol: "moon.stars.fill"),
                ], selection: $timeOfDay, minWidth: 84)
            }
        }
        Section("Night") {
            ToggleRow(title: "Fireflies", symbol: "sparkle", note: "From dusk until dawn, except in heavy rain.", isOn: $fireflies)
        }
    }
}

struct WeatherPage: View {
    @AppStorage("weather") private var weather = "auto"
    @AppStorage("windAmount") private var windAmount = 100.0
    @AppStorage("lightning") private var lightning = true
    @AppStorage("windAuto") private var windAuto = true
    @AppStorage("windRipplesOn") private var windRipplesOn = true
    @AppStorage("windRipples") private var windRipples = 100.0
    @AppStorage("lowMemory") private var lowMemory = false
    @AppStorage("windDirection") private var windDirection = 0.0

    private var windTowards: String {
        let names = ["right", "upper right", "top", "upper left", "left", "lower left", "bottom", "lower right"]
        return names[Int(((windDirection + 22.5).truncatingRemainder(dividingBy: 360)) / 45) % 8]
    }
    @AppStorage("rainMode") private var rainMode = "auto"
    @AppStorage("rainIntensity") private var rainIntensity = 100.0
    @AppStorage("rainDropSize") private var rainDropSize = 100.0
    @AppStorage("rainVary") private var rainVary = true
    @AppStorage("rainDim") private var rainDim = true

    /// Whether rain can happen with the current weather and rain mode.
    private var rainPossible: Bool {
        switch rainMode {
        case "never": return false
        case "always": return true
        default: return ["auto", "rain", "storm"].contains(weather)
        }
    }

    var body: some View {
        Section("Weather") {
            ChipPicker(choices: [
                Choice(tag: "auto", title: "Auto", symbol: "arrow.triangle.2.circlepath"),
                Choice(tag: "clear", title: "Clear", symbol: "sun.max.fill"),
                Choice(tag: "cloudy", title: "Cloudy", symbol: "cloud.fill"),
                Choice(tag: "rain", title: "Rain", symbol: "cloud.rain.fill"),
                Choice(tag: "storm", title: "Storm", symbol: "cloud.bolt.rain.fill"),
                Choice(tag: "windy", title: "Windy", symbol: "wind"),
            ], selection: $weather, minWidth: 80)
            if weather == "auto" {
                Text("Mostly fair, with cloudy, rainy, windy and the odd stormy spell. Changes every 75 seconds.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        Section {
            SliderRow(title: "Wind", symbol: "wind", value: $windAmount, range: 0...300, step: 10, defaultValue: def("windAmount"))
            if windAmount > 0 {
                HStack(spacing: 18) {
                    WindDial(angle: $windDirection, enabled: !windAuto)
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("", selection: $windAuto) {
                            Text("Wanders").tag(true)
                            Text("Fixed direction").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        Text(windAuto ? "The wind slowly changes direction on its own."
                                      : "Blowing toward the \(windTowards). Drag the arrow to change it.")
                            .font(.callout).foregroundStyle(.secondary)
                        if !windAuto {
                            Text("\(Int(windDirection))°").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            ToggleRow(title: "Wind ripples", symbol: "water.waves",
                      note: lowMemory ? "Off in Low memory mode." : "Gusts roughen the water in patches that race downwind.",
                      isOn: $windRipplesOn)
                .disabled(lowMemory)
            if windRipplesOn && !lowMemory {
                SliderRow(title: "Strength", value: $windRipples, range: 20...300, step: 10, defaultValue: def("windRipples"))
            }
            if ["auto", "storm"].contains(weather) {
                ToggleRow(title: "Lightning in storms", symbol: "bolt.fill", isOn: $lightning)
            }
        } header: {
            Text("Wind & storms")
        } footer: {
            Text("Wind blows petals, leaves and lily pads across the pond and makes plants sway. Windy and stormy weather multiply it.")
                .foregroundStyle(.secondary)
        }
        Section("Rain") {
            Picker(selection: $rainMode) {
                Text("With weather").tag("auto")
                Text("Always").tag("always")
                Text("Never").tag("never")
            } label: { RowLabel(title: "Rain", symbol: "cloud.rain") }
            .pickerStyle(.segmented)
            if rainPossible {
                SliderRow(title: "Intensity", symbol: "drop", value: $rainIntensity, range: 10...300, step: 10,
                          defaultValue: def("rainIntensity"))
                SliderRow(title: "Drop size", symbol: "circle.dotted", value: $rainDropSize, range: 50...200, step: 10,
                          defaultValue: def("rainDropSize"))
                ToggleRow(title: "Showers come and go", symbol: "waveform.path", isOn: $rainVary)
                ToggleRow(title: "Darken the pond while raining", symbol: "cloud.fog", isOn: $rainDim)
            } else if rainMode == "auto" {
                Text("No rain with \(weather.capitalized) weather. Choose Rain, Storm or Auto above, or set Rain to Always.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct SeasonPage: View {
    @AppStorage("season") private var season = "auto"
    @AppStorage("fallingOn") private var fallingOn = true
    @AppStorage("fallingAmount") private var fallingAmount = 100.0

    private var falling: String {
        switch season {
        case "spring": return "Cherry petals"
        case "summer": return "A few green leaves"
        case "autumn": return "Orange and red leaves"
        case "winter": return "Snow"
        default: return "Petals, leaves or snow"
        }
    }

    var body: some View {
        Section("Season") {
            ChipPicker(choices: [
                Choice(tag: "auto", title: "Auto", symbol: "arrow.triangle.2.circlepath"),
                Choice(tag: "spring", title: "Spring", symbol: "camera.macro"),
                Choice(tag: "summer", title: "Summer", symbol: "sun.max.fill"),
                Choice(tag: "autumn", title: "Autumn", symbol: "leaf.fill"),
                Choice(tag: "winter", title: "Winter", symbol: "snowflake"),
            ], selection: $season, minWidth: 84)
            if season == "auto" {
                Text("Changes every 4 minutes.").font(.callout).foregroundStyle(.secondary)
            }
        }
        Section("Falling from above") {
            ToggleRow(title: falling, symbol: "arrow.down.circle", isOn: $fallingOn)
            if fallingOn {
                SliderRow(title: "Amount", value: $fallingAmount, range: 10...200, step: 10, defaultValue: def("fallingAmount"))
            }
        }
    }
}

// MARK: - App

struct InteractionPage: View {
    @AppStorage("interactive") private var interactive = false
    @AppStorage("feedOn") private var feedOn = true
    @AppStorage("clickLure") private var clickLure = true
    @AppStorage("splashOn") private var splashOn = true
    @AppStorage("splashStrength") private var splashStrength = 100.0
    @AppStorage("lowMemory") private var lowMemory = false

    var body: some View {
        Section {
            ToggleRow(title: "Interactive", symbol: "cursorarrow.click.2",
                      note: "The pond takes clicks and covers desktop icons. App windows stay on top.", isOn: $interactive)
            if !interactive {
                InfoBanner(symbol: "info.circle", text: "Clicks only reach the pond while Interactive is on.", tint: .blue)
            }
        } header: {
            Text("Clicks")
        }
        Section("When you click") {
            ToggleRow(title: "Drop koi food", symbol: "takeoutbag.and.cup.and.straw",
                      note: "Pellets float; the nearest koi swim over to eat.", isOn: $feedOn)
            if !feedOn {
                ToggleRow(title: "Koi swim to the click", symbol: "scope", isOn: $clickLure)
            }
        }
        Section {
            if lowMemory {
                InfoBanner(symbol: "memorychip", text: "Ripples are drawn rings while Low memory mode is on.",
                           action: ("Turn off", { lowMemory = false }))
            }
            ToggleRow(title: "Realistic ripples", symbol: "water.waves",
                      note: "Clicks, rain and splashes bend the water instead of drawing rings.", isOn: $splashOn)
                .disabled(lowMemory)
            SliderRow(title: "Ripple strength", symbol: "dot.radiowaves.left.and.right", value: $splashStrength,
                      range: 20...300, step: 10, defaultValue: def("splashStrength"))
        } header: {
            Text("Ripples")
        }
    }
}

struct PerformancePage: View {
    @AppStorage("fps") private var fps = 0
    @AppStorage("lowMemory") private var lowMemory = false

    var body: some View {
        Section("Frame rate") {
            Picker(selection: $fps) {
                Text("Display max").tag(0)
                Text("60 fps").tag(60)
                Text("30 fps").tag(30)
            } label: { RowLabel(title: "Frame rate", symbol: "speedometer") }
            .pickerStyle(.segmented)
        }
        Section {
            ToggleRow(title: "Low memory mode", symbol: "memorychip",
                      note: "Skips the full-screen water distortion and draws the floor at lower resolution.", isOn: $lowMemory)
            LabeledContent {
                Text(lowMemory ? "about 180 MB" : "about 450–650 MB").foregroundStyle(.secondary)
            } label: { RowLabel(title: "Typical memory", symbol: "chart.bar") }
        } header: {
            Text("Memory")
        } footer: {
            Text("The pond always pauses while it's covered by windows, the screen is locked or the Mac sleeps.")
                .foregroundStyle(.secondary)
        }
    }
}

struct GeneralPage: View {
    @AppStorage("showStats") private var showStats = false
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Section("Startup") {
            ToggleRow(title: "Start at login", symbol: "power", isOn: $startAtLogin)
                .onChange(of: startAtLogin) { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        startAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        Section("Diagnostics") {
            ToggleRow(title: "Show FPS", symbol: "chart.xyaxis.line", note: "Frame rate, node and draw counts in the corner.",
                      isOn: $showStats)
        }
    }
}

// MARK: - Window

final class SettingsWindow {
    static let shared = SettingsWindow()
    private(set) var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "PondWall Settings"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 860, height: 640))
            w.setFrameAutosaveName("PondWallSettings")
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
