# SysPulse — notes for Claude

macOS menu bar utility (Swift Package, no Xcode project): a small floating window
with live CPU load per core, memory of every kind and free disk space.
UI/architecture reference: /Users/proninigor/Projects/mac-desktop-map (DeskMap) —
same panel, same settings windows, same build/icon/screenshot scripts. Keep the
two visually and structurally in step: a change in the shared parts of one is
usually worth mirroring in the other.

`./build-app.sh` builds the public variant, `./build-app.sh -dev` builds the owner's
local variant (extra About info via `DEV_BUILD` compile flag). The copy installed
in `/Applications` must always be the `-dev` build.

## README files

`README.md` (English) and `README.ru.md` (Russian) are mirrors of each other. Any
change to one MUST be applied to the other in the same commit. Both keep the
language-switcher links (`**English** | [Русский](README.ru.md)` /
`[English](README.md) | **Русский**`) at the top — do not remove them.

## Languages

The app UI has 10 languages (en, ru, es, de, fr, it, pt, zh, ja, ko) in
`Sources/SysPulse/Localization.swift`. Every new UI string MUST be added to ALL
ten language tables at once — `t(_:)` force-unwraps the English table, and a
missing key elsewhere silently falls back to English. The dev-only About suffix
(`devSuffix`) exists in en/ru only; that is intentional.

## Versioning — MANDATORY

The version lives in ONE place: `Sources/SysPulse/Version.swift` (`AppInfo.version`).
`build-app.sh` extracts it into Info.plist; the About dialog shows it.

**Every functional change MUST bump the version** (semver: patch for fixes,
minor for features). Never ship a functional change with an unchanged version.

Every version bump MUST, in the same commit, also update:

1. `CHANGELOG.md` — a new entry describing the changes (Keep a Changelog
   format, with the release link at the bottom of the file);
2. the "Current version" line in BOTH `README.md` and `README.ru.md`.

Release procedure: bump + changelog + readme → commit & push → `git tag vX.Y.Z`
→ push the tag → `./build-app.sh` (public) → `ditto -c -k --keepParent
build/SysPulse.app dist/SysPulse.zip` → verify `strings` show no dev/private
data → `gh release create vX.Y.Z dist/SysPulse.zip` → rebuild `-dev` back into
build/ and relaunch (dist/ is gitignored; the zip ships only via Releases).

## Temporary files

Use the project-local `tmp/` folder (gitignored) for any temporary files —
screenshots, scratch scripts, intermediate artifacts. Do NOT use the global
`/tmp` or other locations outside the project.

## Reading the metrics

All three metrics come from public APIs — the app needs no permissions, and it
must stay that way.

- **CPU**: `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` returns cumulative
  32-bit tick counters per logical core. Load is the delta of two samples, so
  the first sample only sets the baseline and returns nil; deltas use `&-`
  because the counters wrap. Always `vm_deallocate` the returned array.
- **Memory**: `host_statistics64(HOST_VM_INFO64)`, in Activity Monitor's terms —
  app = internal − purgeable, used = app + wired + compressed, cached =
  external + purgeable. Swap from `vm.swapusage`, pressure level from
  `kern.memorystatus_vm_pressure_level` (1 normal / 2 warning / 4 critical).
  Verified against `vm_stat` and `memory_pressure`.
- **Disks**: `volumeAvailableCapacityForImportantUsage` over
  `mountedVolumeURLs`, filtered to browsable local volumes — the same number
  Finder shows. Sampled on a separate 5 s timer off the main thread, because
  volume queries can hit the disk; the list is sorted (boot volume first, then
  by name) so rows never swap places between polls.
- Units follow macOS: memory in binary GB, disks in decimal GB (`Fmt.mem` vs
  `Fmt.disk`). Do not unify them.

## Panel layout

Column widths (label / bar / value) are fixed constants in `ContentView`, and
the per-core bars share the fixed bar width. This is deliberate: the readings
change every second, and a content-driven width would make the window pulse.
Value text is `.monospacedDigit()` for the same reason. When the window's height
does change (a section toggled, a volume mounted), `windowDidResize` keeps the
top edge — and with right alignment the right edge — pinned in place.

A click on the panel pops up `statusItem.menu` itself (not a copy), so the
`menuWillOpen` delegate refreshes the checkmarks the same way for both entry
points — the panel must stay usable when a full menu bar hides the status icon.
The popup point is in the content view's coordinates, and that view is an
`NSHostingView`, which is flipped: "below the panel" is `bounds.maxY + 6`, not
`-6`. Getting this wrong makes the menu cover the panel instead of dropping
under it.

## Menu bar diagnostics

`swift scripts/menubar-list.swift` lists every menu bar item, including the ones
macOS pushed off a crowded bar (they stay in the window list with
`isOnscreen = false`). Status item icons are windows at level 25
(`kCGStatusWindowLevel`); the script filters to `y == 0` and menu-bar height,
because the same level also carries those apps' dropdown panels. Needs no
permissions. Use it when "the icon does not appear" — usually it exists and is
simply the leftmost item on a full bar.

## Screenshots

`scripts/make-screenshots.sh` renders `docs/*.png` offscreen from the real views
with fake data via `SystemMonitor.setScreenshotState(...)`, which also freezes
polling — no real machine state ends up in the README images. Re-render whenever
the panel's look changes.
