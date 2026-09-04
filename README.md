# SysPulse

**English** | [Русский](README.ru.md) | [Português](README.pt.md)

Current version: **0.9.0** — see [Releases](../../releases) and the [CHANGELOG](CHANGELOG.md).

<img src="docs/icon.png" width="96" align="right" alt="SysPulse icon">

A tiny macOS utility that always shows **how your Mac is doing right now** — CPU load per core, memory of every kind and free disk space, live in a small floating window and in the menu bar.

Made for one simple purpose: keeping an eye on the machine without opening Activity Monitor. A permanent, glanceable answer to "is something eating my CPU / RAM / disk?" that sits on top of whatever you are working on.

## What it looks like

| Normal | Compact | Memory breakdown | Contrast |
|:---:|:---:|:---:|:---:|
| <img src="docs/screenshot-normal.png" width="200" alt="Floating window: CPU per-core bars, memory bar, disks"> | <img src="docs/screenshot-compact.png" width="158" alt="Compact window: same rows, smaller fonts and bars"> | <img src="docs/screenshot-details.png" width="200" alt="Memory breakdown: app, wired, compressed, cached, free, swap, pressure"> | <img src="docs/screenshot-contrast.png" width="200" alt="Contrast mode: white background, dark text"> |

The semi-transparent floating window over a desktop; the same numbers live in the menu bar. Screenshots are rendered offscreen with fake data by `scripts/make-screenshots.sh` — no real machine state involved.

## Features

- **Floating window** — a small semi-transparent panel. Drag it anywhere; the position is remembered. If the display it sits on is unplugged, it moves to the one you are working on rather than staying out of sight.
- **One menu, two ways in** — right-click the window (or tap it with two fingers) and the same menu the menu bar icon shows drops down right below it. Nothing is reachable from only one of them, and everything stays reachable even when a crowded menu bar hides the icon. The left button is left alone for dragging.
- **CPU, per core** — one bar per logical core plus the overall percentage, with performance and efficiency cores set apart by a gap and named on hover. On a machine with many cores the strip widens so the bars stay readable instead of thinning to a hairline, and every bar is exactly the same width.
- **GPU load** — read straight from the system, no permissions and no `powermetrics`. Apple Silicon reports one figure for the whole GPU, so there is no per-core breakdown to show.
- **Memory of every kind** — one segmented bar with used / total next to it: blue for app memory, orange for wired, violet for compressed, neutral gray for the file cache, and the empty tail is what is free. Colour here says *which kind*, not *how much*, and the steps are validated for colour-blind separation and contrast in both light and dark. Turn on the breakdown to see every kind as numbers, plus swap and the system's memory-pressure level; hovering the RAM label reports that level at any time.
- **Hover to learn** — hovering a segment of the memory bar names it and gives its size; hovering a row of the breakdown explains what that kind of memory actually is and what it is for, down to what Normal, Warning and Critical pressure mean. Handy if you have ever wondered why a healthy Mac shows almost no free memory.
- **Free disk space** — a row per mounted local volume with the used fraction as a bar and the free space in figures; hover the bar for how much is used and the volume's full name. On APFS and HFS+ the figure matches Finder's, purgeable snapshot space included; on exFAT and FAT — what most external drives arrive formatted as — it falls back to the plain free-space count, which is the only one those filesystems keep. The hover tip also names the filesystem — APFS, ExFAT, Mac OS Extended — which is what decided how that free space was counted. Click a volume's bar to open it in Finder, and eject an external one with the button at the end of its row; that column appears only while there is something to eject. Hide the volumes you don't care about in settings.
- **Folder sizes** — track any folders you like: add them in Folders by typing a path or picking one in Finder, give each a scan interval (never, or every minute up to once a day), and their sizes join the panel as a block of their own, under a "Folders" heading that carries the total of all of them. A button on the heading rescans every folder at once, and each folder has one of its own. Set an alias and the panel shows that instead of the folder name. Hovering a folder reports its path, its scan interval, when it was last measured and the ten largest things inside it — subfolders and loose files ranked together, folders marked with a trailing slash — enough to see what is actually eating the space. Click a folder name to open it in Finder. Results are cached, so a size is on screen the moment the app starts, without waiting for a fresh walk.
- **Load colors** — bars run green → amber → red as a metric fills up, so a busy core or a full disk catches the eye without reading a single number.
- **Menu bar line** — CPU load by default, with memory and disk available too; the readings use fixed-width digits so the neighbouring menu bar icons never shuffle, and the tooltip always carries the full summary. Switch all three off and a small icon takes their place, so the menu never becomes unreachable while the panel is hidden.
- **Update rate** — 0.5, 1, 2 or 5 seconds. Disk space is polled separately and rarely, because it changes slowly and costs more to read.
- **Pick your metrics** — every section (CPU, per-core bars, memory, breakdown, disks) is a toggle; the window shrinks to exactly what you left on.
- **Compact mode** — an even smaller window: smaller fonts, thinner bars, tighter rows.
- **Opacity slider** — one slider in UI settings drives the window look from fully transparent to solid black; the text color adapts along the way so it always stays readable.
- **Contrast mode** — a toggle in UI settings inverts the color scheme: the background goes from transparent to white instead of black, and the text adapts the opposite way.
- **Left or right alignment** — right alignment mirrors every row (value, bar, label) and keeps the window's right edge fixed, growing leftward. Handy when the window sits near the right screen edge.
- **Always on top** decides two things at once, because they belong together. On: the panel floats above everything and appears on every desktop of its display, fullscreen apps included. Off: it orders like an ordinary window, can be covered, and stays on the single desktop where you left it — a window that hides under others has no business following you across desktops.
- **Everything is remembered** — chosen metrics, hidden volumes, window position, compact mode, alignment, opacity and visibility all survive app restarts.
- **Launch at login** — toggle in the menu (uses the system `SMAppService`).
- **Update check** — once a day SysPulse asks GitHub whether a newer release is out. If one is, the top line of the menu says so and opens the release page; it never downloads or replaces anything by itself. Check by hand any time, or turn the automatic check off entirely.
- **11 languages** — English (default), Русский, Español, Deutsch, Français, Italiano, Português (Brasil), Português (Portugal), 中文, 日本語, 한국어. Switchable from the menu.

## Plans

- **Nesting-aware folder totals** — when one tracked folder sits inside another, its bytes are currently counted twice: the "Folders" heading simply adds every folder up. The plan is to work out which folders contain which and count the shared space once, so the total is the space actually occupied rather than the sum of the rows.
- **Scroll to a newly added folder** — "Add folder" appends an empty row at the bottom of the list, and once the list is taller than the window that row lands out of sight, so the button looks as if it did nothing at all. Adding a folder should scroll the list down to it.
- **Sort the folder list** — folders appear in the panel in the order they were added, and that is the only order there is. A choice between sorting by size, by name, or by the order added would let the biggest ones rise to the top, which is usually the reason for watching them at all.
- **History and a chart** — free disk space and folder sizes are measured every few minutes and every reading is then thrown away. Kept in a small local log, the same numbers become a line you can read at a glance: whether a disk is filling steadily or lost 40 GB overnight, and which tracked folder was the one that grew. The log would stay on the machine, like everything else the app records.

## Privacy

SysPulse makes exactly one kind of network request: once a day it asks GitHub whether a newer release exists. Nothing about you is sent — GitHub sees an IP address and the app's name and version, the same as any browser opening the releases page — and you can switch the check off in **Updates → Check automatically**.

Everything else is local: the app reads its own machine's counters through public macOS APIs and keeps your settings in its own preferences. No accounts, no analytics, no telemetry, and nothing about your files or your machine leaves it.

## Install (prebuilt)

1. Download `SysPulse.zip` from the [Releases](../../releases) page and unzip it.
2. Move `SysPulse.app` to `/Applications`.
3. First launch: the app is not notarized, so macOS blocks a normal double-click. On **macOS 15 Sequoia** try to open it once, then go to **System Settings → Privacy & Security** and press **Open Anyway** — Apple removed the old Control-click bypass in Sequoia. On **macOS 13 and 14**, right-click the app → **Open** → **Open** still works. On any version, removing the quarantine flag in Terminal does the job:

   ```sh
   xattr -dr com.apple.quarantine /Applications/SysPulse.app
   ```

4. Look for the readings in your menu bar (if you don't see them, your menu bar may be full — Cmd-drag other icons to make room). Either way the floating window shows up on first launch, and right-clicking it opens the same menu.

Requires macOS 13 Ventura or later. No special permissions are needed.

## Build from source

Requirements: macOS 13+, Xcode Command Line Tools (`xcode-select --install`). No Xcode project needed — it's a plain Swift Package.

```sh
git clone https://github.com/igorpronin/SysPulse.git
cd SysPulse
./build-app.sh
ditto build/SysPulse.app /Applications/SysPulse.app
```

`build-app.sh` compiles a release binary with SwiftPM, wraps it into an `.app` bundle with the icon (regenerated by `scripts/make-icon.sh` if missing), and ad-hoc signs it. The app version is taken from `Sources/SysPulse/Version.swift` and shown in the About dialog.

Dev variant with extra info in the About dialog: `./build-app.sh -dev`.

## License

MIT — see [LICENSE](LICENSE).

## How it works

- **CPU** — `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` gives cumulative tick counters per logical core; load is the difference between two samples (user + system + nice against the total), so the first sample after launch only sets the baseline.
- **Memory** — `host_statistics64(HOST_VM_INFO64)` in Activity Monitor's terms: app memory is anonymous pages minus purgeable, plus wired and compressed pages; used = app + wired + compressed. The file cache and free memory are reported separately, swap comes from `vm.swapusage` and the pressure level from `kern.memorystatus_vm_pressure_level`.
- **Disks** — `volumeAvailableCapacityForImportantUsage` for every mounted local browsable volume, which is exactly what Finder shows.
- **Folders** — one walk of the file tree per scan, adding up the space each file actually occupies on disk (the figure `du` reports) and attributing it to the first-level subfolder it sits in. Walks run one at a time in the background, off the main thread; adding a folder inside Desktop, Documents or Downloads makes macOS ask for permission the first time, and a folder that cannot be read is reported as such rather than as zero. Memory is counted in binary gigabytes and disks in decimal ones, matching how macOS itself reports each.
- The window is a borderless, non-activating `NSPanel` at floating level hosting a SwiftUI view — clicking it never steals focus from your current app.
