# SysPulse

**English** | [Русский](README.ru.md)

Current version: **0.1.0** — see [Releases](../../releases) and the [CHANGELOG](CHANGELOG.md).

<img src="docs/icon.png" width="96" align="right" alt="SysPulse icon">

A tiny macOS utility that always shows **how your Mac is doing right now** — CPU load per core, memory of every kind and free disk space, live in a small floating window and in the menu bar.

Made for one simple purpose: keeping an eye on the machine without opening Activity Monitor. A permanent, glanceable answer to "is something eating my CPU / RAM / disk?" that sits on top of whatever you are working on.

## What it looks like

| Normal | Compact | Memory breakdown | Contrast |
|:---:|:---:|:---:|:---:|
| <img src="docs/screenshot-normal.png" width="200" alt="Floating window: CPU per-core bars, memory bar, disks"> | <img src="docs/screenshot-compact.png" width="158" alt="Compact window: same rows, smaller fonts and bars"> | <img src="docs/screenshot-details.png" width="200" alt="Memory breakdown: app, wired, compressed, cached, free, swap, pressure"> | <img src="docs/screenshot-contrast.png" width="200" alt="Contrast mode: white background, dark text"> |

The semi-transparent floating window over a desktop; the same numbers live in the menu bar. Screenshots are rendered offscreen with fake data by `scripts/make-screenshots.sh` — no real machine state involved.

## Features

- **Floating window** — a small semi-transparent panel that stays on top of all windows, on every desktop, even over fullscreen apps. Drag it anywhere; the position is remembered.
- **Click the window for the menu** — clicking the panel opens the same menu as the menu bar icon, right below it, so everything stays reachable even when a crowded menu bar hides the icon. Right-click gives a shorter context menu with the metric toggles.
- **CPU, per core** — one bar per logical core plus the overall percentage. The bars share a fixed width, so the window never changes size as the load moves.
- **Memory of every kind** — one segmented bar (app memory → wired → compressed → file cache) with used / total next to it. Turn on the breakdown to see all of them as numbers, plus free memory, swap and the system's memory-pressure level. A dot next to the row lights up when macOS reports memory pressure.
- **Free disk space** — a row per mounted local volume with the used fraction as a bar and the free space in figures — the same number Finder shows (on APFS it includes purgeable snapshot space). Hide the volumes you don't care about in settings.
- **Load colors** — bars run green → amber → red as a metric fills up, so a busy core or a full disk catches the eye without reading a single number.
- **Menu bar line** — CPU load by default, with memory and disk available too; the readings use fixed-width digits so the neighbouring menu bar icons never shuffle. The tooltip always carries the full summary.
- **Update rate** — 0.5, 1, 2 or 5 seconds. Disk space is polled separately and rarely, because it changes slowly and costs more to read.
- **Pick your metrics** — every section (CPU, per-core bars, memory, breakdown, disks) is a toggle; the window shrinks to exactly what you left on.
- **Compact mode** — an even smaller window: smaller fonts, thinner bars, tighter rows.
- **Opacity slider** — one slider in UI settings drives the window look from fully transparent to solid black; the text color adapts along the way so it always stays readable.
- **Contrast mode** — a toggle in UI settings inverts the color scheme: the background goes from transparent to white instead of black, and the text adapts the opposite way.
- **Left or right alignment** — right alignment mirrors every row (value, bar, label) and keeps the window's right edge fixed, growing leftward. Handy when the window sits near the right screen edge.
- **Always on top** is a separate toggle: with it off, the window orders like a regular window and can be covered by others.
- **Everything is remembered** — chosen metrics, hidden volumes, window position, compact mode, alignment, opacity and visibility all survive app restarts.
- **Launch at login** — toggle in the menu (uses the system `SMAppService`).
- **10 languages** — English (default), Русский, Español, Deutsch, Français, Italiano, Português, 中文, 日本語, 한국어. Switchable from the menu.

## Privacy

SysPulse makes no network requests at all. It only reads its own machine's counters through public macOS APIs, and stores your settings locally in the app's preferences. No accounts, no analytics, nothing leaves your Mac.

## Install (prebuilt)

1. Download `SysPulse.zip` from the [Releases](../../releases) page and unzip it.
2. Move `SysPulse.app` to `/Applications`.
3. First launch: the app is not notarized, so macOS will block a normal double-click. Either **right-click the app → Open → Open**, or remove the quarantine flag in Terminal:

   ```sh
   xattr -dr com.apple.quarantine /Applications/SysPulse.app
   ```

4. Look for the readings in your menu bar (if you don't see them, your menu bar may be full — Cmd-drag other icons to make room). Either way the floating window shows up on first launch, and clicking it opens the same menu.

Requires macOS 13 Ventura or later. No special permissions are needed.

## Build from source

Requirements: macOS 13+, Xcode Command Line Tools (`xcode-select --install`). No Xcode project needed — it's a plain Swift Package.

```sh
git clone <this repo>
cd macos-sys-monitor
./build-app.sh
ditto build/SysPulse.app /Applications/SysPulse.app
```

`build-app.sh` compiles a release binary with SwiftPM, wraps it into an `.app` bundle with the icon (regenerated by `scripts/make-icon.sh` if missing), and ad-hoc signs it. The app version is taken from `Sources/SysPulse/Version.swift` and shown in the About dialog.

Dev variant with extra info in the About dialog: `./build-app.sh -dev`.

## How it works

- **CPU** — `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` gives cumulative tick counters per logical core; load is the difference between two samples (user + system + nice against the total), so the first sample after launch only sets the baseline.
- **Memory** — `host_statistics64(HOST_VM_INFO64)` in Activity Monitor's terms: app memory is anonymous pages minus purgeable, plus wired and compressed pages; used = app + wired + compressed. The file cache and free memory are reported separately, swap comes from `vm.swapusage` and the pressure level from `kern.memorystatus_vm_pressure_level`.
- **Disks** — `volumeAvailableCapacityForImportantUsage` for every mounted local browsable volume, which is exactly what Finder shows. Memory is counted in binary gigabytes and disks in decimal ones, matching how macOS itself reports each.
- The window is a borderless, non-activating `NSPanel` at floating level hosting a SwiftUI view — clicking it never steals focus from your current app.
