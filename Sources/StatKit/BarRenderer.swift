import AppKit

/// The menu bar layout engine. Widths depend only on the layout, never on
/// the values, so the status item never jitters as numbers change.
///
/// By default everything is drawn in black at varying opacity into a
/// template image, and AppKit tints it like any system menu bar extra
/// (light, dark, inactive display, increased contrast). With colour on, the
/// image is drawn in dynamic system colours instead, which resolve against
/// the menu bar's appearance at draw time.
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

    /// Opacity steps for marks, applied to whatever colour a mark has.
    enum Alpha {
        static let secondary: CGFloat = 0.5
        static let track: CGFloat = 0.11
    }

    /// The colours one render uses. Template ink is black at fixed opacities,
    /// which is all a template image keeps.
    struct Ink {
        let text: NSColor
        let secondary: NSColor
        let track: NSColor
        let mark: (Metric) -> NSColor
        let isTemplate: Bool

        static var template: Ink {
            Ink(
                text: .black, secondary: .black.withAlphaComponent(Alpha.secondary),
                track: .black.withAlphaComponent(Alpha.track), mark: { _ in .black }, isTemplate: true)
        }

        static func color(_ palette: Palette) -> Ink {
            Ink(
                text: .labelColor, secondary: .secondaryLabelColor,
                track: .labelColor.withAlphaComponent(Alpha.track), mark: { palette.color(for: $0) },
                isTemplate: false)
        }
    }

    var ink: Ink { layout.colorInMenuBar ? .color(layout.palette) : .template }

    /// Samples each displayed value averages over; 1 shows raw readings.
    var window: Int { layout.smoothing.window(interval: layout.interval) }

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
        case .caption: return Self.measure(item.metric.caption, Self.captionAttributes())
        case .graph: return layout.density.graphWidth
        case .gauge: return Self.gaugeWidth
        case .value: return valueWidth(item.metric)
        }
    }

    /// The widest string a metric can produce, so the cell never resizes.
    func valueWidth(_ metric: Metric) -> CGFloat {
        if metric.isRatePair {
            let glyph = Self.pairGlyphs(metric).map { Self.measure($0, Self.pairAttributes()) }.max()!
            return ceil(glyph + Self.pairGlyphGap + Self.widest(Self.rateTemplates, Self.pairFont))
        }
        let templates = metric == .storage ? ["888 GB", "888 TB", "8\(Format.decimalSeparator())8 TB"] : ["100%"]
        let stacked = layout.showCaptions
        var w = Self.widest(templates, stacked ? Self.stackedValueFont : Self.valueFont)
        if metric == .battery { w += Self.boltWidth(stacked) }
        if stacked { w = max(w, Self.measure(metric.caption, Self.captionAttributes())) }
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

    /// An image of the whole bar, or nil when nothing is visible. A template
    /// image unless the layout asks for colour.
    public func image(_ readout: Readout) -> NSImage? {
        guard let last = cells.last else { return nil }
        let size = CGSize(width: ceil(last.x + last.width), height: height)
        let ink = self.ink
        let image = NSImage(size: size, flipped: true) { _ in
            for cell in cells { self.draw(cell, readout, ink) }
            return true
        }
        image.isTemplate = !layout.colorInMenuBar
        return image
    }

    func draw(_ cell: Cell, _ readout: Readout, _ ink: Ink) {
        let metric = cell.item.metric
        let mark = ink.mark(metric)
        for (part, x, w) in cell.parts {
            let chart = CGRect(x: x, y: (height - chartHeight) / 2, width: w, height: chartHeight)
            switch part {
            case .caption:
                drawLine(metric.caption, Self.captionAttributes(ink.secondary), x: x, width: w, align: .left)
            case .gauge:
                drawGauge(readout.fraction(metric, window: window) ?? 0, mark: mark, ink: ink, in: chart)
            case .graph:
                if metric.isRatePair {
                    drawMirrored(
                        readout.primary[metric], readout.secondary[metric], floor: metric.rateFloor, mark: mark,
                        ink: ink, in: chart)
                } else {
                    drawGraph(readout.primary[metric], readout.secondary[metric], mark: mark, ink: ink, in: chart)
                }
            case .value:
                if metric.isRatePair {
                    drawPair(metric, readout.rates(metric, window: window), ink: ink, x: x, width: w)
                } else {
                    drawValue(metric, readout, ink: ink, x: x, width: w)
                }
            }
        }
    }

    private func drawValue(_ metric: Metric, _ readout: Readout, ink: Ink, x: CGFloat, width: CGFloat) {
        let text = readout.valueText(metric, window: window)
        let bolt = metric == .battery && readout.latest.battery.map { $0.state != .discharging } == true
        if layout.showCaptions {
            let caption = NSAttributedString(string: metric.caption, attributes: Self.captionAttributes(ink.secondary))
            let value = Self.number(text, Self.stackedValueFont, ink: ink)
            let (top, bottom) = twoLineBaselines(Self.captionFont, Self.stackedValueFont)
            draw(caption, baseline: top, x: x, width: width, align: .right)
            draw(value, baseline: bottom, x: x, width: width, align: .right)
            if bolt { drawBolt(stacked: true, ink: ink, baseline: bottom, leftOf: x + width - value.size().width) }
        } else {
            let value = Self.number(text, Self.valueFont, ink: ink)
            let baseline = (height + Self.valueFont.capHeight) / 2
            draw(value, baseline: baseline, x: x, width: width, align: .right)
            if bolt { drawBolt(stacked: false, ink: ink, baseline: baseline, leftOf: x + width - value.size().width) }
        }
    }

    private func drawPair(_ metric: Metric, _ rates: RateReading?, ink: Ink, x: CGFloat, width: CGFloat) {
        let glyphs = Self.pairGlyphs(metric)
        // Outbound on top, matching the mirrored graph.
        let values = [rates?.outbound, rates?.inbound].map { $0.map { Format.rate($0) } ?? Format.missing }
        let (top, bottom) = twoLineBaselines(Self.pairFont, Self.pairFont)
        for (i, baseline) in [top, bottom].enumerated() {
            draw(
                NSAttributedString(string: glyphs[i], attributes: Self.pairAttributes(ink.secondary)),
                baseline: baseline, x: x, width: width, align: .left)
            draw(
                Self.number(values[i], Self.pairFont, ink: ink),
                baseline: baseline, x: x, width: width, align: .right)
        }
    }

    private func drawGauge(_ fraction: Double, mark: NSColor, ink: Ink, in rect: CGRect) {
        let radius = rect.width / 2
        ink.track.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let filled = rect.height * CGFloat(min(max(fraction, 0), 1))
        guard filled > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        mark.setFill()
        CGRect(x: rect.minX, y: rect.maxY - filled, width: rect.width, height: filled).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Fractions 0...1; newest sample at the right edge, one sample per point.
    private func drawGraph(_ primary: History?, _ secondary: History?, mark: NSColor, ink: Ink, in rect: CGRect) {
        drawTrack(rect, ink) {
            let n = Int(rect.width)
            if let primary {
                let total = primary.trailingMeans(last: n, window: window)
                mark.withAlphaComponent(secondary == nil ? 0.85 : Alpha.secondary).setFill()
                Self.area(total, in: rect, scale: 1).fill()
            }
            if let secondary {
                mark.setFill()
                Self.area(secondary.trailingMeans(last: n, window: window), in: rect, scale: 1).fill()
            }
        }
    }

    /// Outbound grows up from the midline, inbound down, on a shared scale.
    private func drawMirrored(
        _ inbound: History?, _ outbound: History?, floor: Double, mark: NSColor, ink: Ink, in rect: CGRect
    ) {
        drawTrack(rect, ink) {
            let n = Int(rect.width)
            let down = inbound?.trailingMeans(last: n, window: window) ?? []
            let up = outbound?.trailingMeans(last: n, window: window) ?? []
            let peak = max(down.max() ?? 0, up.max() ?? 0, floor)
            let half = rect.height / 2
            // The midline says "two-way" even when the link is idle.
            ink.text.withAlphaComponent(Alpha.track * 2).setFill()
            CGRect(x: rect.minX, y: rect.midY - 0.25, width: rect.width, height: 0.5).fill()
            var top = rect
            top.size.height = half
            var bottom = top
            bottom.origin.y += half
            mark.withAlphaComponent(Alpha.secondary + 0.15).setFill()
            Self.area(up, in: top, scale: peak).fill()
            mark.setFill()
            Self.area(down, in: bottom, scale: peak, fromTop: true).fill()
        }
    }

    private func drawTrack(_ rect: CGRect, _ ink: Ink, _ body: () -> Void) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        ink.track.setFill()
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

    private func drawBolt(stacked: Bool, ink: Ink, baseline: CGFloat, leftOf valueX: CGFloat) {
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
        if ink.isTemplate {
            bolt.draw(in: rect)
        } else {
            // Symbol images draw black; tint it to the label colour for a colour bar.
            NSGraphicsContext.saveGraphicsState()
            bolt.draw(in: rect)
            ink.text.set()
            rect.fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
        }
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
    static func number(_ text: String, _ font: NSFont, ink: Ink = .template) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: valueAttributes(font, ink.text))
        let digits = text.prefix { $0.isNumber || $0 == "." || $0 == "," }.count
        if digits > 0, digits < text.count {
            let unit = NSRange(text.index(text.startIndex, offsetBy: digits)..., in: text)
            result.addAttribute(.foregroundColor, value: ink.secondary, range: unit)
        }
        return result
    }

    static func valueAttributes(_ font: NSFont, _ color: NSColor = .black) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    static func pairAttributes(_ color: NSColor = .black) -> [NSAttributedString.Key: Any] {
        [.font: pairFont, .foregroundColor: color]
    }

    static func captionAttributes(_ color: NSColor = .black) -> [NSAttributedString.Key: Any] {
        [.font: captionFont, .foregroundColor: color, .kern: 0.4]
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
            if let r = readout.rates(m, window: window) {
                let (outName, inName) = m == .network ? ("up", "down") : ("write", "read")
                return "\(m.name) \(inName) \(Format.rate(r.inbound)), \(outName) \(Format.rate(r.outbound))"
            }
            return "\(m.name) \(readout.valueText(m, window: window))"
        }.joined(separator: ", ")
    }
}
