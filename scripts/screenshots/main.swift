// Renders README screenshots offscreen with fake data (no real system metrics involved).
// Built by scripts/make-screenshots.sh together with the app sources.
import AppKit
import SwiftUI

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs"
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    L10n.shared.lang = "en"

    let gb: UInt64 = 1_073_741_824
    let fakeCPU = CPULoad(
        perCore: [0.18, 0.62, 0.34, 0.91, 0.12, 0.47, 0.08, 0.29],
        total: 0.38
    )
    let fakeMemory = MemoryUsage(
        total: 16 * gb,
        app: 5 * gb + gb / 5,
        wired: 2 * gb + gb / 10,
        compressed: gb + gb / 2,
        cached: 3 * gb,
        free: 4 * gb + gb / 5,
        swapUsed: gb / 2,
        swapTotal: 2 * gb,
        pressureRaw: MemoryPressure.normal.rawValue
    )
    let fakeFolders = [
        TrackedFolder(path: "/Users/you/Projects", alias: "", interval: .tenMinutes),
        TrackedFolder(path: "/Users/you/Movies", alias: "Media", interval: .hour),
    ]
    let fakeScans: [String: FolderScan] = [
        fakeFolders[0].id.uuidString: FolderScan(
            size: 24_500_000_000,
            children: [
                .init(name: "node_modules", size: 9_800_000_000),
                .init(name: "archive", size: 6_100_000_000),
                .init(name: "build", size: 3_400_000_000),
            ],
            scannedAt: Date(timeIntervalSince1970: 1_770_000_000)
        ),
        fakeFolders[1].id.uuidString: FolderScan(
            size: 112_000_000_000,
            children: [.init(name: "Raw", size: 88_000_000_000)],
            scannedAt: Date(timeIntervalSince1970: 1_770_000_000)
        ),
    ]
    let fakeVolumes = [
        VolumeUsage(id: "/", name: "Macintosh HD", isRoot: true, total: 994_662_584_320,
                    free: 312_400_000_000, format: "APFS", isExternal: false),
        // Второй том нарочно внешний: только у такого есть стрелка извлечения,
        // и на снимках README её должно быть видно.
        VolumeUsage(id: "/Volumes/Backup", name: "Backup", isRoot: false, total: 2_000_000_000_000,
                    free: 640_000_000_000, format: "ExFAT", isExternal: true),
    ]

    // Композиция вью на градиентном «обое», чтобы была видна полупрозрачность
    @MainActor func render<V: View>(_ view: V, out: String) {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        let panelRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        panelRep.size = size
        host.cacheDisplay(in: host.bounds, to: panelRep)
        let panelImage = NSImage(size: size)
        panelImage.addRepresentation(panelRep)

        let pad: CGFloat = 22
        let bgSize = NSSize(width: size.width + pad * 2, height: size.height + pad * 2)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bgSize.width * scale), pixelsHigh: Int(bgSize.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = bgSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(
            starting: NSColor(calibratedRed: 0.30, green: 0.24, blue: 0.62, alpha: 1),
            ending: NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.68, alpha: 1)
        )!.draw(in: NSRect(origin: .zero, size: bgSize), angle: 35)
        panelImage.draw(in: NSRect(x: pad, y: pad, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()

        let png = rep.representation(using: .png, properties: [:])!
        try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(out)"))
        print("written: \(outDir)/\(out)")
    }

    @MainActor func renderPanel(
        compact: Bool = false, details: Bool = false,
        contrast: Bool = false, opacity: Double = 0.35,
        volumes: [VolumeUsage] = fakeVolumes,
        out: String
    ) {
        let monitor = SystemMonitor()
        monitor.setScreenshotState(cpu: fakeCPU, memory: fakeMemory, volumes: volumes)
        monitor.setScreenshotGPU(0.62)
        let folders = FolderTracker()
        folders.setScreenshotState(folders: fakeFolders, scans: fakeScans)
        monitor.showCPU = true
        monitor.showGPU = true
        monitor.showCores = true
        monitor.showMemory = true
        monitor.showMemoryDetails = details
        monitor.showDisks = true
        monitor.showFolders = true
        monitor.compact = compact
        monitor.contrast = contrast
        monitor.opacity = opacity
        monitor.alignRight = false
        render(ContentView(monitor: monitor, folders: folders), out: out)
    }

    renderPanel(out: "screenshot-normal.png")
    renderPanel(compact: true, out: "screenshot-compact.png")
    renderPanel(details: true, out: "screenshot-details.png")
    renderPanel(contrast: true, opacity: 0.6, out: "screenshot-contrast.png")
}
