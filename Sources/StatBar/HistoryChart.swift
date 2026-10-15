import StatKit
import SwiftUI

struct ChartSeries {
    let name: String
    let history: History?
    let ink: Color
    /// A line over a gradient. Otherwise a solid band beneath the others.
    let emphasis: Bool
}

/// The dropdown's history graph. Newest sample on the right edge, a fixed
/// time axis (one step per sample of the full history, so the graph scrolls
/// rather than stretches), monotone curves that never invent extremes, and
/// hover to read any moment back.
///
/// `up` series grow from the baseline; when `down` is non-empty the chart
/// mirrors around a midline, `up` above and `down` below, on one scale.
struct HistoryChart: View {
    enum Scale {
        case fraction
        /// Auto-scales to the visible peak, never below `floor`.
        case rate(floor: Double)
    }

    let up: [ChartSeries]
    var down: [ChartSeries] = []
    let scale: Scale
    let interval: TimeInterval
    let format: (Double) -> String
    var height: CGFloat = 48
    /// Pins the hover marker this many samples back from now, for offscreen review.
    var previewHover: Int?

    @State private var hoverX: CGFloat?

    private var mirrored: Bool { !down.isEmpty }
    private var count: Int { (up + down).compactMap { $0.history?.count }.max() ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let step = size.width / CGFloat(Readout.capacity - 1)
            let peak = self.peak
            let hover = hoverIndex(size: size, step: step)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(context, size)
                    let (upper, lower) = halves(size)
                    for series in up where !series.emphasis { band(context, series, upper, step, peak, down: false) }
                    for series in up where series.emphasis { area(context, series, upper, step, peak, down: false) }
                    for series in down { area(context, series, lower, step, peak, down: true) }
                    if let hover { drawHover(context, size, hover, step, peak) }
                }
                if case .rate = scale, hover == nil {
                    // Auto-scaling hides magnitude; say what full height means.
                    scaleLabel(format(peak)).padding(.leading, 6).padding(.top, 3)
                }
                if let hover { hoverLabel(hover, size: size, step: step) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hoverX = point.x
                case .ended: hoverX = nil
                }
            }
        }
        .frame(height: height)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: Geometry

    private var peak: Double {
        switch scale {
        case .fraction: 1
        case .rate(let floor):
            max((up + down).map { $0.history?.max(last: Readout.capacity) ?? 0 }.max() ?? 0, floor)
        }
    }

    /// Plot areas, inset so a full-scale line isn't clipped by the rounded edge.
    private func halves(_ size: CGSize) -> (CGRect, CGRect) {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0, dy: 2)
        guard mirrored else { return (rect, rect) }
        let half = rect.height / 2
        return (
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: half),
            CGRect(x: rect.minX, y: rect.minY + half, width: rect.width, height: half)
        )
    }

    private func x(_ i: Int, of count: Int, width: CGFloat, step: CGFloat) -> CGFloat {
        width - CGFloat(count - 1 - i) * step
    }

    private func hoverIndex(size: CGSize, step: CGFloat) -> Int? {
        if let previewHover { return count > 0 ? min(max(count - 1 - previewHover, 0), count - 1) : nil }
        guard let hoverX, count > 0 else { return nil }
        let back = Int(((size.width - hoverX) / step).rounded())
        let i = count - 1 - back
        return i >= 0 ? i : nil
    }

    // MARK: Drawing

    private func drawGrid(_ context: GraphicsContext, _ size: CGSize) {
        let faint = GraphicsContext.Shading.color(.primary.opacity(0.07))
        if mirrored {
            context.fill(Path(CGRect(x: 0, y: size.height / 2 - 0.25, width: size.width, height: 0.5)), with: faint)
            return
        }
        for f in [0.25, 0.5, 0.75] {
            var line = Path()
            let y = size.height * (1 - f)
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: faint, style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        }
    }

    /// The series' edge as a smooth path, plus its first and last x.
    private func edge(
        _ h: History, in rect: CGRect, step: CGFloat, peak: Double, down: Bool
    ) -> (Path, CGFloat, CGFloat)? {
        guard h.count > 1 else { return nil }
        let base = down ? rect.minY : rect.maxY
        let sign: CGFloat = down ? 1 : -1
        let values = (0..<h.count).map { min(max(h[$0] / peak, 0), 1) }
        let tangents = monotoneTangents(values)
        let first = x(0, of: h.count, width: rect.maxX, step: step)
        func point(_ i: Int) -> CGPoint {
            CGPoint(x: first + CGFloat(i) * step, y: base + sign * rect.height * CGFloat(values[i]))
        }
        var path = Path()
        path.move(to: point(0))
        for i in 0..<values.count - 1 {
            let a = point(i), b = point(i + 1)
            let c1 = CGPoint(x: a.x + step / 3, y: a.y + sign * rect.height * CGFloat(tangents[i] / 3))
            let c2 = CGPoint(x: b.x - step / 3, y: b.y - sign * rect.height * CGFloat(tangents[i + 1] / 3))
            path.addCurve(to: b, control1: c1, control2: c2)
        }
        return (path, first, point(values.count - 1).x)
    }

    private func closed(_ edge: Path, from first: CGFloat, to last: CGFloat, base: CGFloat) -> Path {
        var area = edge
        area.addLine(to: CGPoint(x: last, y: base))
        area.addLine(to: CGPoint(x: first, y: base))
        area.closeSubpath()
        return area
    }

    private func area(
        _ context: GraphicsContext, _ s: ChartSeries, _ rect: CGRect, _ step: CGFloat, _ peak: Double, down: Bool
    ) {
        guard let h = s.history, let (line, first, last) = edge(h, in: rect, step: step, peak: peak, down: down)
        else { return }
        let base = down ? rect.minY : rect.maxY, far = down ? rect.maxY : rect.minY
        context.fill(
            closed(line, from: first, to: last, base: base),
            with: .linearGradient(
                Gradient(colors: [s.ink.opacity(0.42), s.ink.opacity(0.04)]),
                startPoint: CGPoint(x: 0, y: far), endPoint: CGPoint(x: 0, y: base)))
        context.stroke(line, with: .color(s.ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    private func band(
        _ context: GraphicsContext, _ s: ChartSeries, _ rect: CGRect, _ step: CGFloat, _ peak: Double, down: Bool
    ) {
        guard let h = s.history, let (line, first, last) = edge(h, in: rect, step: step, peak: peak, down: down)
        else { return }
        context.fill(closed(line, from: first, to: last, base: down ? rect.minY : rect.maxY), with: .color(s.ink))
    }

    private func drawHover(_ context: GraphicsContext, _ size: CGSize, _ i: Int, _ step: CGFloat, _ peak: Double) {
        let hx = x(i, of: count, width: size.width, step: step)
        context.fill(
            Path(CGRect(x: hx - 0.5, y: 0, width: 1, height: size.height)), with: .color(.primary.opacity(0.35)))
        let (upper, lower) = halves(size)
        for (series, rect, isDown) in up.map({ ($0, upper, false) }) + down.map({ ($0, lower, true) }) {
            guard series.emphasis, let h = series.history, let v = value(h, at: i) else { continue }
            let f = CGFloat(min(max(v / peak, 0), 1))
            let y = isDown ? rect.minY + rect.height * f : rect.maxY - rect.height * f
            let dot = CGRect(x: hx - 3.5, y: y - 3.5, width: 7, height: 7)
            context.fill(Path(ellipseIn: dot), with: .color(.white))
            context.fill(Path(ellipseIn: dot.insetBy(dx: 1.5, dy: 1.5)), with: .color(series.ink))
        }
    }

    /// Histories can differ in length by a sample; index from the newest end.
    private func value(_ h: History, at i: Int) -> Double? {
        let j = h.count - (count - i)
        return j >= 0 && j < h.count ? h[j] : nil
    }

    private func hoverLabel(_ i: Int, size: CGSize, step: CGFloat) -> some View {
        let seconds = Double(count - 1 - i) * interval
        let parts = (down + up).filter(\.emphasis).compactMap { s -> String? in
            guard let h = s.history, let v = value(h, at: i) else { return nil }
            return "\(s.name) \(format(v))"
        }
        let hx = x(i, of: count, width: size.width, step: step)
        return HStack(spacing: 6) {
            Text(ago(seconds)).foregroundStyle(.secondary)
            Text(parts.joined(separator: "  ")).monospacedDigit()
        }
        .font(.system(size: 10, weight: .medium))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        // Sit beside the cursor line, flipping sides near the right edge.
        .alignmentGuide(.leading) { d in
            hx > size.width - d.width - 12 ? d.width + 6 - hx : -(hx + 6)
        }
        .padding(.top, 3)
    }

    private func ago(_ seconds: TimeInterval) -> String {
        guard seconds >= 0.5 else { return "now" }
        let s = Int(seconds.rounded())
        return s < 60 ? "\(s)s ago" : "\(s / 60)m \(s % 60)s ago"
    }

    private func scaleLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(.tertiary)
    }
}
