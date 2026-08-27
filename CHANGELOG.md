# Changelog

All notable changes to SysPulse are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org).

## [0.6.0] — 2026-08-27

### Changed
- "Always on top" now governs desktops as well as stacking order. On, the panel
  appears on every desktop of its display, as before. Off, it stays on the one
  desktop where it was left — previously it followed you everywhere while still
  hiding under other windows, which served no one.

### Fixed
- Unplugging the display the panel sits on used to leave it stranded outside the
  visible area: nothing in the app watched for a change of screen configuration.
  It now moves to the display you are working on — the one holding the frontmost
  window. There is no setting for this; a window off the edge of the world is
  never what anyone wanted.

## [0.5.0] — 2026-08-27

### Added
- GPU load, as its own row. It comes from the IORegistry, so it needs no
  permissions and no `powermetrics`; the row is simply absent on hardware that
  reports nothing. Apple Silicon publishes a single figure for the whole GPU —
  there is no per-core breakdown to show, however many GPU cores the chip has.
- Performance and efficiency cores are told apart: the strip separates the two
  groups with a gap and names their counts on hover. Which cores are which comes
  from `hw.perflevel*` at runtime, so a 10 + 4 machine splits correctly without
  anything hardcoded.

### Changed
- The per-core strip widens on machines with many cores instead of squeezing the
  bars. At 14 cores a bar used to come out 4.6 pt wide, and 3 pt in compact mode
  — a dot rather than a bar. Every row widens together, so the columns stay in
  line and only the panel grows.
- Bar width is now derived from the bar rather than the strip, so the division
  always comes out exact. Left to SwiftUI, the remainder went to a couple of
  bars and made them half a point wider than their neighbours — one device pixel
  on a retina screen, and enough to look crooked.

### Not done
- Neural Engine load. macOS reports it only through `powermetrics`, which needs
  root, and a proper privileged helper needs a Developer ID signature this app
  does not have. The remaining route — an admin password prompt plus a permanent
  root process, for a figure that is power draw rather than utilisation — was
  not worth it for an app that otherwise asks for nothing.

## [0.4.0] — 2026-08-27

### Added
- Update check. Once a day SysPulse asks GitHub whether a newer release exists;
  when one does, the top line of the menu says so and opens the release page.
  There is a manual "Check now" and a switch to turn the automatic check off —
  it is on by default. Versions are compared part by part, so 0.10.0 correctly
  counts as newer than 0.9.0.
- The app deliberately does not download or install anything by itself: it is
  not notarized, and replacing itself would run straight into Gatekeeper.

### Changed
- The privacy section of both READMEs now describes that request instead of
  claiming the app never touches the network.

## [0.3.2] — 2026-08-05

### Changed
- A folder's hover tip now lists the ten largest things inside it instead of
  five, and files sitting loose in the folder are ranked alongside the
  subfolders rather than being left out — a single huge file is just as good an
  answer to "what is taking the space". Folders are marked with a trailing
  slash so the two are told apart at a glance.

## [0.3.1] — 2026-08-05

### Changed
- Folders are a block of their own in the panel now, set off by a hairline rule
  and headed by "Folders" with the total size of every tracked folder beside it.
  The folders themselves are listed under it in the smaller type the memory
  breakdown uses, so a glance tells a section from its contents.
- Rescan buttons moved into the panel itself: one per folder, plus one on the
  heading that refreshes all of them at once. They go dim while a walk is in
  progress. The buttons accept the first click even though the panel never takes
  focus, so a single click is enough.

## [0.3.0] — 2026-08-05

### Added
- Folder size tracking. A new "Folders" window lets you add any folders, give
  each an alias and a scan interval — never, every minute, 5, 10, an hour or a
  day — and rescan any of them by hand. Their sizes appear in the panel as their
  own rows, showing the alias when one is set.
- Hovering a folder in the panel reports its path, its scan interval, when it
  was last measured and the five largest subfolders inside it, so it is clear
  what is taking the space.
- Scan results are cached on disk, so sizes show up immediately at launch and
  the next scan is due from when the last one actually ran.
- "Folders" is a section of its own in Metrics settings and can be switched off
  like the others.

### Changed
- Sizes below a gigabyte now read in MB or KB instead of rounding to "0 GB",
  which matters for subfolders and nearly full volumes alike.

## [0.2.7] — 2026-08-05

### Removed
- The "Metrics" submenu. It repeated, checkmark for checkmark, what the Metrics
  settings window already offers; which sections the panel shows is chosen in
  one place now.

## [0.2.6] — 2026-08-05

### Changed
- With every menu bar reading switched off, the status item now shows a small
  bar-chart icon instead of the app's name. The icon keeps the menu reachable
  when the panel is hidden too, and it is a template image, so it follows the
  menu bar's own light and dark appearance. Turn any reading back on and the
  figures take the icon's place.

## [0.2.5] — 2026-08-05

### Fixed
- A tooltip left on screen when the menu opened stayed there. An open menu takes
  the mouse events for itself, so the panel never hears that the pointer left.
  Tooltips are now dismissed and held back for as long as a menu is open — the
  delayed ones too, since the main queue keeps running inside the menu's tracking
  loop. Hiding the panel dismisses them as well.

## [0.2.4] — 2026-08-05

### Fixed
- Hovering the memory bar only answered over the first two segments, and the
  regions did not line up with what was drawn. Each segment carried its own
  hover overlay tracked `.inVisibleRect`, which measures the *visible* part of a
  view — and inside a container clipped to a capsule that measurement is wrong
  for the segments near the ends. The bar now has a single hover region across
  its whole width and works out which segment is under the pointer from its
  position, using the same arithmetic that draws the segments, so the two cannot
  disagree.
- Hovering the empty tail of the memory bar now explains free memory, which had
  no hover target at all before.

## [0.2.3] — 2026-08-05

### Changed
- The hairline border around the bars is gone — it read as clutter without
  adding legibility. The brighter empty track stays and does the same job on
  its own.

## [0.2.2] — 2026-08-05

### Fixed
- Hovering a segment of the memory bar did nothing. The segments were positioned
  with `.offset`, which moves what is drawn but not where the view lives, so all
  four hover regions sat stacked at the left edge of the bar. They are laid out
  properly now, each hover region exactly under the segment you see.

### Added
- Hovering a disk bar reports how much is used — in figures, as a share, and
  with the volume's full name, which the narrow label often has to truncate.

### Changed
- Free space is easier to see: every bar now has a hairline border, and the
  empty track is brighter. Both the memory tail and a nearly full disk read as
  a definite amount of room left rather than as background.

## [0.2.1] — 2026-08-05

### Fixed
- The hover tooltips shipped in 0.2.0 never appeared. `NSToolTipManager` only
  shows system tooltips for the active application, and SysPulse is a background
  agent whose panel never becomes key, so `.help(…)` was silently dead. Hovering
  is now tracked by an `.activeAlways` tracking area and the text is drawn in the
  app's own panel — both work regardless of which app is in front.

### Changed
- The memory-pressure dot next to the RAM row is gone. It sat outside the
  columns and read as a speck of dust rather than a warning; the pressure level
  now lives in the RAM label's hover tip, together with what each level means.

## [0.2.0] — 2026-08-05

### Added
- Hovering a segment of the memory bar names it and gives its size.
- Hovering a row of the memory breakdown explains what that kind of memory is
  and what it is for — including what Normal, Warning and Critical memory
  pressure actually mean. The panel doubles as a short lesson on how macOS
  handles RAM.
- Each breakdown row carries a colored dot matching its segment in the bar.

### Changed
- The memory bar now uses a categorical palette — blue for app memory, orange
  for wired, violet for compressed, a neutral gray for the file cache — instead
  of three opacity steps of one load color, which were indistinguishable over a
  translucent panel. Colour encodes *which kind* here, not *how much*, so a
  fill-level gradient was the wrong tool; CPU and disk keep theirs. The steps
  are validated for both surfaces: worst adjacent colour-blind ΔE 24.7 light /
  26.0 dark against a threshold of 8, contrast ≥ 3:1 in both modes.
- The file cache no longer blends into the empty track, and segments are
  separated by a hairline gap carved out of the segment, so the bar still tells
  the truth about how much memory is free.

## [0.1.2] — 2026-08-05

### Changed
- The floating window is called a panel in the menu now: "Show window" became
  "Floating panel" and "Compact window" became "Compact panel", in all ten
  languages. Both are checkmark items describing a state, so naming the thing
  reads better than commanding it — and the menu no longer calls one object by
  two different words.

## [0.1.1] — 2026-08-05

### Changed
- One menu instead of two. The floating window no longer has its own context
  menu — right-clicking it (or a two-finger tap) opens the same menu as the
  menu bar icon, so the two never disagree again. The metric toggles that only
  existed in the context menu moved into a new "Metrics" submenu.
- Left-clicking the window no longer opens anything; the left button is back to
  plain dragging, which is what a floating window is expected to do.

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

[0.6.0]: https://github.com/igorpronin/SysPulse/releases/tag/v0.6.0
[0.5.0]: https://github.com/igorpronin/SysPulse/releases/tag/v0.5.0
[0.4.0]: https://github.com/igorpronin/SysPulse/releases/tag/v0.4.0
[0.3.2]: https://github.com/igorpronin/SysPulse/releases/tag/v0.3.2
[0.3.1]: https://github.com/igorpronin/SysPulse/releases/tag/v0.3.1
[0.3.0]: https://github.com/igorpronin/SysPulse/releases/tag/v0.3.0
[0.2.7]: https://github.com/igorpronin/SysPulse/releases/tag/v0.2.7
[0.2.6]: https://github.com/igorpronin/SysPulse/releases/tag/v0.2.6
[0.2.5]: https://github.com/igorpronin/SysPulse/releases/tag/v0.2.5
[0.2.4]: https://github.com/igorpronin/SysPulse/releases/tag/v0.2.4
[0.2.3]: https://github.com/igorpronin/SysPulse/releases/tag/v0.2.3
[0.2.2]: https://github.com/igorpronin/SysPulse/releases/tag/v0.2.2
[0.2.1]: https://github.com/igorpronin/SysPulse/releases/tag/v0.2.1
[0.2.0]: https://github.com/igorpronin/SysPulse/releases/tag/v0.2.0
[0.1.2]: https://github.com/igorpronin/SysPulse/releases/tag/v0.1.2
[0.1.1]: https://github.com/igorpronin/SysPulse/releases/tag/v0.1.1
[0.1.0]: https://github.com/igorpronin/SysPulse/releases/tag/v0.1.0
