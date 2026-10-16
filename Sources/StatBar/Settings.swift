import AppKit
import ServiceManagement
import StatKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            host.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: host)
            window.title = "Common Stats Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // Activation is cooperative since macOS 14: the system may decline
        // it, and an accessory app's window would then open behind the
        // frontmost app. Ordering front regardless keeps it visible either way.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var loginError: String?
    /// The row a dragged item is hovering over, for the drop indicator.
    @State private var dropTarget: Metric?
    @State private var dragging: Metric?

    var body: some View {
        Form {
            Section {
                BarPreview(model: model)
            } footer: {
                if !model.barVisible {
                    Label {
                        Text(
                            "Common Stats is running but can’t be seen in the menu bar. It may be behind the camera housing or hidden by a menu bar manager. Show fewer items, choose Compact density, or hold ⌘ and drag other menu bar items out of the way."
                        )
                    } icon: {
                        Image(systemName: "eye.slash")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach($model.layout.items) { $item in
                    row($item)
                }
            } header: {
                Text("Items")
            } footer: {
                Text("Drag to reorder. Items appear left to right.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show labels", isOn: $model.layout.showCaptions)
                Picker("Density", selection: $model.layout.density) {
                    ForEach(Density.allCases, id: \.self) { Text($0.name) }
                }
                LabeledContent("Color") {
                    PaletteSwatches(selection: $model.layout.palette)
                }
                Toggle("Color in menu bar", isOn: $model.layout.colorInMenuBar)
            } header: {
                Text("Appearance")
            } footer: {
                Text(
                    "Color applies to graphs and gauges. Off in the menu bar, items stay monochrome like the system’s own icons."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at login", isOn: openAtLogin)
                Picker("Update every", selection: $model.layout.interval) {
                    ForEach(BarLayout.intervals, id: \.self) { s in
                        Text(s == 1 ? "1 second" : "\(s.formatted()) seconds")
                    }
                }
            } header: {
                Text("General")
            } footer: {
                if let loginError {
                    Text(loginError).font(.footnote).foregroundStyle(.secondary)
                }
            }

            CommonToolsSection()
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ item: Binding<BarItem>) -> some View {
        let metric = item.wrappedValue.metric
        let shown = item.wrappedValue.style != .hidden
        let index = model.layout.items.firstIndex { $0.metric == metric } ?? 0
        return HStack(spacing: 8) {
            Picker(selection: item.style) {
                ForEach(metric.styles, id: \.self) { Text($0.name) }
            } label: {
                HStack(spacing: 10) {
                    IconTile(metric: metric)
                    Text(metric.name)
                }
                // Items left off the bar recede, so the shown set reads at a glance.
                .opacity(shown ? 1 : 0.5)
            }
            // The handle is the drag source, so clicking the picker never starts a drag.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
                .onDrag {
                    dragging = metric
                    return NSItemProvider(object: metric.rawValue as NSString)
                } preview: {
                    HStack(spacing: 8) {
                        IconTile(metric: metric)
                        Text(metric.name)
                    }
                    .padding(6)
                }
                .help("Drag to reorder")
                .accessibilityHidden(true)
        }
        .dropDestination(for: String.self) { names, _ in
            guard let name = names.first, let moved = Metric(rawValue: name) else { return false }
            withAnimation(.snappy(duration: 0.2)) { model.layout.move(moved, onto: metric) }
            dropTarget = nil
            dragging = nil
            return true
        } isTargeted: { targeted in
            if targeted { dropTarget = metric } else if dropTarget == metric { dropTarget = nil }
        }
        .overlay(alignment: dropEdge(for: metric, at: index)) {
            if dropTarget == metric, dragging != metric {
                Capsule().fill(Color.accentColor).frame(height: 2).offset(
                    y: dropEdge(for: metric, at: index) == .top ? -5 : 5)
            }
        }
        // Dragging is invisible to VoiceOver and keyboard users; these are the accessible path.
        .contextMenu {
            Button("Move Up") { move(index, by: -1) }.disabled(index == 0)
            Button("Move Down") { move(index, by: 1) }.disabled(index == model.layout.items.count - 1)
        }
        .accessibilityActions {
            Button("Move Up") { move(index, by: -1) }
            Button("Move Down") { move(index, by: 1) }
        }
    }

    /// A dragged item lands before a row above it and after a row below it;
    /// the indicator sits on that edge.
    private func dropEdge(for target: Metric, at index: Int) -> Alignment {
        guard let dragging, let from = model.layout.items.firstIndex(where: { $0.metric == dragging }) else {
            return .top
        }
        return from < index ? .bottom : .top
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard model.layout.items.indices.contains(target) else { return }
        model.layout.items.swapAt(index, target)
    }

    private var openAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enable in
                do {
                    if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginError =
                        SMAppService.mainApp.status == .requiresApproval
                        ? "Allow Common Stats in System Settings › General › Login Items." : nil
                } catch {
                    loginError = error.localizedDescription
                }
            })
    }
}

/// The live bar, drawn by the same renderer as the menu bar.
private struct BarPreview: View {
    let model: AppModel

    var body: some View {
        let height = NSStatusBar.system.thickness
        let renderer = BarRenderer(layout: model.layout, height: height)
        Group {
            if let image = renderer.image(model.readout) {
                // A colour bar draws its own colours; a template one takes the label colour.
                Image(nsImage: image)
                    .renderingMode(model.layout.colorInMenuBar ? .original : .template)
                    .foregroundStyle(.primary)
            } else {
                Text("Nothing in the menu bar").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height + 12)
        .accessibilityElement()
        .accessibilityLabel("Preview: \(renderer.accessibilityText(model.readout))")
    }
}

/// Colour swatches in the style of System Settings' accent colour picker.
/// The selected swatch carries a white dot; its name shows beneath.
private struct PaletteSwatches: View {
    @Binding var selection: Palette

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 7) {
                ForEach(Palette.allCases, id: \.self) { palette in
                    Button {
                        selection = palette
                    } label: {
                        swatch(palette)
                            .overlay {
                                if palette == selection {
                                    Circle().fill(.white).frame(width: 6, height: 6).shadow(radius: 0.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(palette.name)
                    .accessibilityLabel(palette.name)
                    .accessibilityAddTraits(palette == selection ? .isSelected : [])
                }
            }
            Text(selection.name).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func swatch(_ palette: Palette) -> some View {
        let circle = Circle().frame(width: 16, height: 16)
        Group {
            switch palette {
            case .accent:
                circle.foregroundStyle(Color.accentColor)
            case .metric:
                // Per Metric shows every metric's colour, like the system's Multicolor swatch.
                circle.foregroundStyle(
                    AngularGradient(
                        colors: (Metric.allCases + [Metric.cpu]).map { Color(nsColor: $0.tint) }, center: .center))
            default:
                circle.foregroundStyle(Color(nsColor: palette.color(for: .cpu)))
            }
        }
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}
