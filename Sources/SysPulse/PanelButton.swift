import AppKit
import SwiftUI

/// Кликабельная накладка для плавающей панели.
///
/// Обычная SwiftUI-кнопка здесь не годится: панель неактивирующаяся и никогда
/// не становится ключевой, а по умолчанию первый клик в неключевое окно уходит
/// на его активацию, а не в контрол. Отсюда `acceptsFirstMouse` — он и делает
/// клик рабочим с первого раза. Заодно перехватываем mouseDown, иначе нажатие
/// на кнопку начнёт таскать саму панель (isMovableByWindowBackground).
struct PanelButton: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.action = action
        return view
    }

    func updateNSView(_ view: ClickView, context: Context) {
        view.action = action
    }

    final class ClickView: NSView {
        var action: (() -> Void)?
        private var pressed = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { pressed = true }

        override func mouseUp(with event: NSEvent) {
            defer { pressed = false }
            // Сработать только если и нажали, и отпустили внутри кнопки.
            guard pressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            action?()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}
