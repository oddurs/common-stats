import StatKit
import SwiftUI

/// What the dropdown shows: a card per metric that has a history worth
/// graphing, in menu bar order, then one row of compact gauge tiles for the
/// slow-moving ones. Each panel becomes its own menu item.
enum DropdownPanel: Hashable {
    case card(Metric)
    case tiles([Metric])

    static let width: CGFloat = 320

    static func panels(for metrics: [Metric]) -> [DropdownPanel] {
        let tiles = metrics.filter(\.isTile)
        return metrics.filter { !$0.isTile }.map(DropdownPanel.card) + (tiles.isEmpty ? [] : [.tiles(tiles)])
    }
}

extension Metric {
    /// Single current values that read best as a gauge rather than a graph.
    var isTile: Bool { self == .gpu || self == .storage || self == .battery }
}

/// The menu's view of the model. Reading `model.readout` here is what makes
/// an open menu redraw on each sample; `PanelView` is a pure function of a
/// readout, so the snapshot tool can render it offscreen.
struct LivePanel: View {
    let model: AppModel
    let panel: DropdownPanel

    var body: some View {
        PanelView(readout: model.readout, panel: panel, interval: model.layout.interval, palette: model.layout.palette)
    }
}

struct PanelView: View {
    let readout: Readout
    let panel: DropdownPanel
    let interval: TimeInterval
    let palette: Palette
    var previewHover: Int?

    var body: some View {
        Group {
            switch panel {
            case .card(let metric):
                MetricCard(
                    readout: readout, metric: metric, interval: interval, ink: Ink(palette.color(for: metric)),
                    previewHover: previewHover)
            case .tiles(let metrics):
                HStack(spacing: 8) {
                    ForEach(metrics, id: \.self) {
                        MetricTile(readout: readout, metric: $0, ink: Ink(palette.color(for: $0)))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(width: DropdownPanel.width)
    }
}

// MARK: - Cards

private struct MetricCard: View {
    let readout: Readout
    let metric: Metric
    let interval: TimeInterval
    let ink: Ink
    let previewHover: Int?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    IconTile(metric: metric, size: 20)
                    Text(metric == .disk ? "Disk" : metric.name).font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if metric == .network, let source = readout.latest.network?.source {
                        Text(source).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 8)
                    headline
                }
                content
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var headline: some View {
        let big = Font.system(size: 15, weight: .semibold).monospacedDigit()
        switch metric {
        case .network, .disk:
            let r = readout.rates(metric)
            let (inGlyph, outGlyph) = metric == .network ? ("↓", "↑") : ("R", "W")
            // The glyphs take their graph colours, so the header doubles as the legend.
            HStack(spacing: 10) {
                Reading(glyph: inGlyph, value: r.map { Format.rate($0.inbound) }, ink: ink.strong)
                Reading(glyph: outGlyph, value: r.map { Format.rate($0.outbound) }, ink: ink.medium)
            }
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
        case .memory:
            if let m = readout.latest.memory {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Format.memory(m.used)).font(big)
                    Text("of \(Format.memory(m.total))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        default:
            Text(readout.valueText(metric)).font(big)
        }
    }

    @ViewBuilder private var content: some View {
        switch metric {
        case .cpu: cpu
        case .memory: memory
        case .network, .disk: rates
        case .gpu, .storage, .battery: EmptyView()
        }
    }

    @ViewBuilder private var cpu: some View {
        HistoryChart(
            up: [
                ChartSeries(name: "CPU", history: readout.primary[.cpu], ink: ink.strong, emphasis: true),
                ChartSeries(name: "System", history: readout.secondary[.cpu], ink: ink.soft, emphasis: false),
            ],
            scale: .fraction, interval: interval, format: Format.percent, previewHover: previewHover)
        if let c = readout.latest.cpu {
            Facts([
                Fact("User", Format.percent(c.user), key: ink.strong),
                Fact("System", Format.percent(c.system), key: ink.soft),
                Fact("Idle", Format.percent(1 - c.total)),
            ])
            CoreClusters(
                cores: c.cores, topology: .current, ink: ink.strong, width: DropdownPanel.width - 16 - cardInset * 2)
            Facts([
                Fact(
                    "Load",
                    [c.loadAverage.0, c.loadAverage.1, c.loadAverage.2]
                        .map { $0.formatted(.number.precision(.fractionLength(2))) }
                        .joined(separator: " ")),
                Fact("Uptime", Format.uptime(Date().timeIntervalSince(systemBootDate))),
            ])
        }
    }

    @ViewBuilder private var memory: some View {
        if let m = readout.latest.memory {
            HStack(spacing: 8) {
                Segments(
                    fractions: [m.app, m.wired, m.compressed].map { Double($0) / Double(m.total) },
                    inks: [ink.strong, ink.medium, ink.soft])
                PressurePill(pressure: m.pressure)
            }
            HistoryChart(
                up: [ChartSeries(name: "Used", history: readout.primary[.memory], ink: ink.strong, emphasis: true)],
                scale: .fraction, interval: interval, format: Format.percent, height: 30, previewHover: previewHover)
            Facts(
                [
                    Fact("App", Format.memory(m.app), key: ink.strong),
                    Fact("Wired", Format.memory(m.wired), key: ink.medium),
                    Fact("Compressed", Format.memory(m.compressed), key: ink.soft),
                    Fact("Cached", Format.memory(m.cached)),
                    Fact("Swap", Format.memory(m.swapUsed)),
                ], columns: 2)
        }
    }

    @ViewBuilder private var rates: some View {
        let network = metric == .network
        HistoryChart(
            up: [
                ChartSeries(
                    name: network ? "Upload" : "Write", history: readout.secondary[metric], ink: ink.medium,
                    emphasis: true)
            ],
            down: [
                ChartSeries(
                    name: network ? "Download" : "Read", history: readout.primary[metric], ink: ink.strong,
                    emphasis: true)
            ],
            scale: .rate(floor: metric.rateFloor), interval: interval, format: { Format.rate($0) },
            previewHover: previewHover)
    }
}

private let cardInset: CGFloat = 10

/// A Control Center–style module: a softly filled rounded panel.
private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

private struct Reading: View {
    let glyph: String
    let value: String?
    let ink: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(glyph).foregroundStyle(ink)
            Text(value ?? Format.missing)
        }
    }
}

// MARK: - Tiles

/// A compact gauge for a single current value: name, ring, and a caption.
private struct MetricTile: View {
    let readout: Readout
    let metric: Metric
    let ink: Ink

    var body: some View {
        Card {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    IconTile(metric: metric, size: 16)
                    Text(metric.name).font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Ring(fraction: readout.fraction(metric) ?? 0, ink: ringInk) {
                    VStack(spacing: 0) {
                        Text(center).font(.system(size: 12, weight: .semibold).monospacedDigit())
                        if metric == .battery, readout.latest.battery?.state == .charging {
                            Image(systemName: "bolt.fill").font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text(caption).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.name) \(center), \(caption)")
    }

    private var center: String {
        metric == .storage
            ? readout.latest.storage.map { Format.percent($0.usedFraction) } ?? Format.missing
            : readout.valueText(metric)
    }

    private var caption: String {
        switch metric {
        case .storage:
            readout.latest.storage.map { "\(Format.bytes(Double($0.available))) free" } ?? " "
        case .battery:
            readout.latest.battery.map(batteryStatus) ?? " "
        default:
            "Utilization"
        }
    }

    /// Alert colours override the palette only when something needs attention.
    private var ringInk: Color {
        switch metric {
        case .battery:
            if let b = readout.latest.battery, b.level <= 0.1, b.state == .discharging { return .red }
        case .storage:
            if let s = readout.latest.storage, s.usedFraction >= 0.9 { return .orange }
        default: break
        }
        return ink.strong
    }

    private func batteryStatus(_ b: BatteryReading) -> String {
        let time = b.minutesRemaining.map { Format.duration(minutes: $0) }
        switch b.state {
        case .charging: return time.map { "\($0) to full" } ?? "Charging"
        case .charged: return "Charged"
        case .onACNotCharging: return "Not charging"
        case .discharging: return time.map { "\($0) left" } ?? "On battery"
        }
    }
}

private struct Ring<Label: View>: View {
    let fraction: Double
    let ink: Color
    @ViewBuilder let label: Label

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(ink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
        .frame(width: 48, height: 48)
    }
}

// MARK: - Shared pieces

/// Three steps of one palette colour, used consistently: the strongest is
/// always the primary series and the legend dots match the marks. Over a
/// dark menu, translucency darkens, so the lighter steps carry more alpha
/// there to stay distinguishable.
struct Ink {
    let strong: Color
    let medium: Color
    let soft: Color

    init(_ base: NSColor) {
        strong = Color(nsColor: base)
        medium = Self.tint(base, light: 0.62, dark: 0.72)
        soft = Self.tint(base, light: 0.36, dark: 0.5)
    }

    private static func tint(_ base: NSColor, light: CGFloat, dark: CGFloat) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return base.withAlphaComponent(isDark ? dark : light)
            })
    }
}

private struct PressurePill: View {
    let pressure: MemoryReading.Pressure

    var body: some View {
        let (name, color): (String, Color) =
            switch pressure {
            case .normal: ("Normal", .green)
            case .warning: ("Warning", .orange)
            case .critical: ("Critical", .red)
            }
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name).font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityLabel("Memory pressure \(name)")
    }
}

private struct Fact: Identifiable {
    let label: String
    let value: String?
    var key: Color?
    var id: String { label }

    init(_ label: String, _ value: String?, key: Color? = nil) {
        self.label = label
        self.value = value
        self.key = key
    }
}

/// Label/value pairs on an aligned grid. A fact with a `key` gets a legend
/// dot in the colour of its chart mark.
private struct Facts: View {
    let facts: [Fact]
    let columns: Int

    init(_ facts: [Fact], columns: Int = 3) {
        self.facts = facts
        self.columns = columns
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(Array(stride(from: 0, to: facts.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(facts[start..<min(start + columns, facts.count)]) { fact in
                        HStack(spacing: 5) {
                            if let key = fact.key {
                                Circle().fill(key).frame(width: 6, height: 6)
                            }
                            Text(fact.label).foregroundStyle(.secondary)
                        }
                        Text(fact.value ?? "")
                            .monospacedDigit()
                            .padding(.trailing, 12)
                            .gridColumnAlignment(.leading)
                    }
                }
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .fixedSize()
    }
}

/// A horizontal bar split into consecutive segments.
private struct Segments: View {
    let fractions: [Double]
    let inks: [Color]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(fractions.indices, id: \.self) { i in
                    Rectangle()
                        .fill(inks[min(i, inks.count - 1)])
                        .frame(width: max(geo.size.width * min(max(fractions[i], 0), 1) - 1.5, 0))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 6)
        .background(Color.primary.opacity(0.08))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// Core bars grouped into efficiency and performance clusters, each captioned
/// with its average load. Bars keep one width across groups so they compare.
/// Without a known topology, all cores show as one ungrouped row.
private struct CoreClusters: View {
    let cores: [Double]
    let topology: CPUTopology
    let ink: Color
    let width: CGFloat

    private let gap: CGFloat = 10
    private let spacing: CGFloat = 2

    var body: some View {
        let clusters = topology.clusters
        if clusters.isEmpty || clusters.map(\.cores.count).reduce(0, +) != cores.count {
            CoreBars(cores: cores, ink: ink)
        } else {
            let gaps = gap * CGFloat(clusters.count - 1) + spacing * CGFloat(cores.count - clusters.count)
            let bar = (width - gaps) / CGFloat(cores.count)
            HStack(alignment: .top, spacing: gap) {
                ForEach(clusters, id: \.kind) { cluster in
                    let load = cluster.cores.map { cores[$0] }
                    VStack(alignment: .leading, spacing: 4) {
                        CoreBars(cores: load, ink: ink)
                        HStack(spacing: 4) {
                            Text(cluster.kind.rawValue).foregroundStyle(.secondary)
                            Text(Format.percent(load.reduce(0, +) / Double(load.count))).monospacedDigit()
                        }
                        .font(.system(size: 10))
                        .lineLimit(1)
                    }
                    .frame(width: bar * CGFloat(load.count) + spacing * CGFloat(load.count - 1))
                }
            }
        }
    }
}

/// One thin bar per logical core, in kernel order.
private struct CoreBars: View {
    let cores: [Double]
    let ink: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(cores.indices, id: \.self) { i in
                ZStack(alignment: .bottom) {
                    Rectangle().fill(Color.primary.opacity(0.08))
                    Rectangle().fill(ink)
                        .frame(height: 14 * CGFloat(min(max(cores[i], 0), 1)))
                }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}
