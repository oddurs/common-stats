import AppKit
import StatKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two copies (say, a build folder and /Applications) would draw two bars.
        // The newer one leaves; ordering by launch date then PID means two
        // copies starting at the same instant can't both quit.
        if let id = Bundle.main.bundleIdentifier,
            NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: isOlder)
        {
            NSLog("Common Stats: an older copy is already running; exiting")
            NSApp.terminate(nil)
            return
        }

        model = AppModel()
        statusItem = StatusItemController(model: model)
        model.onUpdate = { [weak statusItem] in statusItem?.render() }
        model.start()
        offerSettingsIfHiddenOnFirstLaunch()

        // Nobody can see the menu bar while the displays sleep; stop waking the CPU for it.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [model] _ in
            MainActor.assumeIsolated { model?.stop() }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [model] _ in
            MainActor.assumeIsolated { model?.start() }
        }
    }

    /// On a notched Mac a new item can land behind the camera housing, and
    /// launching the app then appears to do nothing. The first time only,
    /// if the item isn't visible once the menu bar settles, open Settings,
    /// which explains why and how to make room.
    private func offerSettingsIfHiddenOnFirstLaunch() {
        let key = "launchedBefore"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [model] in
            MainActor.assumeIsolated {
                guard let model, !model.barVisible else { return }
                SettingsWindowController.shared.show(model: model)
            }
        }
    }

    private func isOlder(_ other: NSRunningApplication) -> Bool {
        let me = NSRunningApplication.current
        guard other.processIdentifier != me.processIdentifier, !other.isTerminated else { return false }
        let mine = me.launchDate ?? .distantFuture, theirs = other.launchDate ?? .distantFuture
        return theirs != mine ? theirs < mine : other.processIdentifier < me.processIdentifier
    }

    /// Launching the app again while it runs is the only way back to
    /// Settings if the menu bar item is hidden behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindowController.shared.show(model: model)
        return false
    }
}
