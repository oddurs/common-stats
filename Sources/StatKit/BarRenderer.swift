import AppKit

/// The menu bar layout engine. Widths depend only on the layout, never on
/// the values, so the status item never jitters as numbers change.
///
/// Everything is drawn in black at varying opacity into a template image;
/// AppKit then tints it like any system menu bar extra (light, dark,
/// inactive display, increased contrast).
public struct BarRenderer {
    public let layout: BarLayout
    public let height: CGFloat
    /// The layout pass, done once: text measurement is the costliest step
    /// and its result only changes with the layout.
    public private(set) var cells: [Cell] = []

    public init(layout: BarLayout, height: CGFloat) {
        self.layout = layout
        self.height = height
        cells = measureCells()
    }

    // MARK: Type and geometry

    enum Ink {
        static let full: CGFloat = 1
        static let secondary: CGFloat = 0.5
        static let track: CGFloat = 0.11
    }

    // NSFont is immutable; Swift just can't see that.
    nonisolated(unsafe) static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    nonisolated(unsafe) static let stackedValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    nonisolated(unsafe) static let pairFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    nonisolated(unsafe) static let captionFont = NSFont.systemFont(ofSize: 7.5, weight: .semibold)

    static let partGap: CGFloat = 3
    static let gaugeWidth: CGFloat = 4
    static let pairGlyphGap: CGFloat = 2

    var chartHeight: CGFloat { min(height - 7, 16) }

    // MARK: Layout pass

    enum Part: Equatable {
        case caption
        case graph
        case gauge
        case value
    }

    public struct Cell: Equatable {
        public let item: BarItem
        public let x: CGFloat
        public let width: CGFloat
        let parts: [(part: Part, x: CGFloat, width: CGFloat)]

        public static func == (a: Cell, b: Cell) -> Bool {
            a.item == b.item && a.x == b.x && a.width == b.width
                && a.parts.elementsEqual(b.parts) { $0.part == $1.part && $0.x == $1.x && $0.width == $1.width }
        }
    }

    func parts(for item: BarItem) -> [Part] {
        var parts: [Part] = []
        // A caption sits above the value when there is one, otherwise beside the chart.
        if layout.showCaptions && !item.style.showsValue { parts.append(.caption) }
        if item.style.showsGraph { parts.append(.graph) }
        if item.style.showsGauge { parts.append(.gauge) }
        if item.style.showsValue { parts.append(.value) }
        return parts
    }

    func width(of part: Part, for item: BarItem) -> CGFloat {
        switch part {
        case .caption: return Self.measure(item.metric.caption, Self.captionAttributes(Ink.full))
        case .graph: return layout.density.graphWidth
        case .gauge: return Self.gaugeWidth
        case .value: return valueWidth(item.metric)
        }
    }

    /// The widest string a metric can produce, so the cell never resizes.
    func valueWidth(_ metric: Metric) -> CGFloat {
        if metric.isRatePair {
            let glyph = Self.pairGlyphs(metric).map { Self.measure($0, Self.pairAttributes(Ink.full)) }.max()!
            return ceil(glyph + Self.pairGlyphGap + Self.widest(Self.rateTemplates, Self.pairFont))
        }
        let templates = metric == .storage ? ["888 GB", "888 TB", "8\(Format.decimalSeparator())8 TB"] : ["100%"]
        let stacked = layout.showCaptions
        var w = Self.widest(templates, stacked ? Self.stackedValueFont : Self.valueFont)
        if metric == .battery { w += Self.boltWidth(stacked) }
        if stacked { w = max(w, Self.measure(metric.caption, Self.captionAttributes(Ink.full))) }
        return ceil(w)
    }

    private func measureCells() -> [Cell] {
        var x: CGFloat = 0
        var cells: [Cell] = []
        for item in layout.visible {
            if !cells.isEmpty { x += layout.density.itemGap }
            let start = x
            var placed: [(Part, CGFloat, CGFloat)] = []
            for (i, part) in parts(for: item).enumerated() {
                if i > 0 { x += Self.partGap }
                let w = width(of: part, for: item)
                placed.append((part, x, w))
                x += w
            }
            cells.append(Cell(item: item, x: start, width: x - start, parts: placed))
        }
        return cells
    }

    public var size: CGSize {
        CGSize(width: ceil(cells.last.map { $0.x + $0.width } ?? 0), height: height)
    }

    // MARK: Drawing

    /// A template image of the whole bar, or nil when nothing is visible.
    public func image(_ readout: Readout) -> NSImage? {
        guard let last = cells.last else { return nil }
        let size = CGSize(width: ceil(last.x + last.width), height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            for cell in cells { self.draw(cell, readout) }
            return true
        }
        image.isTemplate = true
        return image
    }

    func draw(_ cell: Cell, _ readout: Readout) {
        let metric = cell.item.metric
        for (part, x, w) in cell.parts {
            let chart = CGRect(x: x, y: (height - chartHeight) / 2, width: w, height: chartHeight)
            switch part {
            case .caption:
                drawLine(metric.caption, Self.captionAttributes(Ink.secondary), x: x, width: w, align: .left)
            case .gauge:
                drawGauge(readout.fraction(metric) ?? 0, in: chart)
            case .graph:
                if metric.isRatePair {
                    drawMirrored(readout.primary[metric], readout.secondary[metric], floor: metric.rateFloor, in: chart)
                } else {
                    drawGraph(readout.primary[metric], readout.secondary[metric], in: chart)
                }
            case .value:
                if metric.isRatePair {
                    drawPair(metric, readout.rates(metric), x: x, width: w)
                } else {
                    drawValue(metric, readout, x: x, width: w)
                }
            }
        }
    }

    private func drawValue(_ metric: Metric, _ readout: Readout, x: CGFloat, width: CGFloat) {
        let text = readout.valueText(metric)
        let bolt = metric == .battery && readout.latest.battery.map { $0.state != .discharging } == true
        if layout.showCaptions {
            let caption = NSAttributedString(string: metric.caption, attributes: Self.captionAttributes(Ink.secondary))
            let value = Self.number(text, Self.stackedValueFont)
            let (top, bottom) = twoLineBaselines(Self.captionFont, Self.stackedValueFont)
            draw(caption, baseline: top, x: x, width: width, align: .right)
            draw(value, baseline: bottom, x: x, width: width, align: .right)
            if bolt { drawBolt(stacked: true, baseline: bottom, leftOf: x + width - value.size().width) }
        } else {
            let value = Self.number(text, Self.valueFont)
            let baseline = (height + Self.valueFont.capHeight) / 2
            draw(value, baseline: baseline, x: x, width: width, align: .right)
            if bolt { drawBolt(stacked: false, baseline: baseline, leftOf: x + width - value.size().width) }
        }
    }

    private func drawPair(_ metric: Metric, _ rates: RateReading?, x: CGFloat, width: CGFloat) {
        let glyphs = Self.pairGlyphs(metric)
        // Outbound on top, matching the mirrored graph.
        let values = [rates?.outbound, rates?.inbound].map { $0.map { Format.rate($0) } ?? Format.missing }
        let (top, bottom) = twoLineBaselines(Self.pairFont, Self.pairFont)
        for (i, baseline) in [top, bottom].enumerated() {
            draw(
                NSAttributedString(string: glyphs[i], attributes: Self.pairAttributes(Ink.secondary)),
                baseline: baseline, x: x, width: width, align: .left)
            draw(
                Self.number(values[i], Self.pairFont),
                baseline: baseline, x: x, width: width, align: .right)
        }
    }

    private func drawGauge(_ fraction: Double, in rect: CGRect) {
        let radius = rect.width / 2
        NSColor.black.withAlphaComponent(Ink.track).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let filled = rect.height * CGFloat(min(max(fraction, 0), 1))
        guard filled > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        NSColor.black.setFill()
        CGRect(x: rect.minX, y: rect.maxY - filled, width: rect.width, height: filled).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Fractions 0...1; newest sample at the right edge, one sample per point.
    private func drawGraph(_ primary: History?, _ secondary: History?, in rect: CGRect) {
        drawTrack(rect) {
            let n = Int(rect.width)
            if let primary {
                let total = primary.suffix(n)
                NSColor.black.withAlphaComponent(secondary == nil ? 0.85 : Ink.secondary).setFill()
                Self.area(total, in: rect, scale: 1).fill()
            }
            if let secondary {
                NSColor.black.setFill()
                Self.area(secondary.suffix(n), in: rect, scale: 1).fill()
            }
        }
    }

    /// Outbound grows up from the midline, inbound down, on a shared scale.
    private func drawMirrored(_ inbound: History?, _ outbound: History?, floor: Double, in rect: CGRect) {
        drawTrack(rect) {
            let n = Int(rect.width)
            let peak = max(inbound?.max(last: n) ?? 0, outbound?.max(last: n) ?? 0, floor)
            let half = rect.height / 2
            // The midline says "two-way" even when the link is idle.
            NSColor.black.withAlphaComponent(Ink.track * 2).setFill()
            CGRect(x: rect.minX, y: rect.midY - 0.25, width: rect.width, height: 0.5).fill()
            var top = rect
            top.size.height = half
            var bottom = top
            bottom.origin.y += half
            if let outbound {
                NSColor.black.withAlphaComponent(Ink.secondary + 0.15).setFill()
                Self.area(outbound.suffix(n), in: top, scale: peak).fill()
            }
            if let inbound {
                NSColor.black.setFill()
                Self.area(inbound.suffix(n), in: bottom, scale: peak, fromTop: true).fill()
            }
        }
    }

    private func drawTrack(_ rect: CGRect, _ body: () -> Void) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSColor.black.withAlphaComponent(Ink.track).setFill()
        path.fill()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A filled area: one point-wide column per sample, right-aligned. In a
    /// flipped context, "bottom" is maxY unless `fromTop`.
    static func area(_ values: [Double], in rect: CGRect, scale: Double, fromTop: Bool = false) -> NSBezierPath {
        let path = NSBezierPath()
        guard !values.isEmpty else { return path }
        let base = fromTop ? rect.minY : rect.maxY
        let sign: CGFloat = fromTop ? 1 : -1
        var x = rect.maxX - CGFloat(values.count)
        path.move(to: CGPoint(x: x, y: base))
        for v in values {
            let h = rect.height * CGFloat(min(max(v / scale, 0), 1))
            path.line(to: CGPoint(x: x, y: base + sign * h))
            x += 1
            path.line(to: CGPoint(x: x, y: base + sign * h))
        }
        path.line(to: CGPoint(x: x, y: base))
        path.close()
        return path
    }

    private func drawBolt(stacked: Bool, baseline: CGFloat, leftOf valueX: CGFloat) {
        let size = stacked ? 7.0 : 8.5
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .bold)
        guard
            let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        else { return }
        let capHeight = (stacked ? Self.stackedValueFont : Self.valueFont).capHeight
        let rect = CGRect(
            x: valueX - bolt.size.width - 1, y: baseline - capHeight / 2 - bolt.size.height / 2,
            width: bolt.size.width, height: bolt.size.height)
        bolt.draw(in: rect)
    }

    static func boltWidth(_ stacked: Bool) -> CGFloat { stacked ? 8 : 10 }

    // MARK: Text

    private func twoLineBaselines(_ top: NSFont, _ bottom: NSFont) -> (CGFloat, CGFloat) {
        let gap: CGFloat = 3.5
        let block = top.capHeight + gap + bottom.capHeight
        let first = (height - block) / 2 + top.capHeight
        return (first, first + gap + bottom.capHeight)
    }

    private func drawLine(
        _ text: String, _ attributes: [NSAttributedString.Key: Any], x: CGFloat, width: CGFloat, align: NSTextAlignment
    ) {
        let font = attributes[.font] as! NSFont
        draw(
            NSAttributedString(string: text, attributes: attributes), baseline: (height + font.capHeight) / 2, x: x,
            width: width, align: align)
    }

    private func draw(_ text: NSAttributedString, baseline: CGFloat, x: CGFloat, width: CGFloat, align: NSTextAlignment)
    {
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        let w = text.size().width
        let originX = align == .right ? x + width - w : x
        // In a flipped context the drawing origin is the line's top; the baseline sits one ascender below.
        text.draw(at: CGPoint(x: originX, y: baseline - font.ascender))
    }

    /// A value whose unit ("%", " MB/s") is set in secondary ink, so the
    /// number carries the reading. Widths are unchanged: ink isn't geometry.
    static func number(_ text: String, _ font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: valueAttributes(font))
        let digits = text.prefix { $0.isNumber || $0 == "." || $0 == "," }.count
        if digits > 0, digits < text.count {
            let unit = NSRange(text.index(text.startIndex, offsetBy: digits)..., in: text)
            result.addAttribute(.foregroundColor, value: NSColor.black.withAlphaComponent(Ink.secondary), range: unit)
        }
        return result
    }

    static func valueAttributes(_ font: NSFont) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.black]
    }

    static func pairAttributes(_ ink: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: pairFont, .foregroundColor: NSColor.black.withAlphaComponent(ink)]
    }

    static func captionAttributes(_ ink: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: captionFont, .foregroundColor: NSColor.black.withAlphaComponent(ink), .kern: 0.4]
    }

    static func pairGlyphs(_ metric: Metric) -> [String] {
        metric == .network ? ["↑", "↓"] : ["W", "R"]
    }

    static var rateTemplates: [String] {
        ["888 KB/s", "888 MB/s", "888 GB/s", "8\(Format.decimalSeparator())8 MB/s", "888 B/s"]
    }

    static func measure(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: attributes).size().width)
    }

    static func widest(_ texts: [String], _ font: NSFont) -> CGFloat {
        texts.map { measure($0, valueAttributes(font)) }.max() ?? 0
    }

    // MARK: Accessibility

    public func accessibilityText(_ readout: Readout) -> String {
        layout.visible.map { item -> String in
            let m = item.metric
            if let r = readout.rates(m) {
                let (outName, inName) = m == .network ? ("up", "down") : ("write", "read")
                return "\(m.name) \(inName) \(Format.rate(r.inbound)), \(outName) \(Format.rate(r.outbound))"
            }
            return "\(m.name) \(readout.valueText(m))"
        }.joined(separator: ", ")
    }
}
