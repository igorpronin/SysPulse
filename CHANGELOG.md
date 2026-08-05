# Changelog

All notable changes to SysPulse are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org).

## [0.1.0] — 2026-08-05

First release.

### Added
- Floating always-on-top window with live CPU, memory and disk readings, on every desktop and over fullscreen apps; draggable, position remembered.
- CPU load per logical core (one bar each) plus the overall percentage, sampled from cumulative tick counters.
- Memory as a segmented bar (app, wired, compressed, file cache) with used / total, an optional breakdown of every kind of memory including free memory, swap and the system memory-pressure level, and a warning dot when pressure is not normal.
- Free disk space per mounted local volume, matching the figure Finder shows; individual volumes can be hidden.
- Load colors (green → amber → red) on every bar.
- Menu bar line with CPU (memory and disk optional), fixed-width digits so neighbouring icons stay put; full summary in the icon's tooltip.
- Update interval of 0.5, 1, 2 or 5 seconds; disk space polled separately on a slower timer.
- Per-section toggles, compact mode, contrast mode, opacity slider with auto-adapting text color, left/right alignment.
- Metrics settings and UI settings windows; "Open Activity Monitor" in the menu.
- Clicking the floating window opens the menu bar menu right below it, so the app stays fully controllable when a crowded menu bar hides the status icon; right-click keeps a shorter context menu.
- Launch at login, 10 UI languages, no network access and no special permissions.

[0.1.0]: https://github.com/igorpronin/macos-sys-monitor/releases/tag/v0.1.0
