#!/bin/bash
# Renders README screenshots (docs/) offscreen with fake data.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p tmp

swiftc \
    Sources/SysPulse/Version.swift \
    Sources/SysPulse/SystemMonitor.swift \
    Sources/SysPulse/Localization.swift \
    Sources/SysPulse/Folders.swift \
    Sources/SysPulse/Tooltip.swift \
    Sources/SysPulse/PanelButton.swift \
    Sources/SysPulse/ContentView.swift \
    Sources/SysPulse/SettingsView.swift \
    Sources/SysPulse/AppDelegate.swift \
    scripts/screenshots/main.swift \
    -o tmp/syspulse-render-screens

tmp/syspulse-render-screens docs

# Иконка для README
sips -z 256 256 -s format png assets/AppIcon.icns --out docs/icon.png >/dev/null
echo "written: docs/icon.png"
