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
                BarEditor(model: model)
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
                Picker("Average over", selection: $model.layout.smoothing) {
                    ForEach(Smoothing.allCases, id: \.self) { Text($0.name) }
                }
            } header: {
                Text("General")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Averaging steadies the menu bar’s numbers and graphs. The menu always shows exact readings.")
                    if let loginError { Text(loginError) }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            CommonToolsSection()
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
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
