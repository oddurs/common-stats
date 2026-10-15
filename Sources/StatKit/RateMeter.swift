import Darwin

/// Turns cumulative byte counters into per-second rates. Counters are keyed
/// (by disk, by interface) so a source appearing or vanishing changes nothing:
/// only sources present in both samples contribute, each by its own delta.
struct RateMeter<Key: Hashable> {
    typealias Counters = (inbound: UInt64, outbound: UInt64)

    private var last: [Key: Counters] = [:]
    private var lastTime: UInt64?
    /// Gaps longer than this (sleep, a stalled timer) restart the baseline
    /// rather than averaging a burst over time nobody saw.
    var maxGap: Double = 10

    /// Nil on the first sample, after a gap, or when no source was present
    /// in both samples. A counter that went backwards (a reset) contributes nothing.
    mutating func update(_ counters: [Key: Counters], nanoseconds: UInt64) -> (Double, Double)? {
        defer {
            last = counters
            lastTime = nanoseconds
        }
        guard let lastTime, nanoseconds > lastTime else { return nil }
        let seconds = Double(nanoseconds - lastTime) / 1e9
        guard seconds <= maxGap else { return nil }
        var inbound: UInt64 = 0, outbound: UInt64 = 0, matched = false
        for (key, new) in counters {
            guard let old = last[key] else { continue }
            matched = true
            if new.inbound >= old.inbound { inbound &+= new.inbound - old.inbound }
            if new.outbound >= old.outbound { outbound &+= new.outbound - old.outbound }
        }
        return matched ? (Double(inbound) / seconds, Double(outbound) / seconds) : nil
    }
}

/// Monotonic time that keeps counting through sleep.
func monotonicNanoseconds() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }
