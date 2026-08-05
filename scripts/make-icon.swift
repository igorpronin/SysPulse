// Рисует мастер-PNG иконки 1024×1024. Использование: swift make-icon.swift <out.png>
import AppKit

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Сквиркл с полями по гайдлайнам macOS (иконка занимает ~82% холста)
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: CGFloat(size) - 2 * inset, height: CGFloat(size) - 2 * inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.33, alpha: 1),
    ending: NSColor(calibratedRed: 0.13, green: 0.56, blue: 0.62, alpha: 1)
)!
gradient.draw(in: squircle, angle: 90)

// Столбики загрузки по «ядрам»: разной высоты, последний — «горячий».
let heights: [CGFloat] = [0.34, 0.62, 0.46, 0.86]
let barWidth: CGFloat = 108
let gap: CGFloat = 46
let chartWidth = barWidth * CGFloat(heights.count) + gap * CGFloat(heights.count - 1)
let baseY = rect.minY + 190
let maxHeight = rect.maxY - 190 - baseY
let startX = (CGFloat(size) - chartWidth) / 2

// Дорожки — те же полупрозрачные «полоски», что и в окошке приложения.
for index in 0..<heights.count {
    let trackRect = NSRect(
        x: startX + CGFloat(index) * (barWidth + gap),
        y: baseY,
        width: barWidth,
        height: maxHeight
    )
    let path = NSBezierPath(roundedRect: trackRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
    NSColor.white.withAlphaComponent(0.22).setFill()
    path.fill()
}

for (index, value) in heights.enumerated() {
    let barRect = NSRect(
        x: startX + CGFloat(index) * (barWidth + gap),
        y: baseY,
        width: barWidth,
        height: maxHeight * value
    )
    let path = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
    if index == heights.count - 1 {
        NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.35, alpha: 1).setFill()
    } else {
        NSColor.white.withAlphaComponent(0.92).setFill()
    }
    path.fill()
}

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("written:", CommandLine.arguments[1])
