import StatKit
import SwiftUI

/// The menu's view of the model. Reading `model.readout` here is what makes
/// an open menu redraw on each sample; `MetricDetail` itself is a pure
/// function of a readout, so it can also be rendered offscreen.
struct LiveMetricDetail: View {
    let model: AppModel
    let metric: Metric

    var body: some View { MetricDetail(readout: model.readout, metric: metric) }
}

/// One section of the dropdown menu, sized and spaced to sit among native
/// menu items: 14 pt side insets, system fonts, accent-colour charts.
struct MetricDetail: View {
    static let width: CGFloat = 300

    let readout: Readout
    let metric: Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(width: Self.width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(metric.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            headline
                .font(.system(size: 13, weight: .medium).monospacedDigit())
        }
    }

    @ViewBuilder private var headline: some View {
        switch metric {
        case .network, .disk:
            let r = readout.rates(metric)
            let (inGlyph, outGlyph) = metric == .network ? ("↓", "↑") : ("R", "W")
            HStack(spacing: 10) {
                pair(inGlyph, r.map { Format.rate($0.inbound) })
                pair(outGlyph, r.map { Format.rate($0.outbound) })
            }
        case .memory:
            if let m = readout.latest.memory {
                HStack(spacing: 3) {
                    Text(Format.memory(m.used))
                    Text("of \(Format.memory(m.total))").foregroundStyle(.secondary)
                }
            }
        case .storage:
            if let s = readout.latest.storage {
                HStack(spacing: 3) {
                    Text(Format.bytes(Double(s.available)))
                    Text("available").foregroundStyle(.secondary)
                }
            }
        default:
            Text(readout.valueText(metric))
        }
    }

    private func pair(_ glyph: String, _ value: String?) -> some View {
        HStack(spacing: 3) {
            Text(glyph).foregroundStyle(.secondary)
            Text(value ?? Format.missing)
        }
    }

    @ViewBuilder private var content: some View {
        switch metric {
        case .cpu: cpu
        case .gpu: Chart(primary: readout.primary[.gpu], secondary: nil, mirrored: false, floor: 1)
        case .memory: memory
        case .network: rates(source: readout.latest.network?.source)
        case .disk: rates(source: nil)
        case .storage: storage
        case .battery: battery
        }
    }

    @ViewBuilder private var cpu: some View {
        Chart(primary: readout.primary[.cpu], secondary: readout.secondary[.cpu], mirrored: false, floor: 1)
        if let c = readout.latest.cpu {
            Facts([
                Fact("User", Format.percent(c.user), key: Ink.strong),
                Fact("System", Format.percent(c.system), key: Ink.soft),
                Fact("Idle", Format.percent(1 - c.total)),
            ])
            CoreClusters(cores: c.cores, topology: .current, width: Self.width - 28)
            Facts([
                Fact(
                    "Load",
                    [c.loadAverage.0, c.loadAverage.1, c.loadAverage.2]
                        .map { $0.formatted(.number.precision(.fractionLength(2))) }
                        .joined(separator: "  ")),
                Fact("Uptime", Format.uptime(Date().timeIntervalSince(systemBootDate))),
            ])
        }
    }

    @ViewBuilder private var memory: some View {
        if let m = readout.latest.memory {
            let parts = [m.app, m.wired, m.compressed].map { Double($0) / Double(m.total) }
            Segments(fractions: parts, inks: [Ink.strong, Ink.medium, Ink.soft])
            Facts(
                [
                    Fact("App", Format.memory(m.app), key: Ink.strong),
                    Fact("Wired", Format.memory(m.wired), key: Ink.medium),
                    Fact("Compressed", Format.memory(m.compressed), key: Ink.soft),
                    Fact("Cached", Format.memory(m.cached)),
                    Fact("Swap", Format.memory(m.swapUsed)),
                    pressure(m.pressure),
                ], columns: 2)
        }
    }

    @ViewBuilder private func rates(source: String?) -> some View {
        Chart(
            primary: readout.primary[metric], secondary: readout.secondary[metric], mirrored: true,
            floor: metric.rateFloor)
        let (inName, outName) = metric == .network ? ("Download", "Upload") : ("Read", "Write")
        Facts(
            [
                Fact(inName, nil, key: Ink.strong),
                Fact(outName, nil, key: Ink.medium),
                source.map { Fact("Interface", $0) },
            ].compactMap { $0 })
    }

    @ViewBuilder private var storage: some View {
        if let s = readout.latest.storage {
            Segments(fractions: [s.usedFraction], inks: [Ink.strong])
            Facts([
                Fact("Volume", s.name),
                Fact("Capacity", Format.bytes(Double(s.total))),
            ])
        }
    }

    @ViewBuilder private var battery: some View {
        if let b = readout.latest.battery {
            Segments(fractions: [b.level], inks: [b.level <= 0.1 && b.state == .discharging ? .red : Ink.strong])
            Facts([Fact("Status", batteryStatus(b))])
        }
    }

    private func pressure(_ p: MemoryReading.Pressure) -> Fact {
        switch p {
        case .normal: Fact("Pressure", "Normal")
        case .warning: Fact("Pressure", "Warning", tint: .orange)
        case .critical: Fact("Pressure", "Critical", tint: .red)
        }
    }

    private func batteryStatus(_ b: BatteryReading) -> String {
        let time = b.minutesRemaining.map { Format.duration(minutes: $0) }
        switch b.state {
        case .charging: return time.map { "Charging, \($0) until full" } ?? "Charging"
        case .charged: return "Fully charged"
        case .onACNotCharging: return "Not charging"
        case .discharging: return time.map { "\($0) remaining" } ?? "On battery"
        }
    }
}

/// Three steps of the accent colour, used consistently: the strongest is
/// always the primary series and the legend dots match the marks. Over a
/// dark menu, translucency darkens, so the lighter steps carry more alpha
/// there to stay distinguishable.
private enum Ink {
    static let strong = Color.accentColor
    static let medium = tint(light: 0.62, dark: 0.72)
    static let soft = tint(light: 0.36, dark: 0.5)

    private static func tint(light: CGFloat, dark: CGFloat) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor.controlAccentColor.withAlphaComponent(isDark ? dark : light)
            })
    }
}

private struct Fact: Identifiable {
    let label: String
    let value: String?
    var key: Color?
    var tint: Color?
    var id: String { label }

    init(_ label: String, _ value: String?, key: Color? = nil, tint: Color? = nil) {
        self.label = label
        self.value = value
        self.key = key
        self.tint = tint
    }
}

/// Label/value pairs on an aligned grid, like Activity Monitor's footer. A
/// fact with a `key` gets a legend dot in the colour of its chart mark.
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
                            .foregroundStyle(fact.tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                            .padding(.trailing, 14)
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

/// History chart; newest sample on the right, spread across the full width.
/// A line over a soft gradient for the primary series; a solid band beneath
/// for CPU system time; for rate pairs, inbound hangs below the midline and
/// outbound rises above it.
private struct Chart: View {
    let primary: History?
    let secondary: History?
    let mirrored: Bool
    let floor: Double

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0, dy: 1)
            let step = size.width / CGFloat(Readout.capacity - 1)
            if mirrored {
                let peak = max(
                    primary?.max(last: Readout.capacity) ?? 0, secondary?.max(last: Readout.capacity) ?? 0, floor)
                var top = rect
                top.size.height /= 2
                var bottom = top
                bottom.origin.y = top.maxY
                context.fill(
                    Path(CGRect(x: 0, y: top.maxY - 0.25, width: size.width, height: 0.5)),
                    with: .color(.secondary.opacity(0.35)))
                if let secondary {
                    series(
                        context, secondary, in: top, step: step, scale: peak, down: false, ink: Ink.medium, line: true)
                }
                if let primary {
                    series(
                        context, primary, in: bottom, step: step, scale: peak, down: true, ink: Ink.strong, line: true)
                }
            } else {
                if let primary {
                    series(
                        context, primary, in: rect, step: step, scale: floor, down: false, ink: Ink.strong, line: true)
                }
                if let secondary {
                    series(
                        context, secondary, in: rect, step: step, scale: floor, down: false, ink: Ink.soft, line: false)
                }
            }
        }
        .frame(height: 42)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private func series(
        _ context: GraphicsContext, _ h: History, in rect: CGRect, step: CGFloat, scale: Double, down: Bool,
        ink: Color, line: Bool
    ) {
        guard h.count > 1 else { return }
        let base = down ? rect.minY : rect.maxY
        let start = rect.maxX - CGFloat(h.count - 1) * step
        var edge = Path()
        for i in 0..<h.count {
            let y = rect.height * CGFloat(min(max(h[i] / scale, 0), 1))
            let point = CGPoint(x: start + CGFloat(i) * step, y: down ? base + y : base - y)
            if i == 0 { edge.move(to: point) } else { edge.addLine(to: point) }
        }
        var area = edge
        area.addLine(to: CGPoint(x: rect.maxX, y: base))
        area.addLine(to: CGPoint(x: start, y: base))
        area.closeSubpath()

        guard line else {
            context.fill(area, with: .color(ink))
            return
        }
        let far = down ? rect.maxY : rect.minY
        context.fill(
            area,
            with: .linearGradient(
                Gradient(colors: [ink.opacity(0.45), ink.opacity(0.06)]),
                startPoint: CGPoint(x: 0, y: far), endPoint: CGPoint(x: 0, y: base)))
        context.stroke(edge, with: .color(ink), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
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
        .background(.quaternary.opacity(0.7))
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
    let width: CGFloat

    private let gap: CGFloat = 10
    private let spacing: CGFloat = 2

    var body: some View {
        let clusters = topology.clusters
        if clusters.isEmpty || clusters.map(\.cores.count).reduce(0, +) != cores.count {
            CoreBars(cores: cores)
        } else {
            let gaps = gap * CGFloat(clusters.count - 1) + spacing * CGFloat(cores.count - clusters.count)
            let bar = (width - gaps) / CGFloat(cores.count)
            HStack(alignment: .top, spacing: gap) {
                ForEach(clusters, id: \.kind) { cluster in
                    let load = cluster.cores.map { cores[$0] }
                    VStack(alignment: .leading, spacing: 4) {
                        CoreBars(cores: load)
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

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(cores.indices, id: \.self) { i in
                ZStack(alignment: .bottom) {
                    Rectangle().fill(.quaternary.opacity(0.7))
                    Rectangle().fill(Ink.strong)
                        .frame(height: 16 * CGFloat(min(max(cores[i], 0), 1)))
                }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}
