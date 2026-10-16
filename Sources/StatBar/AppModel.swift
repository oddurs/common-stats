import Foundation
import Observation
import StatKit

@MainActor
@Observable
final class AppModel {
    private(set) var readout = Readout()
    /// False while the item can't be seen: behind the camera housing,
    /// collapsed by a menu bar manager, or under a full-screen app.
    var barVisible = true
    var layout: BarLayout {
        didSet {
            guard layout != oldValue else { return }
            save()
            if layout.interval != oldValue.interval, running { monitor.start(interval: interval) }
            onUpdate?()
        }
    }

    @ObservationIgnored var onUpdate: (() -> Void)?
    @ObservationIgnored private var monitor: Monitor!
    @ObservationIgnored private var running = false
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let key = "layout"

    init() {
        layout = Self.load(from: defaults)
        monitor = Monitor { [weak self] snapshot in
            guard let self else { return }
            readout.ingest(snapshot)
            onUpdate?()
        }
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.monitor.start(interval: self.interval)
            }
        }
    }

    /// The configured interval, doubled in Low Power Mode: the user has
    /// asked the Mac to do less, and that includes us.
    var interval: TimeInterval {
        layout.interval * (ProcessInfo.processInfo.isLowPowerModeEnabled ? 2 : 1)
    }

    func start() {
        running = true
        monitor.start(interval: interval)
    }

    func stop() {
        running = false
        monitor.stop()
    }

    private static func load(from defaults: UserDefaults) -> BarLayout {
        guard let data = defaults.data(forKey: key) else { return .standard }
        do {
            return try JSONDecoder().decode(BarLayout.self, from: data)
        } catch {
            // Unreadable settings are replaced, not fatal; the user sees the defaults and can reconfigure.
            NSLog("Common Stats: discarding unreadable layout: \(error)")
            return .standard
        }
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(layout), forKey: Self.key)
        } catch {
            NSLog("Common Stats: could not save layout: \(error)")
        }
    }
}
