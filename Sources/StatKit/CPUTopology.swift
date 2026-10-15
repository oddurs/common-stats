import Foundation
import IOKit

/// Which logical cores are efficiency cores and which are performance cores.
///
/// Apple Silicon's device tree tags every core with a `cluster-type` ("E" or
/// "P") under its `logical-cpu-id`, which is the index `host_processor_info`
/// uses. Verified by confining busy loops to efficiency cores with
/// `taskpolicy -b` and watching exactly those indices saturate.
public struct CPUTopology: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case efficiency = "Efficiency"
        case performance = "Performance"
    }

    public struct Cluster: Sendable, Equatable {
        public let kind: Kind
        /// Logical core indices, ascending.
        public let cores: [Int]
    }

    /// Clusters in core order, one per kind; empty when unknown (Intel, or a
    /// device tree we can't read), in which case cores show ungrouped.
    public let clusters: [Cluster]

    public static let current = CPUTopology(kinds: readKinds(), coreCount: ProcessInfo.processInfo.processorCount)

    /// Groups cores by kind. Anything inconsistent (a missing core, a count
    /// that doesn't match the kernel's) yields no grouping rather than a wrong one.
    init(kinds: [Int: Kind], coreCount: Int) {
        guard kinds.count == coreCount, Set(kinds.keys) == Set(0..<coreCount), Set(kinds.values).count > 1 else {
            clusters = []
            return
        }
        clusters = [Kind.efficiency, .performance].compactMap { kind in
            let cores = kinds.filter { $0.value == kind }.keys.sorted()
            return cores.isEmpty ? nil : Cluster(kind: kind, cores: cores)
        }.sorted { $0.cores[0] < $1.cores[0] }
    }

    private static func readKinds() -> [Int: Kind] {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return [:] }
        defer { IOObjectRelease(cpus) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }

        var kinds: [Int: Kind] = [:]
        while case let cpu = IOIteratorNext(iterator), cpu != 0 {
            defer { IOObjectRelease(cpu) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(cpu, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let id = (property("logical-cpu-id") as? NSNumber)?.intValue,
                let type = property("cluster-type") as? Data,
                let letter = String(bytes: type.prefix { $0 != 0 }, encoding: .ascii)
            else { continue }
            switch letter {
            case "E": kinds[id] = .efficiency
            case "P": kinds[id] = .performance
            default: continue
            }
        }
        return kinds
    }
}
