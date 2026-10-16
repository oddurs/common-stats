import Foundation
import Testing

@testable import StatKit

struct CPUUsageTests {
    func ticks(_ user: UInt32, _ system: UInt32, _ idle: UInt32) -> CoreTicks {
        CoreTicks(user: user, system: system, idle: idle, nice: 0)
    }

    @Test func splitsUserAndSystemAcrossCores() throws {
        let old = [ticks(0, 0, 0), ticks(0, 0, 0)]
        let new = [ticks(30, 10, 60), ticks(0, 0, 100)]
        let usage = try #require(cpuUsage(from: old, to: new))
        #expect(usage.user == 0.15)
        #expect(usage.system == 0.05)
        #expect(usage.cores == [0.4, 0])
    }

    @Test func survivesCounterWraparound() throws {
        let old = [ticks(UInt32.max - 9, 0, UInt32.max - 9)]
        let new = [ticks(10, 0, 10)]  // 20 ticks of user, 20 of idle, across the wrap
        let usage = try #require(cpuUsage(from: old, to: new))
        #expect(usage.user == 0.5)
    }

    @Test func rejectsChangedCoreCount() {
        #expect(cpuUsage(from: [ticks(0, 0, 0)], to: [ticks(1, 1, 1), ticks(1, 1, 1)]) == nil)
        #expect(cpuUsage(from: [], to: [ticks(1, 1, 1)]) == nil)
    }

    @Test func noElapsedTicksIsIdleNotNaN() throws {
        let usage = try #require(cpuUsage(from: [ticks(5, 5, 5)], to: [ticks(5, 5, 5)]))
        #expect(usage.user == 0 && usage.system == 0 && usage.cores == [0])
    }
}

struct RateMeterTests {
    typealias Meter = RateMeter<String>

    @Test func firstSampleHasNoRate() {
        var meter = Meter()
        #expect(meter.update(["en0": (100, 100)], nanoseconds: 1) == nil)
    }

    @Test func dividesByElapsedTimeNotNominalInterval() throws {
        var meter = Meter()
        _ = meter.update(["en0": (0, 0)], nanoseconds: 1_000_000_000)
        let rates = meter.update(["en0": (3000, 1500)], nanoseconds: 2_500_000_000)
        let (down, up) = try #require(rates)
        #expect(down == 2000)
        #expect(up == 1000)
    }

    @Test func counterResetContributesNothing() throws {
        var meter = Meter()
        _ = meter.update(["en0": (5000, 5000)], nanoseconds: 0)
        let reset = meter.update(["en0": (10, 10)], nanoseconds: 1_000_000_000)
        #expect(try #require(reset) == (0, 0))
        let rates = meter.update(["en0": (1010, 10)], nanoseconds: 2_000_000_000)
        #expect(try #require(rates).0 == 1000)
    }

    @Test func switchingInterfaceRestartsBaseline() {
        var meter = Meter()
        _ = meter.update(["en0": (5000, 5000)], nanoseconds: 0)
        #expect(meter.update(["en7": (9_000_000, 0)], nanoseconds: 1_000_000_000) == nil)
    }

    @Test func diskAppearingMidStreamIsNotABurst() throws {
        // A 2 TB drive plugged in between samples must not read as 2 TB/s.
        var meter = RateMeter<UInt64>()
        _ = meter.update([1: (1000, 0)], nanoseconds: 0)
        let rates = meter.update([1: (3000, 0), 2: (2_000_000_000_000, 0)], nanoseconds: 1_000_000_000)
        #expect(try #require(rates).0 == 2000)
    }

    @Test func diskLeavingMidStreamIsNotANegativeRate() throws {
        var meter = RateMeter<UInt64>()
        _ = meter.update([1: (1000, 0), 2: (9_000_000, 0)], nanoseconds: 0)
        let rates = meter.update([1: (1500, 0)], nanoseconds: 1_000_000_000)
        #expect(try #require(rates).0 == 500)
    }

    @Test func longGapSuchAsSleepIsDiscarded() {
        var meter = Meter()
        _ = meter.update(["en0": (0, 0)], nanoseconds: 0)
        #expect(meter.update(["en0": (1, 1)], nanoseconds: 60_000_000_000) == nil)
    }
}

let en = Locale(identifier: "en_US")

struct FormatTests {
    @Test(arguments: [
        (0.0, "0 B"), (999, "999 B"), (1000, "1.0 KB"), (9_949, "9.9 KB"), (9_960, "10 KB"),
        (999_400, "999 KB"), (999_700, "1.0 MB"), (12_345_678, "12 MB"), (2.5e12, "2.5 TB"), (-5, "0 B"),
    ])
    func bytes(value: Double, expected: String) {
        #expect(Format.bytes(value, locale: en) == expected)
    }

    @Test func decimalsFollowTheRegion() {
        let de = Locale(identifier: "de_DE")
        #expect(Format.rate(4_000_000, locale: de) == "4,0 MB/s")
        #expect(Format.memory(1536 * 1024 * 1024, locale: de) == "1,5 GB")
        #expect(Format.rate(4_000_000, locale: en) == "4.0 MB/s")
    }

    @Test func percentClampsAndRounds() {
        #expect(Format.percent(0.004) == "0%")
        #expect(Format.percent(0.995) == "100%")
        #expect(Format.percent(1.7) == "100%")
        #expect(Format.percent(-1) == "0%")
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteValuesShowADashInsteadOfTrapping(value: Double) {
        #expect(Format.percent(value) == Format.missing)
        #expect(Format.bytes(value) == Format.missing)
        #expect(Format.rate(value) == Format.missing)
        #expect(Format.uptime(value) == Format.missing)
    }

    @Test func durations() {
        #expect(Format.duration(minutes: 72) == "1:12")
        #expect(Format.duration(minutes: 5) == "0:05")
        #expect(Format.uptime(59) == "0m")
        #expect(Format.uptime(3 * 3600 + 120) == "3h 2m")
        #expect(Format.uptime(2 * 86400 + 5 * 3600) == "2d 5h")
    }

    @Test func noStringOutgrowsTheWidthTemplates() {
        // The renderer sizes rate cells from templates; every real output must fit one.
        var value = 1.0
        while value < 1e13 {
            let s = Format.rate(value, locale: en)
            #expect(s.count <= "888 KB/s".count, "\(s)")
            value *= 1.37
        }
    }
}

struct HistoryTests {
    @Test func keepsNewestInOrderOnceFull() {
        var h = History(capacity: 3)
        for v in 1...5 { h.append(Double(v)) }
        #expect(h.count == 3)
        #expect(h.suffix(3) == [3, 4, 5])
        #expect(h.suffix(2) == [4, 5])
        #expect(h.suffix(10) == [3, 4, 5])
        #expect(h.last == 5)
        #expect(h.max(last: 2) == 5)
    }

    @Test func emptyHistory() {
        let h = History(capacity: 4)
        #expect(h.last == nil)
        #expect(h.suffix(2).isEmpty)
        #expect(h.max(last: 4) == 0)
    }
}

struct MemoryFormatTests {
    @Test func reportsRAMInBinaryUnitsLikeApple() {
        #expect(Format.memory(24 * 1024 * 1024 * 1024) == "24 GB")
        #expect(Format.memory(16 * 1024 * 1024 * 1024) == "16 GB")
        #expect(Format.memory(1536 * 1024 * 1024, locale: en) == "1.5 GB")
        // The same quantity in decimal units, which is what the menu wrongly showed.
        #expect(Format.bytes(24 * 1024 * 1024 * 1024) == "26 GB")
    }
}

struct CPUTopologyTests {
    typealias Kind = CPUTopology.Kind

    @Test func groupsCoresByKindInCoreOrder() {
        var kinds: [Int: Kind] = [:]
        for i in 0..<4 { kinds[i] = .efficiency }
        for i in 4..<14 { kinds[i] = .performance }
        let t = CPUTopology(kinds: kinds, coreCount: 14)
        #expect(t.clusters.map(\.kind) == [.efficiency, .performance])
        #expect(t.clusters[0].cores == [0, 1, 2, 3])
        #expect(t.clusters[1].cores == Array(4..<14))
    }

    @Test func incompleteOrMismatchedTopologyIsNotGuessed() {
        // A core missing from the device tree, or a kernel count that disagrees.
        #expect(CPUTopology(kinds: [0: .efficiency, 2: .performance], coreCount: 3).clusters.isEmpty)
        #expect(CPUTopology(kinds: [0: .efficiency, 1: .performance], coreCount: 4).clusters.isEmpty)
        // A single kind (Intel-like) has nothing to group.
        #expect(CPUTopology(kinds: [0: .performance, 1: .performance], coreCount: 2).clusters.isEmpty)
    }

    @Test func currentMachineIsConsistentWithSysctl() throws {
        let t = CPUTopology.current
        let levels: Int32 = sysctlValue("hw.nperflevels") ?? 1
        guard levels > 1 else {
            #expect(t.clusters.isEmpty)
            return
        }
        // perflevel0 is performance, perflevel1 efficiency, per the kernel.
        let p: Int32 = try #require(sysctlValue("hw.perflevel0.logicalcpu"))
        let e: Int32 = try #require(sysctlValue("hw.perflevel1.logicalcpu"))
        let counts = Dictionary(uniqueKeysWithValues: t.clusters.map { ($0.kind, $0.cores.count) })
        #expect(counts[.performance] == Int(p))
        #expect(counts[.efficiency] == Int(e))
    }
}

struct SmoothingTests {
    func history(_ values: [Double], capacity: Int = 10) -> History {
        var h = History(capacity: capacity)
        values.forEach { h.append($0) }
        return h
    }

    @Test func meanOfTheNewestValues() {
        let h = history([1, 2, 3, 4])
        #expect(h.mean(last: 2) == 3.5)
        #expect(h.mean(last: 99) == 2.5)
        #expect(History(capacity: 3).mean(last: 2) == nil)
    }

    @Test func trailingMeansAverageWhatHistoryExists() {
        let h = history([0, 10, 20, 30, 40])
        #expect(h.trailingMeans(last: 5, window: 2) == [0, 5, 15, 25, 35])
        #expect(h.trailingMeans(last: 2, window: 3) == [20, 30])  // reaches back before the output range
        #expect(h.trailingMeans(last: 3, window: 1) == [20, 30, 40])
    }

    @Test func trailingMeansAcrossTheRingBufferSeam() {
        let h = history([5, 5, 0, 10, 20], capacity: 3)  // holds 0, 10, 20
        #expect(h.trailingMeans(last: 3, window: 2) == [0, 5, 15])
    }

    @Test func windowFollowsTheUpdateInterval() {
        #expect(Smoothing.off.window(interval: 1) == 1)
        #expect(Smoothing.medium.window(interval: 1) == 10)
        #expect(Smoothing.medium.window(interval: 2) == 5)
        #expect(Smoothing.short.window(interval: 5) == 1)  // shorter than one sample is raw
    }

    @Test func readoutAveragesOnlyWhenAsked() {
        var r = Readout()
        for v in [0.1, 0.3, 0.5] {
            var s = Snapshot()
            s.gpu = v
            s.network = RateReading(inbound: v * 1000, outbound: v * 100)
            r.ingest(s)
        }
        #expect(r.fraction(.gpu, window: 1) == 0.5)
        #expect(abs((r.fraction(.gpu, window: 3) ?? 0) - 0.3) < 1e-12)
        #expect(r.valueText(.gpu, window: 3) == "30%")
        let rates = r.rates(.network, window: 2)
        #expect(abs((rates?.inbound ?? 0) - 400) < 1e-9)
        #expect(abs((rates?.outbound ?? 0) - 40) < 1e-9)
    }

    @Test func layoutsWithoutSmoothingDecodeAsOff() throws {
        let l = try JSONDecoder().decode(BarLayout.self, from: Data(#"{"smoothing":"forever"}"#.utf8))
        #expect(l.smoothing == .off)
    }

    @Test func barShowsTheAverageWhenSmoothing() {
        var r = Readout()
        for v in [0.2, 0.4] {
            var s = Snapshot()
            s.cpu = CPUReading(user: v, system: 0, cores: [v], loadAverage: (0, 0, 0))
            r.ingest(s)
        }
        var layout = BarLayout.standard
        layout.smoothing = .short
        #expect(BarRenderer(layout: layout, height: 22).accessibilityText(r).contains("CPU 30%"))
        layout.smoothing = .off
        #expect(BarRenderer(layout: layout, height: 22).accessibilityText(r).contains("CPU 40%"))
    }
}
