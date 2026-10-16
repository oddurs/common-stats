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
                .onMove { model.layout.items.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Items")
            } footer: {
                Text("Drag to reorder. Items appear left to right.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Toggle("Show labels", isOn: $model.layout.showCaptions)
                Picker("Density", selection: $model.layout.density) {
                    ForEach(Density.allCases, id: \.self) { Text($0.name) }
                }
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
        return Picker(selection: item.style) {
            ForEach(metric.styles, id: \.self) { Text($0.name) }
        } label: {
            HStack(spacing: 10) {
                IconTile(metric: metric)
                Text(metric.name)
            }
            // Items left off the bar recede, so the shown set reads at a glance.
            .opacity(shown ? 1 : 0.5)
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
                Image(nsImage: image)
                    .renderingMode(.template)
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
