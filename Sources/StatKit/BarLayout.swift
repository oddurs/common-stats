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

    var itemGap: CGFloat {
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

    public static let intervals: [TimeInterval] = [0.5, 1, 2, 3, 5]

    public static let standard = BarLayout(
        items: [
            BarItem(.cpu, .graphValue), BarItem(.memory, .gaugeValue), BarItem(.network, .value),
            BarItem(.gpu, .hidden), BarItem(.disk, .hidden), BarItem(.storage, .hidden),
            BarItem(.battery, .hidden),
        ],
        showCaptions: true, density: .regular, interval: 1)

    public var visible: [BarItem] { items.filter { $0.style != .hidden } }

    public init(items: [BarItem], showCaptions: Bool, density: Density, interval: TimeInterval) {
        self.items = items
        self.showCaptions = showCaptions
        self.density = density
        self.interval = interval
        normalize()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BarLayout.standard
        items = try c.decodeIfPresent([BarItem].self, forKey: .items) ?? d.items
        showCaptions = try c.decodeIfPresent(Bool.self, forKey: .showCaptions) ?? d.showCaptions
        density = try c.decodeIfPresent(Density.self, forKey: .density) ?? d.density
        interval = try c.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? d.interval
        normalize()
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
