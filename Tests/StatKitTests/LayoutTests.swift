import AppKit
import Foundation
import Testing

@testable import StatKit

struct BarLayoutTests {
    @Test func roundTripsThroughJSON() throws {
        var layout = BarLayout.standard
        layout.items.swapAt(0, 2)
        layout.density = .compact
        let decoded = try JSONDecoder().decode(BarLayout.self, from: JSONEncoder().encode(layout))
        #expect(decoded == layout)
    }

    @Test func repairsLayoutsFromOtherVersions() throws {
        let json = """
            {"items":[{"metric":"memory","style":"graph"},{"metric":"memory","style":"value"},
            {"metric":"battery","style":"graph"}],"interval":7,"futureSetting":true}
            """
        let layout = try JSONDecoder().decode(BarLayout.self, from: Data(json.utf8))
        #expect(
            layout.items.map(\.metric).sorted { $0.rawValue < $1.rawValue }
                == Metric.allCases.sorted { $0.rawValue < $1.rawValue })
        #expect(layout.items[0] == BarItem(.memory, .graph))
        // Battery has no graph style; an invalid choice falls back to a value.
        #expect(layout.items[1] == BarItem(.battery, .value))
        #expect(layout.interval == 1)
        #expect(layout.showCaptions == BarLayout.standard.showCaptions)
    }

    @Test func everyMetricOffersHiddenAndValue() {
        for m in Metric.allCases {
            #expect(m.styles.contains(.hidden))
            #expect(m.styles.contains(.value))
        }
    }
}

struct BarRendererTests {
    func readout(_ scale: Double) -> Readout {
        var r = Readout()
        var s = Snapshot()
        s.cpu = CPUReading(user: 0.6 * scale, system: 0.4 * scale, cores: [scale], loadAverage: (1, 1, 1))
        s.gpu = scale
        s.memory = MemoryReading(
            total: 16_000_000_000, app: UInt64(8e9 * scale), wired: 0, compressed: 0, cached: 0, swapUsed: 0,
            pressure: .normal)
        s.network = RateReading(inbound: 999_999_999 * scale, outbound: 0)
        s.disk = RateReading(inbound: 1, outbound: 1e12 * scale)
        s.storage = StorageReading(name: "Disk", total: 2_000_000_000_000, available: UInt64(1.999e12 * scale))
        s.battery = BatteryReading(level: scale, state: .charging, minutesRemaining: nil)
        r.ingest(s)
        return r
    }

    var everything: BarLayout {
        BarLayout(
            items: Metric.allCases.map { BarItem($0, $0.styles.last!) }, showCaptions: true,
            density: .regular, interval: 1)
    }

    @Test func widthDoesNotDependOnValues() {
        for captions in [true, false] {
            var layout = everything
            layout.showCaptions = captions
            let renderer = BarRenderer(layout: layout, height: 22)
            let sizes = [0, 0.5, 1].map { renderer.image(readout($0))!.size }
            #expect(Set(sizes.map(\.width)).count == 1)
            #expect(sizes[0] == renderer.size)
        }
    }

    @Test func valuesFitTheirCells() {
        // The widest strings each metric can produce must fit the measured cell.
        let renderer = BarRenderer(layout: everything, height: 22)
        for metric in Metric.allCases where !metric.isRatePair {
            let font = BarRenderer.stackedValueFont
            for scale in [0, 0.01, 0.5, 1.0] {
                let text = readout(scale).valueText(metric)
                #expect(BarRenderer.widest([text], font) <= renderer.valueWidth(metric), "\(metric) \(text)")
            }
        }
    }

    @Test func hiddenItemsTakeNoSpace() {
        let layout = BarLayout(
            items: [BarItem(.cpu, .value), BarItem(.gpu, .hidden)], showCaptions: false, density: .regular,
            interval: 1)
        let cells = BarRenderer(layout: layout, height: 22).cells
        #expect(cells.map(\.item.metric) == [.cpu])
        #expect(cells[0].x == 0)
    }

    @Test func nothingVisibleMeansNoImage() {
        let layout = BarLayout(
            items: Metric.allCases.map { BarItem($0, .hidden) }, showCaptions: true, density: .regular, interval: 1)
        #expect(BarRenderer(layout: layout, height: 22).image(Readout()) == nil)
    }

    @Test func itemsAreSeparatedByTheDensityGap() {
        let layout = BarLayout(
            items: [BarItem(.cpu, .gauge), BarItem(.gpu, .gauge)], showCaptions: false, density: .spacious,
            interval: 1)
        let cells = BarRenderer(layout: layout, height: 22).cells
        #expect(cells[1].x - (cells[0].x + cells[0].width) == Density.spacious.itemGap)
    }

    @Test func accessibilityTextNamesEveryVisibleMetric() {
        let text = BarRenderer(layout: .standard, height: 22).accessibilityText(readout(0.5))
        #expect(text.contains("CPU 50%"))
        #expect(text.contains("Memory 25%"))
        #expect(text.contains("Network down 500 MB/s, up 0 B/s"))
    }
}

struct ValueTypographyTests {
    func alpha(_ s: NSAttributedString, at i: Int) -> CGFloat {
        (s.attribute(.foregroundColor, at: i, effectiveRange: nil) as! NSColor).alphaComponent
    }

    @Test(arguments: [("4.0 MB/s", 3), ("100%", 3), ("65 GB", 2), ("7 B/s", 1)])
    func unitIsDimmedAndNumberIsNot(text: String, digits: Int) {
        let s = BarRenderer.number(text, BarRenderer.valueFont)
        #expect(alpha(s, at: 0) == 1)
        #expect(alpha(s, at: digits - 1) == 1)
        #expect(alpha(s, at: digits) < 1)
        #expect(alpha(s, at: text.count - 1) < 1)
    }

    @Test func commaDecimalsCountAsPartOfTheNumber() {
        let s = BarRenderer.number("4,0 MB/s", BarRenderer.valueFont)
        #expect(alpha(s, at: 2) == 1)
        #expect(alpha(s, at: 3) < 1)
    }

    @Test func placeholderStaysFullInk() {
        let s = BarRenderer.number(Format.missing, BarRenderer.valueFont)
        #expect(alpha(s, at: 0) == 1)
    }
}
