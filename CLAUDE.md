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

There are THREE mirrors of the same document: `README.md` (English),
`README.ru.md` (Russian) and `README.pt.md` (European Portuguese). Any change to
one MUST be applied to ALL THREE in the same commit — a new feature bullet, a
version line, a Plans entry, a reworded sentence. English is the source of
truth; when the three drift, bring the others back to it rather than the reverse.

Each keeps its language-switcher line at the top, with the current language in
bold and the other two as links — do not remove or reorder them:

    **English** | [Русский](README.ru.md) | [Português](README.pt.md)
    [English](README.md) | **Русский** | [Português](README.pt.md)
    [English](README.md) | [Русский](README.ru.md) | **Português**

`README.pt.md` is European Portuguese (pt-PT): *ficheiro*, *ecrã*, *percentagem*,
*predefinição*, *aplicação*, "está a fazer" rather than "está fazendo", and the
pt-PT macOS names — Definições do Sistema, Privacidade e Segurança, Abrir Mesmo
Assim, Secretária / Documentos / Transferências. It describes the pt-PT build of
the UI, which since 0.9.0 is a language of its own — keep the two in the same
variant, and never let a pt-BR word from `Localization.swift` drift into it.
Watch for the false friends in particular: *apelido* is a surname in Portugal,
so the alias field is `Nome alternativo` in both the table and this README.

## Languages

The app UI has 11 languages (en, ru, es, de, fr, it, pt, pt-PT, zh, ja, ko) in
`Sources/SysPulse/Localization.swift`. Every new UI string MUST be added to ALL
eleven language tables at once — `t(_:)` force-unwraps the English table, and a
missing key elsewhere silently falls back to English. The dev-only About suffix
(`devSuffix`) exists in en/ru only; that is intentional.

`pt` is Brazilian and `pt-PT` European Portuguese; they are separate tables
because the variants differ in vocabulary (ficheiro / arquivo), in grammar
("a analisar" against "analisando") and in false friends. When a string names a
macOS command or a Finder verb, take the wording from the system rather than
from memory: the localized `.strings` under
`/System/Library/CoreServices/Finder.app/Contents/Resources/<lang>.lproj/` are
the source the eject terms (推出, 取り出す, 추출) came from.

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

## Folder tracking

`Folders.swift` is separate from `SystemMonitor` on purpose: the three metrics
above are instant counters, a folder size is a walk of the file tree. One pass
of `FolderScanner.scan` produces both the total and each first-level
subdirectory's share, so the five largest come free; verified against `du -sk`
to the byte. Walks run one at a time on a utility queue — parallel walks only
fight each other over the disk — and a folder already being scanned is never
queued again, so a slow walk cannot pile up behind a fast interval. Budget
roughly 25 s for 375 GB when choosing defaults.

Rows in the Folders window are DRAFTS: a folder reaches the saved list only
once its path checks out (`FolderTracker.validPath` — exists and is a
directory). An empty or wrong path outlines the field and keeps the row out of
the settings entirely, and the window rebuilds its content on every open so
yesterday's draft never comes back. A folder that vanishes from disk is dropped
by `pruneMissingFolders` without asking — note this also fires for a folder on
an unmounted volume.

Results are cached to UserDefaults with their timestamp: a size is on screen at
launch without waiting, and the next scan is due from when the last one really
ran, not from app start. `FolderTracker.frozen` (screenshot mode) blocks both
scanning and saving.

NOTE: this is the one part of the app that can trigger a macOS privacy prompt —
only when the user themselves adds a protected folder (Desktop, Documents,
Downloads). Denied access surfaces as `noAccess`, never as a crash or a zero.
The three core metrics still need no permissions and must stay that way.

## Folder size history

`History.swift` records sizes; `HistoryView.swift` draws them. ONE `HistoryStore`
serves the whole app — `AppDelegate` owns it and injects it into both
`SystemMonitor` and `FolderTracker`, because the manifest is shared and must
have a single writer. The store is JSON under
`~/Library/Application Support/SysPulse/history/`: `index.json` maps each
subject (id, path, alias, tracked flag, `kind` of "folder" or "volume") to its
own file of `{"t": ISO8601, "s": bytes}` pairs. Dates are ISO 8601 and keys are short on
purpose — the files are meant to be read and edited by hand, and there are
thousands of points in them, not millions. No SQLite; that was a deliberate call.

`compact` bounds the files: the last two days keep every measurement, older
points thin to the last one in each hour, nothing older than 100 days survives.
Without it a folder scanned every minute reaches 130k points a quarter (~5 MB),
and even the quarter chart cannot draw a thousand.

Recording hangs off the single place a scan result lands (`FolderTracker.rescan`
completion), so the timer path and the manual button both go through it. Failed
scans are NOT recorded: a zero would read as "the folder emptied out".

Deletion is asymmetric on purpose. `FolderTracker.remove(id:)` — the user's own
action — calls `history.forget`, which deletes the file. `pruneMissingFolders`
does not: it also fires for a folder on an unmounted volume, and an unplugged
drive must not destroy months of history. `touchIndex` adopts an untracked
entry with the same path, so re-adding a folder continues its old chart under a
new UUID.

Volumes are recorded hourly by `recordVolume`, called from every disk poll — the
five-second poll would otherwise write constantly, so the store itself holds the
cadence, measured from the last recorded point rather than the top of the clock
(a restart mid-hour must not break the series). The interval is deliberately not
a setting.

Only BUILT-IN volumes are recorded, decided by `volumeIsInternal` — the same
signal the eject button uses. `volumeIsRemovable` and `volumeIsEjectable`
describe media that comes out of a drive and are false for a plain USB disk, so
they are the wrong keys. A removable drive's line cannot distinguish "filled up"
from "was unplugged", which is why they are skipped entirely. A volume's history
key is `volumeUUIDString` (see `VolumeUsage.historyKey`); the mount path is not
stable, since a name collision produces "/Volumes/Name 1". FAT keeps no UUID, so
the path is the fallback and `safeName` scrubs the slashes out of the filename.

The chosen chart range is remembered per key in UserDefaults (`HistoryRanges`) —
a display setting, so it does not belong in the data files. If the remembered
range is no longer available, `HistoryChartView` falls back to the longest
available one rather than to Day, which would throw the intent away.

A built-in volume's chart opens by clicking its LABEL in the panel, not an icon:
disk rows live in the fixed label/bar/value grid, so an icon column would appear
on every row and widen the panel by 18pt for a button that belongs on one.

`HistoryStore(directory:)` exists for tests. Overriding `HOME` does NOT work —
`NSHomeDirectory()` reads the passwd entry for a non-sandboxed process and
ignores the variable; a test that assumed otherwise wrote into the owner's real
history. Point the seam at a scratch directory instead.

Chart rules that are not free choices: the size axis does not start at zero (a
300 GB folder growing 40 GB overnight would be a flat line otherwise), and
BECAUSE of that there is no area fill — a filled area under a shifted axis
misstates magnitude. Ranges unlock only once the data reaches past the previous,
shorter range, so no button ever opens an empty plot. The line uses the same
validated `Palette.app` steps as the memory bar, picked by `colorScheme`.

## Update check — the only network code

`UpdateChecker.swift` is the sole place in the app that touches the network:
one anonymous GET to the GitHub releases API, at most once a day, guarded by a
timestamp in UserDefaults so the hourly timer cannot turn into hourly requests.
GitHub rejects requests without a `User-Agent`, so that header is required, not
decoration. Keep `parse` and `isNewer` `nonisolated` — they run on the URLSession
callback, off the main actor.

Do NOT add downloading or self-replacement. The app is ad-hoc signed and not
notarized; replacing itself would land straight in Gatekeeper. Finding a new
version opens the release page and stops there.

If you ever add a second network call, the privacy section of BOTH READMEs has
to change with it — it currently promises exactly this one request and nothing
else, and that promise is the reason the check can be switched off.

## Hover tooltips

Do NOT use `.help(_:)` or `NSView.toolTip` on the panel. `NSToolTipManager` only
shows system tooltips for the *active* application, and SysPulse is an
`LSUIElement` agent whose panel never becomes key — those tooltips are silently
dead. `Tooltip.swift` replaces them: hover is caught by an `NSTrackingArea` with
`.activeAlways` (SwiftUI's own `.onHover` defaults to key-window-only tracking),
and the text is drawn in an app-owned `NSPanel` at status-bar level with
`ignoresMouseEvents` on — without that the tip covers the segment, the tracking
area gets `mouseExited`, and the tip flickers away. Attach one with `.hoverTip(_:)`.

A hover region lives where the view is LAID OUT, not where it is drawn: never
position something with `.offset` and expect `.hoverTip` on it to work (the
memory segments were built that way once and all four regions ended up stacked
at the left edge). Two further rules came out of that same bug, both learned the
hard way:

- Do NOT use `.inVisibleRect` on the tracking area. It makes AppKit measure the
  *visible* part of the view, and inside a SwiftUI container clipped to a capsule
  that measurement is wrong for elements near the ends — regions drift or vanish.
  Set the rect from `bounds` explicitly and refresh it in `setFrameSize`, since
  the readings resize these views every second.
- For a bar made of several parts, use ONE region across the whole bar and work
  out the part from the pointer's x fraction (`.hoverTip(at:)`), reusing the same
  arithmetic that draws it. Per-segment overlays a few pixels wide are fragile,
  and the drawn boundary and the hover boundary can then never disagree.

Verify a change here by dumping each view's `trackingAreas`: `area.rect` must
equal `bounds`, and the count must match the number of regions you intended.

Two AppKit traps live in that file, both already fixed: sizing the tip with
`NSHostingView.fittingSize` under a width limit returns nonsense (a 992 px tall
window), so the content is plain AppKit; and `contentView`'s frame must be read
BEFORE it is assigned to the panel, because AppKit stretches it to the window.

## Colors

Two different jobs, two different scales — do not mix them up. CPU and disk bars
encode a *magnitude*, so they use the green→amber→red ramp in `loadColor`. The
memory bar encodes *which kind of memory*, so it uses the categorical `Palette`
(blue / orange / violet, plus a fixed neutral gray for the file cache, which is
reclaimable and must not read as "used"). Each has a light step for Contrast
mode and a dark step for the normal panel.

Those steps are not free choices. They were validated with the `dataviz`
skill's `validate_palette.js` against both surfaces: worst adjacent colour-blind
ΔE 24.7 light / 26.0 dark (threshold 8) and contrast ≥ 3:1. Blue+aqua and
darker greens were tried and rejected — they fail either CVD separation against
orange or contrast on the light surface. If you change a hue, re-run the
validator for BOTH modes before committing.

## Panel layout

Column widths (label / bar / value) are fixed constants in `ContentView`, and
the per-core bars share the fixed bar width. This is deliberate: the readings
change every second, and a content-driven width would make the window pulse.
Value text is `.monospacedDigit()` for the same reason. When the window's height
does change (a section toggled, a volume mounted), `windowDidResize` keeps the
top edge — and with right alignment the right edge — pinned in place.

The app has exactly ONE menu. A right-click on the panel pops up
`statusItem.menu` itself (not a copy), so the `menuWillOpen` delegate refreshes
the checkmarks the same way for both entry points — the panel must stay usable
when a full menu bar hides the status icon. Do not give the panel its own
context menu: two menus on one window drifted apart and confused the owner.
Anything new goes into `rebuildMenu()` — but which metrics the panel shows lives
ONLY in the Metrics settings window; a "Metrics" submenu duplicating it existed
briefly and the owner removed it. Checkmark items bound to a `Bool` on
`SystemMonitor` are built with `flagItem(_:_:)`, which registers them in
`flagItems` so one action and one refresh loop serve them all. The left button
is deliberately untouched — the panel is dragged with it via
`isMovableByWindowBackground`.
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
