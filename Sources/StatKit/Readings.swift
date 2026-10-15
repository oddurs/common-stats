import Foundation

public struct CPUReading: Sendable, Equatable {
    /// Fractions of all logical cores' time since the previous sample, 0...1.
    public var user: Double
    public var system: Double
    public var total: Double { user + system }
    /// Per-core busy fraction, in kernel order.
    public var cores: [Double]
    public var loadAverage: (Double, Double, Double)

    public init(user: Double, system: Double, cores: [Double], loadAverage: (Double, Double, Double)) {
        self.user = user
        self.system = system
        self.cores = cores
        self.loadAverage = loadAverage
    }

    public static func == (a: CPUReading, b: CPUReading) -> Bool {
        a.user == b.user && a.system == b.system && a.cores == b.cores
            && a.loadAverage == b.loadAverage
    }
}

/// Memory in bytes, split the way Activity Monitor splits it.
public struct MemoryReading: Sendable, Equatable {
    public enum Pressure: Sendable { case normal, warning, critical }

    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    /// File-backed pages the system can drop at will.
    public var cached: UInt64
    public var swapUsed: UInt64
    public var pressure: Pressure

    public var used: UInt64 { app + wired + compressed }
    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

/// A pair of byte rates: network down/up or disk read/write.
public struct RateReading: Sendable, Equatable {
    public var inbound: Double
    public var outbound: Double
    public var source: String?

    public init(inbound: Double, outbound: Double, source: String? = nil) {
        self.inbound = inbound
        self.outbound = outbound
        self.source = source
    }
}

public struct StorageReading: Sendable, Equatable {
    public var name: String
    public var total: UInt64
    /// Space available for important usage, the figure Finder shows.
    public var available: UInt64
    public var usedFraction: Double {
        total == 0 ? 0 : 1 - Double(available) / Double(total)
    }
}

public struct BatteryReading: Sendable, Equatable {
    public enum State: Sendable { case charging, charged, discharging, onACNotCharging }

    public var level: Double
    public var state: State
    /// Minutes to empty or full; nil while the system is still estimating.
    public var minutesRemaining: Int?
}

/// One pass over every sampler.
public struct Snapshot: Sendable {
    public var cpu: CPUReading?
    public var gpu: Double?
    public var memory: MemoryReading?
    public var network: RateReading?
    public var disk: RateReading?
    public var storage: StorageReading?
    public var battery: BatteryReading?

    public init() {}
}

/// Wall-clock boot time, so uptime includes time spent asleep like `uptime(1)`.
public let systemBootDate: Date = {
    var boot = timeval()
    var size = MemoryLayout<timeval>.size
    guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return .distantPast }
    return Date(timeIntervalSince1970: Double(boot.tv_sec) + Double(boot.tv_usec) / 1e6)
}()
