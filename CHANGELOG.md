# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Average over 3, 10, or 30 seconds (Settings › General): a trailing time average that steadies the menu bar's numbers, gauges, and graphs. It's applied when drawing, so the stored readings stay exact and the menu always shows them as measured.
- Color settings: graphs, gauges, and legends can follow the system accent color, use a color per metric, or use one of eight system colors. An optional "Color in menu bar" switch carries the color into the menu bar; it is off by default, which keeps the bar monochrome like the system's own icons.

### Changed

- Settings edits the menu bar in place. The preview is the editor: drag items to reorder them, drag one out to the tray below to remove it, drag one in from the tray (or click it) to add it, and click an item to choose how it looks. The item list is gone. VoiceOver users get Move Left, Move Right, and Remove actions on each item.

## [0.3.0] - 2026-10-16

### Changed

- Settings follows the shared Common Tools layout: Items, Appearance, then General with Open at login first, and the version at the foot of the window.

### Added

- A Common Tools section at the end of Settings listing Common Stats, Common Keys, and Common Bar, with Open for the ones installed and Get… for the rest.

## [0.2.1] - 2026-10-16

### Changed

- New app icon, in the blue glass style shared by Common Stats, Common Keys, and Common Bar.

## [0.2.0] - 2026-10-16

### Changed

- StatBar is now called Common Stats. The app installs as `Common Stats.app`; the bundle identifier is unchanged, so settings and the menu bar position carry over.
- The website moved to Common Tools at https://oddurs.github.io/common-tools/stats/, and the repository moved to https://github.com/oddurs/common-stats. The old site at oddurs.github.io/statbar is gone.
- The release download is now `CommonStats.zip` (with `CommonStats.zip.sha256`) instead of `StatBar-<version>.zip`, so https://github.com/oddurs/common-stats/releases/latest/download/CommonStats.zip always fetches the newest build.

## [0.1.0] - 2026-10-15

### Added

- Menu bar item with CPU, GPU, memory, network, disk activity, storage, and battery. Each can show a value, a history graph, a gauge, or a combination, in a user-chosen order.
- Dropdown menu of Control Center–style cards and ring-gauge tiles. It shows CPU user and system time, per-core load grouped by efficiency and performance clusters, Activity Monitor's memory breakdown with a pressure indicator, per-interface network and disk rates, free space, and battery status.
- History graphs drawn with monotone curves, so smoothing never invents a peak. Rate graphs show their scale, and hovering any graph reads back a past value.
- Settings: style and order for each item, labels, density, update interval, and open at login.
- Locale-aware number formatting and VoiceOver descriptions.
- A first-launch notice when the menu bar item is hidden behind the camera housing or a menu bar manager.
- Project website at https://oddurs.github.io/statbar/.
- Lower power use: drawing pauses while the item is hidden, sampling halves in Low Power Mode, and sampling stops while the displays sleep.

[Unreleased]: https://github.com/oddurs/common-stats/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/oddurs/common-stats/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/oddurs/common-stats/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/oddurs/common-stats/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/oddurs/common-stats/releases/tag/v0.1.0
