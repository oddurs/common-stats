import Dispatch
import Foundation

/// Samples every metric on a private serial queue and hands snapshots to the
/// main actor. All sampler state is confined to `queue`.
public final class Monitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "statbar.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let handler: @MainActor (Snapshot) -> Void

    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let network = NetworkSampler()
    private let disk = DiskSampler()
    private let gpu = GPUSampler()
    private let battery = BatterySampler()
    private let storage = StorageSampler()

    // Battery and free space change slowly and cost IPC; refresh them less often.
    private var slowAt: UInt64 = 0
    private var lastBattery: BatteryReading?
    private var lastStorage: StorageReading?

    public init(handler: @escaping @MainActor (Snapshot) -> Void) {
        self.handler = handler
    }

    /// (Re)starts sampling. The first snapshot arrives after one interval,
    /// once rates and CPU deltas have a baseline.
    public func start(interval: TimeInterval) {
        queue.async { [self] in
            timer?.cancel()
            _ = sample()  // establish baselines
            let t = DispatchSource.makeTimerSource(queue: queue)
            let nanos = Int(interval * 1e9)
            // Leeway lets the kernel coalesce our wakeups with others.
            t.schedule(
                deadline: .now() + .nanoseconds(nanos), repeating: .nanoseconds(nanos),
                leeway: .nanoseconds(nanos / 10))
            t.setEventHandler { [weak self] in
                guard let self else { return }
                let snapshot = sample()
                let handler = handler
                DispatchQueue.main.async { MainActor.assumeIsolated { handler(snapshot) } }
            }
            timer = t
            t.resume()
        }
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    private func sample() -> Snapshot {
        let now = monotonicNanoseconds()
        if slowAt == 0 || now &- slowAt > 5_000_000_000 {
            lastBattery = battery.sample()
            lastStorage = storage.sample()
            slowAt = now
        }
        var s = Snapshot()
        s.cpu = cpu.sample()
        s.memory = memory.sample()
        s.network = network.sample(now: now)
        s.disk = disk.sample(now: now)
        s.gpu = gpu.sample(now: now)
        s.battery = lastBattery
        s.storage = lastStorage
        return s
    }

    /// Samples synchronously, for tools and tests that run without a main loop.
    public func sampleNow() -> Snapshot { queue.sync { sample() } }
}
