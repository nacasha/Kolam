// SettingsView — the settings panel, modelled on the original page's tabbed panel.
// Every control writes straight to UserDefaults; the pond applies it live.

import ServiceManagement
import SwiftUI

struct SettingsView: View {
    enum Tab: String, CaseIterable { case pond = "Pond", sky = "Sky", life = "Life", general = "General" }
    @State private var tab = Tab.pond

    // Pond
    @AppStorage("water") private var water = "deep"
    @AppStorage("wavesOn") private var wavesOn = true
    @AppStorage("waveIntensity") private var waveIntensity = 100.0
    @AppStorage("padsOn") private var padsOn = true
    @AppStorage("padClusters") private var padClusters = 5.0
    @AppStorage("flowers") private var flowers = true
    @AppStorage("depth") private var depth = 70.0
    @AppStorage("floorStyle") private var floorStyle = "original"
    @AppStorage("depthDarken") private var depthDarken = true
    @AppStorage("shadowStrength") private var shadowStrength = 100.0
    @AppStorage("shadowBlur") private var shadowBlur = 100.0
    @AppStorage("shadowDistance") private var shadowDistance = 100.0
    @AppStorage("lightAngle") private var lightAngle = 125.0
    @AppStorage("wobbleOn") private var wobbleOn = true
    @AppStorage("wobbleIntensity") private var wobbleIntensity = 60.0
    @AppStorage("wobbleSize") private var wobbleSize = 100.0
    @AppStorage("splashOn") private var splashOn = true
    @AppStorage("splashStrength") private var splashStrength = 100.0
    @AppStorage("driftOn") private var driftOn = true
    @AppStorage("driftIntensity") private var driftIntensity = 100.0
    @AppStorage("skyOn") private var skyOn = true
    @AppStorage("vinesOn") private var vinesOn = true
    // Sky
    @AppStorage("weather") private var weather = "auto"
    @AppStorage("season") private var season = "auto"
    @AppStorage("fallingOn") private var fallingOn = true
    @AppStorage("fallingAmount") private var fallingAmount = 100.0
    @AppStorage("fireflies") private var fireflies = true
    @AppStorage("rainMode") private var rainMode = "auto"
    @AppStorage("rainIntensity") private var rainIntensity = 100.0
    @AppStorage("rainDropSize") private var rainDropSize = 100.0
    @AppStorage("rainVary") private var rainVary = true
    @AppStorage("rainDim") private var rainDim = true
    // Life
    @AppStorage("koiCount") private var koiCount = 8.0
    @AppStorage("koiSpeed") private var koiSpeed = 100.0
    @AppStorage("koiSize") private var koiSize = 100.0
    @AppStorage("clickLure") private var clickLure = true
    @AppStorage("minnowsOn") private var minnowsOn = true
    @AppStorage("minnowSchools") private var minnowSchools = 3.0
    @AppStorage("minnowFollow") private var minnowFollow = true
    @AppStorage("dragonflies") private var dragonflies = 2.0
    @AppStorage("frog") private var frog = true
    // General
    @AppStorage("fps") private var fps = 0
    @AppStorage("interactive") private var interactive = false
    @AppStorage("showStats") private var showStats = false
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 16)

            Form {
                switch tab {
                case .pond: pond
                case .sky: sky
                case .life: life
                case .general: general
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 420, height: 520)
    }

    @ViewBuilder private var pond: some View {
        Section {
            LabeledContent("Water") {
                HStack(spacing: 8) {
                    ForEach(WaterPreset.all, id: \.name) { preset in
                        Button { water = preset.name } label: {
                            Circle()
                                .fill(Color(nsColor: preset.swatch))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: water == preset.name ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }
                }
            }
        }
        Section {
            Picker("Pond floor", selection: $floorStyle) {
                Text("Original").tag("original")
                Text("Sand").tag("sand")
                Text("Stones").tag("stones")
                Text("Gravel").tag("gravel")
                Text("Moss").tag("moss")
                Text("Slate").tag("slate")
                Text("Cracked clay").tag("clay")
                Text("Plain").tag("plain")
            }
            slider("Pond depth", $depth, 0...100, step: 5, unit: "%")
            Toggle("Darken deep water", isOn: $depthDarken)
        } footer: {
            Text(depthDarken
                 ? "Deeper water hides more of the floor, and shadows fall further and softer."
                 : "Depth only moves shadows further and softer; the pond keeps its brightness.")
                .foregroundStyle(.secondary)
        }
        Section {
            slider("Strength", $shadowStrength, 0...200, step: 10, unit: "%")
            slider("Blur", $shadowBlur, 20...250, step: 10, unit: "%")
            slider("Distance", $shadowDistance, 0...250, step: 10, unit: "%")
            slider("Light from", $lightAngle, 0...350, step: 10, unit: "°")
        } header: {
            Text("Shadows")
        } footer: {
            Text("Light from: 90° is the top, 180° the left, 0° the right.").foregroundStyle(.secondary)
        }
        Section {
            Toggle("Water distortion", isOn: $wobbleOn)
            if wobbleOn {
                slider("Intensity", $wobbleIntensity, 10...250, step: 10, unit: "%")
                slider("Wave size", $wobbleSize, 40...250, step: 10, unit: "%")
            }
            Toggle("Clicks send real ripples", isOn: $splashOn)
            if splashOn { slider("Ripple strength", $splashStrength, 20...300, step: 10, unit: "%") }
        } footer: {
            Text("The floor, fish and shadows wobble as seen through moving water; lily pads and petals bob on it. Click ripples need Interactive on.")
                .foregroundStyle(.secondary)
        }
        Section {
            Toggle("Light patterns", isOn: $wavesOn)
            if wavesOn { slider("Intensity", $waveIntensity, 10...200, step: 10, unit: "%") }
        }
        Section {
            Toggle("Drifting light", isOn: $driftOn)
            if driftOn { slider("Intensity", $driftIntensity, 10...200, step: 10, unit: "%") }
            Toggle("Sky reflections", isOn: $skyOn)
        }
        Section {
            Toggle("Lily pads", isOn: $padsOn)
            if padsOn {
                slider("Clusters", $padClusters, 1...12, step: 1)
                Toggle("Flowers", isOn: $flowers)
            }
            Toggle("Vines", isOn: $vinesOn)
        }
    }

    @ViewBuilder private var sky: some View {
        Section {
            Picker("Weather", selection: $weather) {
                Text("Auto").tag("auto")
                Text("Clear").tag("clear")
                Text("Rain").tag("rain")
                Text("Night").tag("night")
            }
            Picker("Season", selection: $season) {
                Text("Auto").tag("auto")
                Text("Spring").tag("spring")
                Text("Summer").tag("summer")
                Text("Autumn").tag("autumn")
                Text("Winter").tag("winter")
            }
        } footer: {
            Text("Auto changes the weather every 75 seconds and the season every 4 minutes.")
                .foregroundStyle(.secondary)
        }
        Section {
            Picker("Rain", selection: $rainMode) {
                Text("Auto").tag("auto")
                Text("Always").tag("always")
                Text("Never").tag("never")
            }
            .pickerStyle(.segmented)
            if rainMode != "never" {
                slider("Intensity", $rainIntensity, 10...300, step: 10, unit: "%")
                slider("Drop size", $rainDropSize, 50...200, step: 10, unit: "%")
                Toggle("Showers come and go", isOn: $rainVary)
                Toggle("Darken the pond while raining", isOn: $rainDim)
            }
        } header: {
            Text("Rain")
        } footer: {
            Text("Auto rains only when the weather is Rain. Always rains in any weather, even at night.")
                .foregroundStyle(.secondary)
        }
        Section {
            Toggle("Falling petals, leaves & snow", isOn: $fallingOn)
            if fallingOn { slider("Amount", $fallingAmount, 10...200, step: 10, unit: "%") }
            Toggle("Fireflies at night", isOn: $fireflies)
        }
    }

    @ViewBuilder private var life: some View {
        Section {
            slider("Koi", $koiCount, 1...24, step: 1)
            slider("Koi speed", $koiSpeed, 20...150, step: 5, unit: "%")
            slider("Koi size", $koiSize, 50...160, step: 10, unit: "%")
        }
        Section {
            Toggle("Small fish", isOn: $minnowsOn)
            if minnowsOn {
                slider("Schools", $minnowSchools, 1...8, step: 1)
                Toggle("Follow koi", isOn: $minnowFollow)
            }
            slider("Dragonflies", $dragonflies, 0...6, step: 1)
            Toggle("Frog", isOn: $frog)
        }
        Section {
            Toggle("Koi come to clicks", isOn: $clickLure)
        } footer: {
            Text("Clicks reach the pond only while Interactive is on.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var general: some View {
        Section {
            Picker("Frame rate", selection: $fps) {
                Text("Display max").tag(0)
                Text("60 fps").tag(60)
                Text("30 fps").tag(30)
            }
            Toggle("Show FPS", isOn: $showStats)
        }
        Section {
            Toggle("Interactive", isOn: $interactive)
        } footer: {
            Text("The pond takes clicks and covers desktop icons. App windows stay on top.")
                .foregroundStyle(.secondary)
        }
        Section {
            Toggle("Start at Login", isOn: $startAtLogin)
                .onChange(of: startAtLogin) { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        startAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        step: Double, unit: String = "") -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: step)
                Text("\(Int(value.wrappedValue))\(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "PondWall Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
