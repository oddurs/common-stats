import StatKit
import SwiftUI
import UniformTypeIdentifiers

/// The menu bar preview, editable in place. Each item is drawn by the same
/// renderer as the real menu bar. Drag items to reorder them, drag one out
/// to the tray to remove it, drag one in from the tray (or click it) to add
/// it, and click an item to choose how it looks.
struct BarEditor: View {
    @Bindable var model: AppModel

    @State private var selected: Metric?
    @State private var hovered: Metric?
    /// The item being dragged. Every drag starts in this view, so drops read
    /// this instead of decoding the pasteboard.
    @State private var dragging: Metric?
    /// The gap a drag over the strip would drop into, 0...visible count.
    @State private var insertion: Int?
    @State private var frames: [Metric: CGRect] = [:]
    @State private var trayTargeted = false

    private var height: CGFloat { NSStatusBar.system.thickness }
    private var spacing: CGFloat { max(model.layout.density.itemGap - 8, 2) }

    var body: some View {
        VStack(spacing: 12) {
            strip
            tray
            Text("Drag to arrange. Click an item to change how it looks.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: The strip

    private var strip: some View {
        let visible = model.layout.visible.map(\.metric)
        return HStack(spacing: spacing) {
            if visible.isEmpty {
                Text("Drag items here").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(visible, id: \.self) { metric in
                piece(metric)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height + 14)
        .background(.bar, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(insertion == nil ? 0.08 : 0.2), lineWidth: 0.5)
        )
        .overlay(alignment: .topLeading) { indicator(visible) }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(FramesKey.self) { frames = $0 }
        .onDrop(
            of: [UTType.utf8PlainText],
            delegate: StripDrop(
                dragging: dragging, frames: frames, visible: visible, insertion: $insertion,
                drop: { metric, slot in
                    withAnimation(.snappy(duration: 0.2)) { place(metric, inSlot: slot, of: visible) }
                    dragging = nil
                }))
    }

    private static let space = "strip"

    private func piece(_ metric: Metric) -> some View {
        let item = BarItem(metric, model.layout.visible.first { $0.metric == metric }?.style ?? .value)
        var only = model.layout
        only.items = [item]
        let renderer = BarRenderer(layout: only, height: height)
        return Group {
            if let image = renderer.image(model.readout) {
                Image(nsImage: image)
                    .renderingMode(model.layout.colorInMenuBar ? .original : .template)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        // Selected looks like a pressed menu bar item; hover is a lighter hint that it's clickable.
        .background(
            Color.primary.opacity(selected == metric ? 0.16 : hovered == metric ? 0.07 : 0),
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .opacity(dragging == metric && insertion != nil ? 0.35 : 1)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: FramesKey.self, value: [metric: g.frame(in: .named(Self.space))])
            }
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? metric : (hovered == metric ? nil : hovered) }
        .onTapGesture { selected = selected == metric ? nil : metric }
        .onDrag {
            dragging = metric
            selected = nil
            return NSItemProvider(object: metric.rawValue as NSString)
        }
        .popover(
            isPresented: Binding(get: { selected == metric }, set: { if !$0, selected == metric { selected = nil } }),
            arrowEdge: .bottom
        ) {
            ItemInspector(model: model, metric: metric) { selected = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.name), \(item.style.name)")
        .accessibilityHint("Opens options for this item")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selected = metric }
        // Dragging is invisible to VoiceOver and keyboard users; these are the accessible path.
        .accessibilityActions {
            Button("Move Left") { nudge(metric, by: -1) }
            Button("Move Right") { nudge(metric, by: 1) }
            Button("Remove from Menu Bar") { model.layout.remove(metric) }
        }
    }

    /// A line in the gap the drop would land in.
    @ViewBuilder private func indicator(_ visible: [Metric]) -> some View {
        if let slot = insertion {
            let x: CGFloat? = {
                if visible.isEmpty { return nil }
                if slot == 0 { return frames[visible[0]].map { $0.minX - spacing / 2 } }
                return frames[visible[slot - 1]].map { $0.maxX + spacing / 2 }
            }()
            if let x {
                Capsule().fill(Color.accentColor)
                    .frame(width: 2, height: height)
                    .offset(x: x - 1, y: 7)
            }
        }
    }

    private func place(_ metric: Metric, inSlot slot: Int, of visible: [Metric]) {
        // Slots count gaps around every visible item, including the dragged one;
        // `place` counts positions once it has left its old place.
        let adjusted = visible.firstIndex(of: metric).map { slot > $0 ? slot - 1 : slot } ?? slot
        model.layout.place(metric, atVisibleIndex: adjusted)
    }

    private func nudge(_ metric: Metric, by offset: Int) {
        guard let i = model.layout.visible.firstIndex(where: { $0.metric == metric }) else { return }
        model.layout.place(metric, atVisibleIndex: max(i + offset, 0))
    }

    // MARK: The tray

    private var tray: some View {
        let hidden = model.layout.items.filter { $0.style == .hidden }.map(\.metric).filter(isAvailable)
        return HStack(spacing: 6) {
            if hidden.isEmpty {
                Text("Everything is in the menu bar")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            ForEach(hidden, id: \.self) { metric in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { model.layout.place(metric, atVisibleIndex: .max) }
                } label: {
                    HStack(spacing: 6) {
                        IconTile(metric: metric, size: 16)
                        Text(metric.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Drag into the menu bar, or click to add")
                .onDrag {
                    dragging = metric
                    return NSItemProvider(object: metric.rawValue as NSString)
                }
                .accessibilityLabel("Add \(metric.name)")
            }
            if !hidden.isEmpty { Spacer(minLength: 0) }
        }
        .frame(minHeight: 30)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    trayTargeted ? Color.accentColor : Color.primary.opacity(0.1),
                    style: StrokeStyle(lineWidth: 1, dash: trayTargeted ? [] : [3, 3]))
        )
        // Dropping an item from the strip here removes it.
        .dropDestination(for: String.self) { _, _ in
            guard let metric = dragging, model.layout.visible.contains(where: { $0.metric == metric }) else {
                return false
            }
            withAnimation(.snappy(duration: 0.2)) { model.layout.remove(metric) }
            dragging = nil
            return true
        } isTargeted: {
            trayTargeted = $0 && dragging.map { m in model.layout.visible.contains { $0.metric == m } } == true
        }
    }

    /// Desktops have no battery; don't offer it.
    private func isAvailable(_ metric: Metric) -> Bool {
        metric != .battery || model.readout.latest.battery != nil
    }
}

/// Tracks a drag over the strip and drops into the gap under the pointer.
private struct StripDrop: DropDelegate {
    let dragging: Metric?
    let frames: [Metric: CGRect]
    let visible: [Metric]
    @Binding var insertion: Int?
    let drop: (Metric, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func dropEntered(info: DropInfo) { insertion = slot(at: info.location.x) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        insertion = slot(at: info.location.x)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { insertion = nil }

    func performDrop(info: DropInfo) -> Bool {
        let slot = slot(at: info.location.x)
        insertion = nil
        guard let dragging else { return false }
        drop(dragging, slot)
        return true
    }

    /// The number of items whose centre lies left of `x`.
    private func slot(at x: CGFloat) -> Int {
        visible.filter { (frames[$0]?.midX ?? .infinity) < x }.count
    }
}

private struct FramesKey: PreferenceKey {
    static let defaultValue: [Metric: CGRect] = [:]
    static func reduce(value: inout [Metric: CGRect], nextValue: () -> [Metric: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The popover for one item: how it's drawn, or take it out.
private struct ItemInspector: View {
    @Bindable var model: AppModel
    let metric: Metric
    let dismiss: () -> Void

    private var style: Binding<Style> {
        Binding(
            get: { model.layout.items.first { $0.metric == metric }?.style ?? .value },
            set: { new in
                if let i = model.layout.items.firstIndex(where: { $0.metric == metric }) {
                    model.layout.items[i].style = new
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconTile(metric: metric, size: 20)
                Text(metric.name).font(.headline)
            }
            Picker("Show as", selection: style) {
                ForEach(metric.styles.filter { $0 != .hidden }, id: \.self) { Text($0.name) }
            }
            .pickerStyle(.radioGroup)
            Divider()
            Button("Remove from Menu Bar", role: .destructive) {
                model.layout.remove(metric)
                dismiss()
            }
        }
        .padding(14)
        .frame(width: 230, alignment: .leading)
    }
}
