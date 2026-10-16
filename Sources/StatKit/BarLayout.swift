import Foundation

public enum Metric: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, gpu, memory, network, disk, storage, battery

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .network: "Network"
        case .disk: "Disk Activity"
        case .storage: "Storage"
        case .battery: "Battery"
        }
    }

    /// The tiny caption drawn above a value in the menu bar.
    public var caption: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "MEM"
        case .network: "NET"
        case .disk: "DISK"
        case .storage: "FREE"
        case .battery: "BAT"
        }
    }

    public var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "arrow.up.arrow.down"
        case .storage: "internaldrive"
        case .battery: "battery.75percent"
        }
    }

    /// The style an item gets when it's added to the menu bar.
    public var defaultStyle: Style {
        switch self {
        case .cpu, .gpu: .graphValue
        case .memory: .gaugeValue
        case .network, .disk, .storage, .battery: .value
        }
    }

    /// Network and disk show two rates (in and out) rather than one fraction.
    public var isRatePair: Bool { self == .network || self == .disk }

    /// The smallest full-scale value for a rate graph. Graphs auto-scale
    /// above this; below it, background chatter stays visibly small instead
    /// of filling the graph.
    public var rateFloor: Double { self == .disk ? 1_000_000 : 64_000 }

    public var styles: [Style] {
        switch self {
        case .network, .disk: [.hidden, .value, .graph, .graphValue]
        // A history graph of quantities that move over hours is noise.
        case .storage, .battery: [.hidden, .value, .gauge, .gaugeValue]
        case .cpu, .gpu, .memory: Style.allCases
        }
    }
}

public enum Style: String, Codable, CaseIterable, Sendable {
    case hidden, value, graph, graphValue, gauge, gaugeValue

    public var name: String {
        switch self {
        case .hidden: "Don’t Show"
        case .value: "Value"
        case .graph: "Graph"
        case .graphValue: "Graph and Value"
        case .gauge: "Gauge"
        case .gaugeValue: "Gauge and Value"
        }
    }

    public var showsValue: Bool { self == .value || self == .graphValue || self == .gaugeValue }
    public var showsGraph: Bool { self == .graph || self == .graphValue }
    public var showsGauge: Bool { self == .gauge || self == .gaugeValue }
}

/// A trailing time average for the menu bar. The menu always shows exact readings.
public enum Smoothing: String, Codable, CaseIterable, Sendable {
    case off, short, medium, long

    public var seconds: TimeInterval? {
        switch self {
        case .off: nil
        case .short: 3
        case .medium: 10
        case .long: 30
        }
    }

    public var name: String { seconds.map { "\(Int($0)) seconds" } ?? "Off" }

    /// How many samples the average spans at a given update interval; 1 means raw.
    public func window(interval: TimeInterval) -> Int {
        guard let seconds, interval > 0 else { return 1 }
        return Swift.max(1, Int((seconds / interval).rounded()))
    }
}

public struct BarItem: Codable, Hashable, Identifiable, Sendable {
    public var metric: Metric
    public var style: Style
    public var id: Metric { metric }

    public init(_ metric: Metric, _ style: Style) {
        self.metric = metric
        self.style = style
    }
}

public enum Density: String, Codable, CaseIterable, Sendable {
    case compact, regular, spacious

    public var name: String { rawValue.capitalized }

    public var itemGap: CGFloat {
        switch self {
        case .compact: 7
        case .regular: 11
        case .spacious: 16
        }
    }

    var graphWidth: CGFloat {
        switch self {
        case .compact: 22
        case .regular: 30
        case .spacious: 40
        }
    }
}

/// Everything the user can configure. Every metric appears exactly once in
/// `items`; order is menu bar order, left to right.
public struct BarLayout: Codable, Equatable, Sendable {
    public var items: [BarItem]
    public var showCaptions: Bool
    public var density: Density
    public var interval: TimeInterval
    public var palette: Palette
    /// Colour graphs and gauges in the menu bar too. Off, the bar is a
    /// monochrome template image like the system's own menu bar icons.
    public var colorInMenuBar: Bool
    public var smoothing: Smoothing

    public static let intervals: [TimeInterval] = [0.5, 1, 2, 3, 5]

    public static let standard = BarLayout(
        items: [
            BarItem(.cpu, .graphValue), BarItem(.memory, .gaugeValue), BarItem(.network, .value),
            BarItem(.gpu, .hidden), BarItem(.disk, .hidden), BarItem(.storage, .hidden),
            BarItem(.battery, .hidden),
        ],
        showCaptions: true, density: .regular, interval: 1, palette: .accent, colorInMenuBar: false,
        smoothing: .off)

    public var visible: [BarItem] { items.filter { $0.style != .hidden } }

    public init(
        items: [BarItem], showCaptions: Bool, density: Density, interval: TimeInterval,
        palette: Palette = .accent, colorInMenuBar: Bool = false, smoothing: Smoothing = .off
    ) {
        self.items = items
        self.showCaptions = showCaptions
        self.density = density
        self.interval = interval
        self.palette = palette
        self.colorInMenuBar = colorInMenuBar
        self.smoothing = smoothing
        normalize()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BarLayout.standard
        items = try c.decodeIfPresent([BarItem].self, forKey: .items) ?? d.items
        showCaptions = try c.decodeIfPresent(Bool.self, forKey: .showCaptions) ?? d.showCaptions
        density = try c.decodeIfPresent(Density.self, forKey: .density) ?? d.density
        interval = try c.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? d.interval
        // An unknown palette from a newer version falls back rather than discarding the whole layout.
        palette = (try? c.decodeIfPresent(Palette.self, forKey: .palette)) ?? d.palette
        colorInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .colorInMenuBar) ?? d.colorInMenuBar
        smoothing = (try? c.decodeIfPresent(Smoothing.self, forKey: .smoothing)) ?? d.smoothing
        normalize()
    }

    /// Puts `metric` at `index` among the visible items, showing it in its
    /// default style if it was hidden. Hidden items keep their relative order
    /// after it, so the stored order stays stable.
    public mutating func place(_ metric: Metric, atVisibleIndex index: Int) {
        guard let from = items.firstIndex(where: { $0.metric == metric }) else { return }
        var item = items.remove(at: from)
        if item.style == .hidden { item.style = metric.defaultStyle }
        let visibleIndices = items.indices.filter { items[$0].style != .hidden }
        let clamped = min(max(index, 0), visibleIndices.count)
        let at = clamped < visibleIndices.count ? visibleIndices[clamped] : (visibleIndices.last.map { $0 + 1 } ?? 0)
        items.insert(item, at: at)
    }

    /// Takes `metric` out of the menu bar.
    public mutating func remove(_ metric: Metric) {
        guard let i = items.firstIndex(where: { $0.metric == metric }) else { return }
        items[i].style = .hidden
    }

    /// Moves `metric` to where `target` is: after it when moving down,
    /// before it when moving up, which is where a drop on that row lands.
    public mutating func move(_ metric: Metric, onto target: Metric) {
        guard metric != target, let from = items.firstIndex(where: { $0.metric == metric }),
            let to = items.firstIndex(where: { $0.metric == target })
        else { return }
        items.insert(items.remove(at: from), at: to)
    }

    /// Repairs a stored layout from an older or newer version: drops
    /// duplicates, adds metrics it lacks, and clamps invalid choices.
    private mutating func normalize() {
        var seen = Set<Metric>()
        items = items.filter { seen.insert($0.metric).inserted }
        for m in Metric.allCases where !seen.contains(m) { items.append(BarItem(m, .hidden)) }
        for i in items.indices where !items[i].metric.styles.contains(items[i].style) {
            items[i].style = .value
        }
        if !Self.intervals.contains(interval) { interval = 1 }
    }
}
