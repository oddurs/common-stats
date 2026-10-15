import Foundation
import IOKit

/// Holds IORegistry entries for one class so each sample reads properties
/// instead of re-matching services. Rematches every `refresh` nanoseconds to
/// pick up disks and GPUs that come and go.
final class RegistryEntries {
    private let className: String
    private var entries: [io_registry_entry_t] = []
    private var matchedAt: UInt64 = 0
    private let refresh: UInt64 = 10_000_000_000

    init(className: String) { self.className = className }

    deinit { entries.forEach { IOObjectRelease($0) } }

    /// The property dictionary of each entry, keyed by its stable registry ID.
    func properties(_ key: String, now: UInt64) -> [UInt64: [String: Any]] {
        if entries.isEmpty || now &- matchedAt > refresh {
            rematch()
            matchedAt = now
        }
        var result: [UInt64: [String: Any]] = [:]
        for entry in entries {
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS,
                let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any]
            else { continue }
            result[id] = value
        }
        return result
    }

    private func rematch() {
        entries.forEach { IOObjectRelease($0) }
        entries.removeAll()
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator)
                == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            entries.append(entry)
        }
    }
}

final class DiskSampler {
    private let drivers = RegistryEntries(className: "IOBlockStorageDriver")
    private var meter = RateMeter<UInt64>()

    func sample(now: UInt64) -> RateReading? {
        let counters = drivers.properties("Statistics", now: now).mapValues { s in
            (
                inbound: (s["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0,
                outbound: (s["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            )
        }
        guard let (r, w) = meter.update(counters, nanoseconds: now) else { return nil }
        return RateReading(inbound: r, outbound: w)
    }
}

final class GPUSampler {
    private let accelerators = RegistryEntries(className: "IOAccelerator")

    /// Busiest GPU's utilisation, 0...1. The driver reports a smoothed percentage.
    func sample(now: UInt64) -> Double? {
        let values = accelerators.properties("PerformanceStatistics", now: now).values
            .compactMap { ($0["Device Utilization %"] as? NSNumber)?.doubleValue }
        return values.max().map { min(max($0 / 100, 0), 1) }
    }
}
