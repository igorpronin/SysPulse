import AppKit
import SwiftUI

// Свои подсказки вместо системных (.help / NSView.toolTip).
// Системные показывает NSToolTipManager, и только для активного приложения —
// а SysPulse фоновое (LSUIElement) и панель никогда не становится ключевой,
// поэтому штатные тултипы на ней молчат. Здесь наведение ловится трекинг-областью
// с .activeAlways, а текст рисуется в собственном окне: и то, и другое работает
// независимо от того, активно приложение или нет.

@MainActor
final class TooltipPanel {
    static let shared = TooltipPanel()

    private var panel: NSPanel?
    private var pending: DispatchWorkItem?
    private var currentText: String?

    /// Пока открыто меню, подсказки не показываем, а показанную убираем. Меню
    /// забирает события мыши себе: mouseExited до панели уже не дойдёт, и
    /// подсказка зависла бы поверх экрана до следующего наведения. Отложенный
    /// показ тоже надо глушить — main queue крутится и в цикле отслеживания меню.
    var isSuppressed = false {
        didSet { if isSuppressed { cancel() } }
    }

    private init() {}

    /// Показать подсказку у курсора. Первая появляется с задержкой, как системная,
    /// а при переходе на соседний сегмент — сразу, иначе она мигала бы.
    /// Тот же текст повторно не перерисовываем: при движении по одному сегменту
    /// событий приходят десятки в секунду.
    func schedule(_ text: String, delay: TimeInterval = 0.35) {
        guard !isSuppressed else { return }
        if panel?.isVisible == true, currentText == text { return }
        pending?.cancel()
        guard panel?.isVisible != true else {
            show(text)
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.show(text) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        currentText = nil
        panel?.orderOut(nil)
    }

    private func show(_ text: String) {
        currentText = text
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let content = makeContent(text)
        // Размер снимаем до присваивания: contentView AppKit растягивает по окну,
        // и после присваивания frame вью — это уже размер окна, а не текста.
        let size = content.frame.size
        panel.setContentSize(size)
        panel.contentView = content
        panel.setFrameOrigin(origin(for: panel.frame.size))
        panel.orderFrontRegardless()
    }

    /// Содержимое собрано на AppKit, а не на SwiftUI: у NSHostingView с
    /// ограничением по ширине fittingSize считается неверно (окно получалось
    /// в тысячу пикселей высотой), а перенос строк в NSTextField предсказуем.
    private func makeContent(_ text: String) -> NSView {
        let padding = NSSize(width: 9, height: 7)
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = 260
        label.setFrameSize(label.fittingSize)

        // Материал .toolTip — тот самый фон, что у системных подсказок:
        // сам подстраивается под светлую и тёмную тему.
        let box = NSVisualEffectView(frame: NSRect(
            x: 0, y: 0,
            width: label.frame.width + padding.width * 2,
            height: label.frame.height + padding.height * 2
        ))
        box.material = .toolTip
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.masksToBounds = true
        label.setFrameOrigin(NSPoint(x: padding.width, y: padding.height))
        box.addSubview(label)
        return box
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Выше плавающей панели, иначе подсказка окажется под ней.
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Подсказка не должна ловить курсор: иначе она перекроет сегмент,
        // трекинг-область получит mouseExited, и подсказка тут же исчезнет.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Справа-снизу от курсора, но так, чтобы целиком помещаться на экране.
    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var point = NSPoint(x: mouse.x + 14, y: mouse.y - size.height - 14)
        guard let visible = screen?.visibleFrame else { return point }
        point.x = min(point.x, visible.maxX - size.width - 4)
        point.x = max(point.x, visible.minX + 4)
        if point.y < visible.minY + 4 {
            point.y = mouse.y + 18  // внизу экрана — показываем над курсором
        }
        point.y = min(point.y, visible.maxY - size.height - 4)
        return point
    }
}

/// Прозрачная накладка, которая только следит за курсором.
private struct HoverTracker: NSViewRepresentable {
    var onHover: ((Bool) -> Void)?
    /// Доля ширины 0…1, где сейчас курсор. Нужна полоскам из нескольких
    /// сегментов: по ней вычисляется, над каким именно сегментом мышь.
    var onMove: ((Double) -> Void)?

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHover = onHover
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHover = onHover
        view.onMove = onMove
    }

    final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?
        var onMove: ((Double) -> Void)?
        private var area: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            // .activeAlways — курсор считается и когда приложение неактивно.
            // С .activeInKeyWindow (по умолчанию у SwiftUI) фоновое приложение
            // наведения не увидит вовсе.
            //
            // Область задаётся явно по bounds. .inVisibleRect брать нельзя:
            // тогда AppKit считает область по ВИДИМОЙ части вью, а внутри
            // SwiftUI-контейнера, обрезанного капсулой, видимая часть у краевых
            // элементов вычисляется неверно — область съезжает или исчезает.
            let created = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                owner: self
            )
            addTrackingArea(created)
            area = created
        }

        // Размер меняется на каждом обновлении показаний — область должна ехать
        // следом, иначе она останется от прошлой раскладки.
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            updateTrackingAreas()
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(true)
            report(event)
        }

        override func mouseMoved(with event: NSEvent) { report(event) }

        override func mouseExited(with event: NSEvent) { onHover?(false) }

        private func report(_ event: NSEvent) {
            guard let onMove, bounds.width > 0 else { return }
            let point = convert(event.locationInWindow, from: nil)
            onMove(min(1, max(0, Double(point.x / bounds.width))))
        }

        // Клики не перехватываем: панель должна оставаться перетаскиваемой,
        // а ПКМ — открывать меню. Трекинг от hitTest не зависит.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension View {
    /// Подсказка при наведении. Замена `.help(_:)`, которая в фоновом
    /// приложении не работает. nil или пустая строка — накладка не ставится вовсе.
    @ViewBuilder
    func hoverTip(_ text: String?) -> some View {
        overlay {
            if let text, !text.isEmpty {
                HoverTracker(onHover: { inside in
                    if inside {
                        TooltipPanel.shared.schedule(text)
                    } else {
                        TooltipPanel.shared.cancel()
                    }
                })
            }
        }
    }

    /// Подсказка для полоски из нескольких частей: одна область наведения на всю
    /// ширину, а нужная часть вычисляется по доле координаты курсора. Так
    /// надёжнее, чем вешать по накладке на каждый сегмент шириной в десяток
    /// пикселей, и границы областей совпадают с нарисованными в точности.
    func hoverTip(at tipForFraction: @escaping (Double) -> String?) -> some View {
        overlay(
            HoverTracker(
                onHover: { inside in
                    if !inside { TooltipPanel.shared.cancel() }
                },
                onMove: { fraction in
                    if let text = tipForFraction(fraction) {
                        TooltipPanel.shared.schedule(text)
                    } else {
                        TooltipPanel.shared.cancel()
                    }
                }
            )
        )
    }
}
