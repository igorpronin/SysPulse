import AppKit
import SwiftUI
import Combine
import ServiceManagement

#if DEV_BUILD
let projectFolder = "/Users/proninigor/Projects/macos-sys-monitor"
#endif

final class FloatingPanel: NSPanel {
    var onRightClick: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // ЛКМ не перехватываем вообще: окно таскается за фон штатным AppKit-механизмом
    // (isMovableByWindowBackground). ПКМ — он же тап двумя пальцами — открывает
    // то самое единственное меню приложения; своего контекстного меню у окошка
    // нет, два разных меню на одном окошке только путали. Событие доходит сюда по
    // цепочке ответчиков, потому что у NSHostingView внутри не задано своё menu.
    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var panelMenuItem: NSMenuItem!
    private var onTopMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    // Пункты-галочки, привязанные к Bool-настройкам монитора: метрики, состав
    // строки в меню-баре, компактный режим. Один массив — одно действие на всех
    // и одно место, где состояния освежаются перед показом меню.
    private var flagItems: [(item: NSMenuItem, key: ReferenceWritableKeyPath<SystemMonitor, Bool>)] = []
    private var alignLeftMenuItem: NSMenuItem!
    private var alignRightMenuItem: NSMenuItem!
    private var metricsSettingsWindow: NSWindow?
    private var foldersSettingsWindow: NSWindow?
    private var uiSettingsWindow: NSWindow?
    private var lastPanelFrame: NSRect = .zero
    private let monitor = SystemMonitor()
    private let folders = FolderTracker()
    private var cancellables = Set<AnyCancellable>()

    private var panelVisible: Bool {
        get { UserDefaults.standard.object(forKey: "ShowFloatingPanel") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "ShowFloatingPanel") }
    }

    private var panelOnTop: Bool {
        get { UserDefaults.standard.object(forKey: "PanelOnTop") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "PanelOnTop") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "…"
        rebuildMenu()

        // objectWillChange эмитит на willSet — обрабатываем на следующем тике main
        // queue, когда значение уже записано. Метрики меняются раз в интервал опроса,
        // поэтому title в меню-баре обновляется вместе с ними.
        monitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        L10n.shared.$lang
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        if panelVisible {
            panel.orderFrontRegardless()
        }
        monitor.start()
        folders.start()
        updateStatusItem()
    }

    // MARK: - Плавающее окошко

    private func setupPanel() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = panelOnTop ? .floating : .normal
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        // Полоска памяти определяет сегмент под курсором по mouseMoved —
        // окно должно эти события принимать.
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let host = NSHostingController(rootView: ContentView(monitor: monitor, folders: folders))
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        panel.setContentSize(host.view.fittingSize)

        if !panel.setFrameUsingName("SysPulsePanel"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: f.maxX - panel.frame.width - 16,
                y: f.maxY - panel.frame.height - 16
            ))
        }
        panel.setFrameAutosaveName("SysPulsePanel")
        panel.delegate = self
        panel.onRightClick = { [weak self] in self?.showMainMenu() }

        self.panel = panel
        clampPanelToScreen()
        lastPanelFrame = panel.frame
    }

    /// ПКМ по окошку — то же меню, что и у значка в меню-баре, прямо под окошком.
    /// Меню-бар бывает забит, и тогда macOS прячет значок: окошко остаётся
    /// единственным входом в настройки. Меню одно и то же (`statusItem.menu`),
    /// поэтому menuWillOpen освежает галочки одинаково в обоих случаях.
    func showMainMenu() {
        guard let view = panel.contentView, let menu = statusItem?.menu else { return }
        // Точка задаётся в координатах вью, а внутри окошка живёт NSHostingView —
        // он перевёрнутый (y растёт вниз), поэтому «под окошком» считается
        // по-разному. Без этого меню накрывает само окошко.
        let below = view.isFlipped
            ? NSPoint(x: 0, y: view.bounds.maxY + 6)
            : NSPoint(x: 0, y: -6)
        menu.popUp(positioning: nil, at: below, in: view)
    }

    // MARK: - Окна настроек

    func openMetricsSettings() {
        if metricsSettingsWindow == nil {
            let host = NSHostingController(rootView: MetricsSettingsView(monitor: monitor))
            let window = NSWindow(contentViewController: host)
            window.title = L10n.shared.t(.metricsSettings).replacingOccurrences(of: "…", with: "")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            metricsSettingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        metricsSettingsWindow?.makeKeyAndOrderFront(nil)
    }

    func openFoldersSettings() {
        if foldersSettingsWindow == nil {
            let host = NSHostingController(rootView: FoldersSettingsView(folders: folders))
            let window = NSWindow(contentViewController: host)
            window.title = L10n.shared.t(.foldersSettings).replacingOccurrences(of: "…", with: "")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            foldersSettingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        foldersSettingsWindow?.makeKeyAndOrderFront(nil)
    }

    func openUISettings() {
        if uiSettingsWindow == nil {
            let host = NSHostingController(rootView: UISettingsView(monitor: monitor))
            let window = NSWindow(contentViewController: host)
            window.title = L10n.shared.t(.uiSettings).replacingOccurrences(of: "…", with: "")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            uiSettingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        uiSettingsWindow?.makeKeyAndOrderFront(nil)
    }

    func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
            // Панель ушла из-под курсора — mouseExited уже не придёт.
            TooltipPanel.shared.cancel()
        }
        panelMenuItem?.state = visible ? .on : .off
    }

    func setPanelOnTop(_ onTop: Bool) {
        panelOnTop = onTop
        panel.level = onTop ? .floating : .normal
        if panelVisible { panel.orderFrontRegardless() }
        onTopMenuItem?.state = onTop ? .on : .off
    }

    var isPanelOnTop: Bool { panelOnTop }

    @objc private func toggleOnTop() {
        setPanelOnTop(!panelOnTop)
    }

    // Контент меняет размер (включили разбивку памяти, появился том) —
    // не даём окну уходить за край экрана.
    private func clampPanelToScreen() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        var origin = panel.frame.origin
        origin.x = min(max(origin.x, v.minX + 4), v.maxX - panel.frame.width - 4)
        origin.y = min(max(origin.y, v.minY + 4), v.maxY - panel.frame.height - 4)
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
    }

    // MARK: - Меню в меню-баре

    /// Пункт-галочка поверх Bool-настройки монитора: сам ставит текущее состояние
    /// и регистрируется в flagItems, чтобы одно действие обслуживало их все.
    private func flagItem(
        _ title: String, _ key: ReferenceWritableKeyPath<SystemMonitor, Bool>
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(toggleFlag(_:)), keyEquivalent: "")
        item.target = self
        item.state = monitor[keyPath: key] ? .on : .off
        flagItems.append((item, key))
        return item
    }

    private func rebuildMenu() {
        let l10n = L10n.shared
        let menu = NSMenu()
        menu.autoenablesItems = false
        flagItems = []

        let activityItem = NSMenuItem(title: l10n.t(.activityMonitor), action: #selector(openActivityMonitorAction), keyEquivalent: "")
        activityItem.target = self
        menu.addItem(activityItem)

        menu.addItem(NSMenuItem.separator())

        let metricsSettingsItem = NSMenuItem(title: l10n.t(.metricsSettings), action: #selector(openMetricsSettingsAction), keyEquivalent: ",")
        metricsSettingsItem.target = self
        menu.addItem(metricsSettingsItem)

        let foldersItem = NSMenuItem(title: l10n.t(.foldersSettings), action: #selector(openFoldersSettingsAction), keyEquivalent: "")
        foldersItem.target = self
        menu.addItem(foldersItem)

        let uiSettingsItem = NSMenuItem(title: l10n.t(.uiSettings), action: #selector(openUISettingsAction), keyEquivalent: "")
        uiSettingsItem.target = self
        menu.addItem(uiSettingsItem)

        panelMenuItem = NSMenuItem(title: l10n.t(.floatingPanel), action: #selector(togglePanel), keyEquivalent: "")
        panelMenuItem.target = self
        panelMenuItem.state = panelVisible ? .on : .off
        menu.addItem(panelMenuItem)

        onTopMenuItem = NSMenuItem(title: l10n.t(.alwaysOnTop), action: #selector(toggleOnTop), keyEquivalent: "")
        onTopMenuItem.target = self
        onTopMenuItem.state = panelOnTop ? .on : .off
        menu.addItem(onTopMenuItem)

        menu.addItem(flagItem(l10n.t(.compactPanel), \SystemMonitor.compact))

        let alignItem = NSMenuItem(title: l10n.t(.alignMenu), action: nil, keyEquivalent: "")
        let alignMenu = NSMenu()
        alignMenu.autoenablesItems = false
        alignLeftMenuItem = NSMenuItem(title: l10n.t(.alignLeft), action: #selector(selectAlignLeft), keyEquivalent: "")
        alignLeftMenuItem.target = self
        alignLeftMenuItem.state = monitor.alignRight ? .off : .on
        alignMenu.addItem(alignLeftMenuItem)
        alignRightMenuItem = NSMenuItem(title: l10n.t(.alignRight), action: #selector(selectAlignRight), keyEquivalent: "")
        alignRightMenuItem.target = self
        alignRightMenuItem.state = monitor.alignRight ? .on : .off
        alignMenu.addItem(alignRightMenuItem)
        alignItem.submenu = alignMenu
        menu.addItem(alignItem)

        // Подменю «что дублировать в меню-баре»: те же три метрики.
        let menuBarItem = NSMenuItem(title: l10n.t(.menuBarMenu), action: nil, keyEquivalent: "")
        let menuBarMenu = NSMenu()
        menuBarMenu.autoenablesItems = false
        for (title, keyPath) in [
            (l10n.t(.cpu), \SystemMonitor.menuBarCPU),
            (l10n.t(.memory), \SystemMonitor.menuBarMemory),
            (l10n.t(.disk), \SystemMonitor.menuBarDisk),
        ] {
            menuBarMenu.addItem(flagItem(title, keyPath))
        }
        menuBarItem.submenu = menuBarMenu
        menu.addItem(menuBarItem)

        loginMenuItem = NSMenuItem(title: l10n.t(.launchAtLogin), action: #selector(toggleLoginItem), keyEquivalent: "")
        loginMenuItem.target = self
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginMenuItem)

        let langItem = NSMenuItem(title: l10n.t(.language), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        langMenu.autoenablesItems = false
        for (code, name) in L10n.languages {
            let item = NSMenuItem(title: name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = l10n.lang == code ? .on : .off
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        let aboutItem = NSMenuItem(title: l10n.t(.about), action: #selector(showAboutAction), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: l10n.t(.quit), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Строка в меню-баре

    private func updateStatusItem() {
        let l10n = L10n.shared
        var parts: [String] = []
        if monitor.menuBarCPU {
            parts.append("\(l10n.t(.cpu)) \(Fmt.percentPadded(monitor.cpu.total))")
        }
        if monitor.menuBarMemory {
            parts.append("\(l10n.t(.memory)) \(Fmt.percentPadded(monitor.memory.usedFraction))")
        }
        if monitor.menuBarDisk, let volume = monitor.visibleVolumes.first ?? monitor.volumes.first {
            parts.append("\(l10n.t(.disk)) \(Fmt.disk(volume.free))")
        }
        guard let button = statusItem?.button else { return }
        if parts.isEmpty {
            // Все метрики в меню-баре выключены — показываем иконку, а не имя
            // приложения: значок должен остаться на месте, иначе при скрытой
            // панели приложение будет нечем открыть. Столбики перекликаются с
            // иконкой приложения, template — сам подстраивается под тему.
            button.attributedTitle = NSAttributedString(string: "")
            if button.image == nil {
                let image = NSImage(
                    systemSymbolName: "chart.bar.fill", accessibilityDescription: AppInfo.name
                )
                image?.isTemplate = true
                button.image = image
            }
        } else {
            button.image = nil
            // Моноширинные цифры: без них значок меняет ширину на каждом обновлении
            // и утягивает за собой соседние значки меню-бара.
            button.attributedTitle = NSAttributedString(
                string: parts.joined(separator: " · "),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(
                        ofSize: NSFont.systemFontSize, weight: .regular
                    )
                ]
            )
        }
        button.toolTip = tooltip
    }

    // Полная сводка — в подсказке значка, даже если в меню-баре включена одна метрика.
    private var tooltip: String {
        let l10n = L10n.shared
        let memory = monitor.memory
        var lines = [
            "\(l10n.t(.cpu)): \(Fmt.percent(monitor.cpu.total))",
            "\(l10n.t(.memory)): \(Fmt.memNumber(memory.used)) / \(Fmt.mem(memory.total))"
                + " · \(l10n.t(.pressure)): \(pressureTitle)",
        ]
        for volume in monitor.visibleVolumes {
            let name = volume.isRoot ? l10n.t(.disk) : volume.name
            lines.append("\(name): \(Fmt.disk(volume.free)) \(l10n.t(.free)) / \(Fmt.disk(volume.total))")
        }
        return lines.joined(separator: "\n")
    }

    private var pressureTitle: String {
        let l10n = L10n.shared
        switch monitor.memory.pressure {
        case .normal: return l10n.t(.pressureNormal)
        case .warning: return l10n.t(.pressureWarning)
        case .critical: return l10n.t(.pressureCritical)
        }
    }

    // MARK: - Действия меню

    @objc private func togglePanel() { setPanelVisible(!panelVisible) }

    @objc private func toggleFlag(_ sender: NSMenuItem) {
        guard let entry = flagItems.first(where: { $0.item === sender }) else { return }
        monitor[keyPath: entry.key].toggle()
        sender.state = monitor[keyPath: entry.key] ? .on : .off
        updateStatusItem()
    }

    @objc private func selectAlignLeft() { setAlignRight(false) }

    @objc private func selectAlignRight() { setAlignRight(true) }

    private func setAlignRight(_ value: Bool) {
        monitor.alignRight = value
        alignLeftMenuItem?.state = value ? .off : .on
        alignRightMenuItem?.state = value ? .on : .off
    }

    @objc private func openMetricsSettingsAction() { openMetricsSettings() }

    @objc private func openFoldersSettingsAction() { openFoldersSettings() }

    @objc private func openUISettingsAction() { openUISettings() }

    @objc private func openActivityMonitorAction() { openActivityMonitor() }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        L10n.shared.lang = code
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = L10n.shared.t(.loginItemError)
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func showAboutAction() { showAbout() }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - About

    func showAbout() {
        let l10n = L10n.shared
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = AppInfo.name
        alert.addButton(withTitle: "OK")
        let versionLine = "\(l10n.t(.version)) \(AppInfo.version)"
        #if DEV_BUILD
        alert.informativeText = l10n.t(.aboutText) + "\n\n" + versionLine + "\n\n"
            + l10n.devSuffix().replacingOccurrences(of: "{path}", with: projectFolder)
        alert.addButton(withTitle: l10n.t(.openProjectFolder))
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: projectFolder))
        }
        #else
        alert.informativeText = l10n.t(.aboutText) + "\n\n" + versionLine
        alert.runModal()
        #endif
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel,
              let panel = self.panel, lastPanelFrame.height > 0 else { return }
        var origin = panel.frame.origin
        // Строк стало больше или меньше — держим верхний край на месте (у macOS
        // начало координат внизу, иначе окно «прыгает» вверх при росте).
        origin.y = lastPanelFrame.maxY - panel.frame.height
        // При правом выравнивании так же держим правый край: окно растёт влево.
        if monitor.alignRight {
            origin.x = lastPanelFrame.maxX - panel.frame.width
        }
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
        clampPanelToScreen()
        lastPanelFrame = panel.frame
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        lastPanelFrame = panel.frame
    }
}

extension AppDelegate: NSMenuDelegate {
    // Состояния могли поменять извне (Системные настройки, другая копия меню).
    func menuWillOpen(_ menu: NSMenu) {
        TooltipPanel.shared.isSuppressed = true
        loginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        onTopMenuItem?.state = panelOnTop ? .on : .off
        panelMenuItem?.state = panelVisible ? .on : .off
        alignLeftMenuItem?.state = monitor.alignRight ? .off : .on
        alignRightMenuItem?.state = monitor.alignRight ? .on : .off
        for entry in flagItems {
            entry.item.state = monitor[keyPath: entry.key] ? .on : .off
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        TooltipPanel.shared.isSuppressed = false
    }
}
