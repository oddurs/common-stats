import AppKit
import Darwin
import Testing

@testable import StatKit

/// Regression gates, not benchmarks of record. Budgets sit roughly 10x above
/// what an M-series Mac measures, so they catch an accidental O(n) syscall
/// loop or a per-tick allocation storm without flaking on a busy CI runner.
@Suite(.serialized)
struct PerformanceTests {
    /// The median time of one call. A mean over a loop absorbs every time the
    /// scheduler pre-empts the test, which on a loaded machine (load average
    /// 35 on 14 cores was seen) inflated a 115 µs sample past the budget. The
    /// median ignores those stalls but still moves if every call gets slower.
    func medianMicroseconds(_ iterations: Int, _ body: () -> Void) -> Double {
        body()  // warm caches and lazy registry matching
        let times = (0..<iterations).map { _ in
            let start = monotonicNanoseconds()
            body()
            return Double(monotonicNanoseconds() - start) / 1000
        }.sorted()
        return times[times.count / 2]
    }

    func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    @Test func samplingEveryMetricIsCheap() {
        let monitor = Monitor { _ in }
        let us = medianMicroseconds(200) { _ = monitor.sampleNow() }
        print("sample all metrics: \(String(format: "%.0f", us)) µs")
        #expect(us < 3000)
    }

    @Test func drawingTheBarIsCheap() throws {
        let layout = BarLayout(
            items: Metric.allCases.map { BarItem($0, $0.isRatePair ? .graphValue : $0.styles.last!) },
            showCaptions: true, density: .spacious, interval: 1)
        let renderer = BarRenderer(layout: layout, height: 24)
        let monitor = Monitor { _ in }
        var readout = Readout()
        for _ in 0..<Readout.capacity { readout.ingest(monitor.sampleNow()) }
        let image = try #require(renderer.image(readout))
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2), pixelsHigh: 48, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                bitsPerPixel: 0))
        rep.size = image.size
        let context = NSGraphicsContext(bitmapImageRep: rep)
        let us = medianMicroseconds(200) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            renderer.image(readout)?.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        print("draw full bar at 2x: \(String(format: "%.0f", us)) µs")
        #expect(us < 3000)
    }

    @Test func longRunsDoNotLeak() {
        // An hour of 1 Hz sampling, compressed. A leaked IOKit object or CF
        // dictionary per tick shows up as megabytes here.
        let monitor = Monitor { _ in }
        var readout = Readout()
        for _ in 0..<500 { readout.ingest(monitor.sampleNow()) }
        let before = footprint()
        for _ in 0..<3600 { readout.ingest(monitor.sampleNow()) }
        let grown = Int64(footprint()) - Int64(before)
        print("footprint growth over 3600 samples: \(grown / 1024) KB")
        #expect(grown < 2_000_000)
    }
}
