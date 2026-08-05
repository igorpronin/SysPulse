// Список всех элементов меню-бара, включая скрытые (не поместившиеся).
// Каждый значок в баре — окно на слое 25; скрытые остаются в списке окон,
// но с isOnscreen = false. Разрешений не требует.
// Запуск: swift scripts/menubar-list.swift
import AppKit

struct Item {
    let x: CGFloat, width: CGFloat, owner: String, onscreen: Bool
}

let screenWidth = NSScreen.main?.frame.width ?? 0
let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []

var items: [Item] = []
for window in windows where (window[kCGWindowLayer as String] as? Int) == 25 {
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    guard let x = bounds["X"] as? CGFloat, let width = bounds["Width"] as? CGFloat,
          let y = bounds["Y"] as? CGFloat, let height = bounds["Height"] as? CGFloat,
          // На слое 25 висят и выпадающие панели этих же приложений — значок
          // всегда прижат к верху экрана и не выше самого меню-бара.
          y == 0, height <= 40, width > 0, width < screenWidth
    else { continue }
    items.append(Item(
        x: x,
        width: width,
        owner: window[kCGWindowOwnerName as String] as? String ?? "?",
        onscreen: (window[kCGWindowIsOnscreen as String] as? Bool) ?? false
    ))
}
items.sort { $0.x < $1.x }

let visible = items.filter(\.onscreen)
let hidden = items.filter { !$0.onscreen }

print("Экран: \(Int(screenWidth)) pt")
print("Видимых: \(visible.count), скрытых: \(hidden.count)\n")
print("  x     ширина  приложение")
print("  ----  ------  -----------------------------")
for item in items {
    print(String(
        format: "  %4.0f  %4.0f    %@%@",
        item.x, item.width, item.owner, item.onscreen ? "" : "   ← СКРЫТ"
    ))
}

if let leftmost = visible.first {
    let used = visible.reduce(0) { $0 + $1.width }
    print("\nЗначки занимают \(Int(used)) pt, крайний левый — \(leftmost.owner) на x=\(Int(leftmost.x)).")
    print("Он же первым уедет за край, когда меню активного приложения станет шире.")
}
