import AppKit
import StatKit
import SwiftUI

/// Owns the menu bar item. The dropdown is a real NSMenu so it opens, tracks,
/// and dismisses exactly like every other menu bar extra.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var renderer: BarRenderer?
    private var menuOpen = false

    init(model: AppModel) {
        self.model = model
        super.init()
        // The pre-rename name: macOS keys the item's saved menu bar position on it.
        item.autosaveName = "StatBar"
        item.button?.imagePosition = .imageOnly
        menu.delegate = self
        item.menu = menu
        if let window = item.button?.window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification,
                object: window)
        }
        render()
    }

    /// Called every sample. Sampling always continues so history stays
    /// complete, but drawing is skipped while nobody can see the item:
    /// behind the notch, collapsed by a menu bar manager, or under a
    /// full-screen app.
    func render() {
        guard let button = item.button else { return }
        if let window = button.window, !window.occlusionState.contains(.visible), !menuOpen { return }
        let height = NSStatusBar.system.thickness
        if renderer?.layout != model.layout || renderer?.height != height {
            renderer = BarRenderer(layout: model.layout, height: height)
        }
        guard let renderer else { return }
        if let image = renderer.image(model.readout) {
            button.image = image
            button.setAccessibilityLabel(renderer.accessibilityText(model.readout))
        } else {
            // Everything hidden: keep a quiet glyph so Settings stays reachable.
            button.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Common Stats")
            button.setAccessibilityLabel("Common Stats")
        }
    }

    // MARK: NSMenuDelegate

    /// Detail views exist only while the menu is open, so a closed menu costs nothing.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let visible = model.layout.visible.map(\.metric)
        let metrics = (visible.isEmpty ? Metric.allCases : visible).filter(isAvailable)
        for panel in DropdownPanel.panels(for: metrics) {
            menu.addItem(hosted(LivePanel(model: model, panel: panel)))
        }
        if !metrics.isEmpty { menu.addItem(.separator()) }

        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.activityMonitor) != nil {
            let open = NSMenuItem(
                title: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")
            open.target = self
            // Tahoe gives standard items icons; match them. Earlier releases show none.
            if #available(macOS 26, *) {
                open.image = NSImage(
                    systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: nil)
            }
            menu.addItem(open)
        }
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(
            title: "Quit Common Stats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        // Drop the hosting views; menuNeedsUpdate rebuilds them on the next open.
        for item in menu.items { item.view = nil }
    }

    @objc private func occlusionChanged() {
        model.barVisible = item.button?.window?.occlusionState.contains(.visible) ?? true
        render()
    }

    private func isAvailable(_ metric: Metric) -> Bool {
        // Desktops have no battery; don't show an empty section for it.
        metric != .battery || model.readout.latest.battery != nil
    }

    private func hosted(_ view: some View) -> NSMenuItem {
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let item = NSMenuItem()
        item.view = host
        return item
    }

    private static let activityMonitor = "com.apple.ActivityMonitor"

    @objc private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.activityMonitor) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(model: model)
    }
}
