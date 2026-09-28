// SettingsUI — building blocks for the settings window: icon badges, rows with
// icons, value sliders, choice chips and swatches, and info banners.

import SwiftUI

/// A coloured rounded square with a white symbol, like System Settings.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// Row label: a small tinted symbol, a title and an optional note underneath.
struct RowLabel: View {
    let title: String
    var symbol: String?
    var note: String?

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ToggleRow: View {
    let title: String
    var symbol: String?
    var note: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { RowLabel(title: title, symbol: symbol, note: note) }
    }
}

/// Slider with its current value shown, and a double-click on the value to reset it.
struct SliderRow: View {
    let title: String
    var symbol: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = "%"
    var defaultValue: Double?

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                // Snap in the binding rather than with `step:`, which draws a tick per step.
                Slider(value: Binding(get: { value }, set: { value = (($0 / step).rounded() * step).clamped(to: range) }),
                       in: range)
                    .frame(minWidth: 140)
                Text("\(Int(value.rounded()))\(unit)")
                    .monospacedDigit()
                    .foregroundStyle(defaultValue.map { $0 == value } ?? true ? .secondary : Color.accentColor)
                    .frame(width: 52, alignment: .trailing)
                    .help(defaultValue.map { "Double-click to reset to \(Int($0))\(unit)" } ?? "")
                    .onTapGesture(count: 2) { if let d = defaultValue { value = d } }
            }
        } label: {
            RowLabel(title: title, symbol: symbol)
        }
    }
}

/// One option for ChipPicker.
struct Choice: Identifiable {
    let tag: String
    let title: String
    let symbol: String
    var id: String { tag }
}

/// A grid of tappable chips with icons: better than a menu when the options are visual.
struct ChipPicker: View {
    let choices: [Choice]
    @Binding var selection: String
    var minWidth: CGFloat = 96

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: 8)], spacing: 8) {
            ForEach(choices) { c in
                let selected = selection == c.tag
                Button { selection = c.tag } label: {
                    VStack(spacing: 5) {
                        Image(systemName: c.symbol)
                            .font(.system(size: 17))
                            .symbolRenderingMode(.hierarchical)
                        Text(c.title).font(.caption).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(selected ? Color.accentColor : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Water colour swatches with names.
struct SwatchPicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 12) {
            ForEach(WaterPreset.all, id: \.name) { preset in
                let selected = selection == preset.name
                Button { selection = preset.name } label: {
                    VStack(spacing: 5) {
                        Circle()
                            .fill(LinearGradient(colors: [Color(nsColor: preset.swatch), Color(nsColor: preset.mid(depth: 0.3))],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                            .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5).padding(-4))
                        Text(preset.name.capitalized)
                            .font(.caption)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A small note inside a section, with an optional action.
struct InfoBanner: View {
    let symbol: String
    let text: String
    var tint: Color = .orange
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action.title, action: action.run).controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.1)))
    }
}

/// Wind direction dial: drag to point where the wind blows toward.
struct WindDial: View {
    @Binding var angle: Double
    var enabled = true

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size / 2 - 10
            let a = angle * .pi / 180
            ZStack {
                Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                ForEach(0..<3) { k in
                    Image(systemName: "wind")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.teal.opacity(0.35))
                        .offset(x: CGFloat(k - 1) * 12 - 6, y: CGFloat(k - 1) * 10)
                        .rotationEffect(.radians(-a))
                }
                Image(systemName: "location.north.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(enabled ? Color.teal : Color.secondary)
                    .rotationEffect(.radians(.pi / 2 - a))
                    .offset(x: cos(a) * r * 0.62, y: -sin(a) * r * 0.62)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                guard enabled else { return }
                let dx = g.location.x - size / 2, dy = size / 2 - g.location.y
                var deg = atan2(dy, dx) * 180 / .pi
                if deg < 0 { deg += 360 }
                angle = (deg / 5).rounded() * 5
            })
        }
        .frame(width: 92, height: 92)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// Light direction dial: drag or click to point the light; shadows fall the other way.
struct LightDial: View {
    @Binding var angle: Double

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size / 2 - 10
            let a = angle * .pi / 180
            ZStack {
                Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                Circle().fill(Color.primary.opacity(0.05)).frame(width: size * 0.36)
                // Shadow cast away from the light.
                Capsule()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: r * 0.55, height: 6)
                    .offset(x: r * 0.3)
                    .rotationEffect(.radians(-(a + .pi)))
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.orange)
                    .offset(x: cos(a) * r, y: -sin(a) * r)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let dx = g.location.x - size / 2, dy = size / 2 - g.location.y
                var deg = atan2(dy, dx) * 180 / .pi
                if deg < 0 { deg += 360 }
                angle = (deg / 5).rounded() * 5
            })
        }
        .frame(width: 92, height: 92)
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

/// Pond floor choices as picture tiles, previewed in the current water colour.
struct FloorPicker: View {
    @Binding var selection: String
    let water: String
    @State private var previews: [String: CGImage] = [:]

    private let styles: [(tag: String, title: String)] = [
        ("original", "Original"), ("sand", "Sand"), ("stones", "Stones"), ("gravel", "Gravel"),
        ("moss", "Moss"), ("slate", "Slate"), ("clay", "Cracked clay"), ("plain", "Plain"),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
            ForEach(styles, id: \.tag) { s in
                let selected = selection == s.tag
                Button { selection = s.tag } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06))
                            if let img = previews[s.tag] {
                                Image(decorative: img, scale: 1).resizable().scaledToFill()
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .frame(height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1)
                        )
                        Text(s.title).font(.caption).foregroundStyle(selected ? Color.accentColor : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .task(id: water) { await render() }
    }

    /// Bakes the previews off the main thread; they take a moment each.
    private func render() async {
        let preset = WaterPreset.named(water)
        let tags = styles.map(\.tag)
        let images = await Task.detached(priority: .userInitiated) { () -> [String: CGImage] in
            var result: [String: CGImage] = [:]
            for tag in tags {
                if let style = FloorStyle(rawValue: tag), let img = Floor.preview(style: style, water: preset) {
                    result[tag] = img
                }
            }
            return result
        }.value
        previews = images
    }
}
