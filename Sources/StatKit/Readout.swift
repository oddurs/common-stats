/// The latest snapshot plus the history each graph draws from. A value type,
/// so the renderer can draw a consistent copy while sampling continues.
public struct Readout: Sendable {
    public static let capacity = 180

    public private(set) var latest = Snapshot()
    /// Fractions for CPU (total), GPU and memory; inbound bytes/s for rate pairs.
    public private(set) var primary: [Metric: History] = [:]
    /// CPU system time, or outbound bytes/s for rate pairs.
    public private(set) var secondary: [Metric: History] = [:]

    public init() {}

    public mutating func ingest(_ s: Snapshot) {
        latest = s
        if let cpu = s.cpu { record(.cpu, cpu.total, cpu.system) }
        if let gpu = s.gpu { record(.gpu, gpu) }
        if let memory = s.memory { record(.memory, memory.usedFraction) }
        if let n = s.network { record(.network, n.inbound, n.outbound) }
        if let d = s.disk { record(.disk, d.inbound, d.outbound) }
    }

    private mutating func record(_ metric: Metric, _ a: Double, _ b: Double? = nil) {
        primary[metric, default: History(capacity: Self.capacity)].append(a)
        if let b { secondary[metric, default: History(capacity: Self.capacity)].append(b) }
    }

    /// The single fraction a gauge shows, or the primary graph value.
    public func fraction(_ metric: Metric) -> Double? {
        switch metric {
        case .cpu: latest.cpu?.total
        case .gpu: latest.gpu
        case .memory: latest.memory?.usedFraction
        case .storage: latest.storage?.usedFraction
        case .battery: latest.battery?.level
        case .network, .disk: nil
        }
    }

    public func rates(_ metric: Metric) -> RateReading? {
        switch metric {
        case .network: latest.network
        case .disk: latest.disk
        default: nil
        }
    }

    /// `fraction` averaged over the newest `window` samples. Metrics without
    /// a history (storage, battery) are always current.
    public func fraction(_ metric: Metric, window: Int) -> Double? {
        guard window > 1, metric == .cpu || metric == .gpu || metric == .memory,
            let mean = primary[metric]?.mean(last: window)
        else { return fraction(metric) }
        return mean
    }

    /// `rates` averaged over the newest `window` samples.
    public func rates(_ metric: Metric, window: Int) -> RateReading? {
        guard window > 1, metric.isRatePair, let inbound = primary[metric]?.mean(last: window),
            let outbound = secondary[metric]?.mean(last: window)
        else { return rates(metric) }
        return RateReading(inbound: inbound, outbound: outbound, source: rates(metric)?.source)
    }

    /// `valueText` from values averaged over the newest `window` samples.
    public func valueText(_ metric: Metric, window: Int) -> String {
        guard window > 1, metric != .storage else { return valueText(metric) }
        return fraction(metric, window: window).map(Format.percent) ?? Format.missing
    }

    /// Menu bar text for a single-value metric.
    public func valueText(_ metric: Metric) -> String {
        switch metric {
        case .storage: latest.storage.map { Format.bytes(Double($0.available)) } ?? Format.missing
        default: fraction(metric).map(Format.percent) ?? Format.missing
        }
    }
}

extension Format {
    public static let missing = "–"
}
