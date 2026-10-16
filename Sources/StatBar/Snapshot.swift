import AppKit
import StatKit
import SwiftUI

/// `StatBar --snapshot out.png [seconds] [palette]` samples for a few seconds
/// and writes the bar at 2x on light and dark menu bars to `out.png` (the
/// last row in colour), and every menu section in light and dark, in the
/// given palette, to `out-menu.png`. Used for README images and for design
/// review without screen-recording permission.
@MainActor
enum SnapshotCommand {
    static func run(path: String, seconds: Int, palette: Palette) {
        let monitor = Monitor { _ in }
        var readout = Readout()
        for _ in 0..<seconds {
            readout.ingest(monitor.sampleNow())
            Thread.sleep(forTimeInterval: 1)
        }
        readout.ingest(monitor.sampleNow())
        writeBar(readout, to: path)
        writeMenu(readout, palette: palette, to: (path as NSString).deletingPathExtension + "-menu.png")
    }

    private static func writeMenu(_ readout: Readout, palette: Palette, to path: String) {
        let interval: TimeInterval = 1
        func menu(_ scheme: ColorScheme) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(DropdownPanel.panels(for: Metric.allCases), id: \.self) { panel in
                    // The network card shows the pointer resting on its graph, to review hover.
                    PanelView(
                        readout: readout, panel: panel, interval: interval, palette: palette,
                        previewHover: panel == .card(.network) ? 20 : nil)
                }
            }
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .environment(\.colorScheme, scheme)
        }
        let renderer = ImageRenderer(
            content: HStack(alignment: .top, spacing: 24) {
                menu(.light); menu(.dark)
            }
            .padding(24))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { fatalError("could not render menu") }
        write(png, to: path)
    }

    private static func writeBar(_ readout: Readout, to path: String) {
        let layouts: [BarLayout] = [
            .standard,
            BarLayout(
                items: Metric.allCases.map { BarItem($0, $0.isRatePair ? .graphValue : $0.styles.last!) },
                showCaptions: true, density: .regular, interval: 1),
            BarLayout(
                items: [
                    BarItem(.cpu, .graph), BarItem(.gpu, .graph), BarItem(.memory, .value), BarItem(.network, .graph),
                ],
                showCaptions: false, density: .compact, interval: 1, palette: .metric, colorInMenuBar: true),
        ]
        let height: CGFloat = 24
        let images = layouts.compactMap { BarRenderer(layout: $0, height: height).image(readout) }
        let width = (images.map(\.size.width).max() ?? 0) + 24
        let rowHeight = height + 4
        let size = CGSize(width: width, height: rowHeight * CGFloat(images.count) * 2)
        let scale: CGFloat = 2

        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { fatalError("could not allocate bitmap") }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (dark, origin) in [(false, 0.0), (true, size.height / 2)] {
            let band = CGRect(x: 0, y: origin, width: size.width, height: size.height / 2)
            (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            band.fill()
            for (i, image) in images.enumerated() {
                let y = band.maxY - rowHeight * CGFloat(i + 1) + 2
                let rect = CGRect(x: 12, y: y, width: image.size.width, height: image.size.height)
                if image.isTemplate {
                    tint(image, dark ? .white : .black).draw(in: rect)
                } else {
                    // A colour bar resolves its dynamic colours against the appearance it's drawn in.
                    NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                        image.draw(in: rect)
                    }
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }
        write(png, to: path)
    }

    private static func write(_ png: Data, to path: String) {
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("statbar: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    /// What AppKit does to a template image in the menu bar, minus vibrancy.
    private static func tint(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
