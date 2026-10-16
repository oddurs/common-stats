import AppKit

/// The colour of graphs, gauges, and legends. Every choice is a system
/// colour, so each adapts to light, dark, and Increase Contrast.
public enum Palette: String, Codable, CaseIterable, Sendable {
    /// Follows the accent colour chosen in System Settings.
    case accent
    /// Each metric in its own colour, matching its Settings icon.
    case metric
    case blue, purple, pink, red, orange, yellow, green, graphite

    public var name: String {
        switch self {
        case .accent: "Accent Color"
        case .metric: "Per Metric"
        default: rawValue.capitalized
        }
    }

    public func color(for metric: Metric) -> NSColor {
        switch self {
        case .accent: .controlAccentColor
        case .metric: metric.tint
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .graphite: .systemGray
        }
    }
}

extension Metric {
    /// The metric's own colour: its Settings icon and its marks under `Palette.metric`.
    public var tint: NSColor {
        switch self {
        case .cpu: .systemBlue
        case .gpu: .systemPurple
        case .memory: .systemPink
        case .network: .systemTeal
        case .disk: .systemOrange
        case .storage: .systemGray
        case .battery: .systemGreen
        }
    }
}
