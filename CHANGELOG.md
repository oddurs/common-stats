# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-15

### Added

- Menu bar item with CPU, GPU, memory, network, disk activity, storage, and battery. Each can show a value, a history graph, a gauge, or a combination, in a user-chosen order.
- Dropdown menu with per-metric detail: CPU user and system time, per-core load grouped by efficiency and performance clusters, Activity Monitor's memory breakdown and pressure, rates per interface, free space, and battery status.
- Settings: style and order for each item, labels, density, update interval, and open at login.
- Locale-aware number formatting and VoiceOver descriptions.
- Lower power use: drawing pauses while the item is hidden, sampling halves in Low Power Mode, and sampling stops while the displays sleep.

[Unreleased]: https://github.com/oddurs/statbar/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/oddurs/statbar/releases/tag/v0.1.0
