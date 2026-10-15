import Foundation
import Testing

@testable import StatKit

/// Cross-checks the samplers against the system's own command-line tools.
/// Both read live counters, so comparisons allow for activity between reads.
struct AccuracyTests {
    func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test func networkCountersMatchNetstat() throws {
        let lo = "lo0"  // always present, so the test runs offline and in CI
        let netstat = try run("/usr/sbin/netstat", ["-I", lo, "-b", "-n"])
        // The Address column can be blank, so count from the right: ... Ibytes Opkts Oerrs Obytes Coll
        let row = try #require(netstat.split(separator: "\n").first { $0.hasPrefix(lo) && $0.contains("<Link") })
        let cols = row.split(separator: " ", omittingEmptySubsequences: true)
        let ibytes = try #require(UInt64(cols[cols.count - 5]))
        let (sampled, _) = try #require(NetworkSampler.counters(for: lo))
        // The kernel publishes interface statistics in batches, so two readers
        // a moment apart can see snapshots that differ in either direction
        // (CI saw ours 337 bytes behind netstat's). Agreement, not ordering.
        let difference = sampled > ibytes ? sampled - ibytes : ibytes - sampled
        #expect(difference < 50_000_000, "sampled \(sampled), netstat \(ibytes)")
    }

    @Test func memoryMatchesVMStat() throws {
        let reading = try #require(MemorySampler().sample())
        let vmstat = try run("/usr/bin/vm_stat", [])
        let pageSize = try #require(
            vmstat.firstMatch(of: /page size of (\d+) bytes/).flatMap { UInt64($0.1) })
        func pages(_ label: String) throws -> UInt64 {
            let line = try #require(vmstat.split(separator: "\n").first { $0.hasPrefix(label + ":") })
            return try #require(UInt64(line.split(separator: " ").last!.trimmingCharacters(in: .punctuationCharacters)))
                * pageSize
        }
        let wired = try pages("Pages wired down")
        let compressed = try pages("Pages occupied by compressor")
        let app = try pages("Anonymous pages") - pages("Pages purgeable")
        let total = Double(reading.total)
        #expect(abs(Double(reading.wired) - Double(wired)) / total < 0.02)
        #expect(abs(Double(reading.compressed) - Double(compressed)) / total < 0.02)
        #expect(abs(Double(reading.app) - Double(app)) / total < 0.02)
        #expect(reading.used <= reading.total)
    }

    @Test func totalMemoryMatchesHardware() throws {
        let reading = try #require(MemorySampler().sample())
        #expect(reading.total == ProcessInfo.processInfo.physicalMemory)
    }

    @Test func cpuReadingIsAFraction() throws {
        let sampler = CPUSampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 0.2)
        let reading = try #require(sampler.sample())
        #expect((0...1).contains(reading.total))
        #expect(reading.cores.count == ProcessInfo.processInfo.processorCount)
        #expect(reading.cores.allSatisfy { (0...1).contains($0) })
    }

    @Test func storageMatchesFinderFigures() throws {
        let reading = try #require(StorageSampler().sample())
        let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey])
        #expect(Int(reading.total) == values.volumeTotalCapacity)
        #expect(reading.available <= reading.total)
    }
}
