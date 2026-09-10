import AppKit
import Combine

// Отслеживание размера произвольных папок. В отличие от трёх основных метрик,
// это не мгновенное показание, а обход дерева файлов: он стоит дорого, поэтому
// результат кэшируется на диск и переживает перезапуск, а частоту обхода
// пользователь задаёт сам — вплоть до «не обновлять».

enum ScanInterval: Int, CaseIterable, Codable, Sendable {
    case never = 0
    case minute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case hour = 3600
    case day = 86_400

    var key: L10nKey {
        switch self {
        case .never: return .scanNever
        case .minute: return .scanMinute
        case .fiveMinutes: return .scan5Minutes
        case .tenMinutes: return .scan10Minutes
        case .hour: return .scanHourly
        case .day: return .scanDaily
        }
    }
}

struct TrackedFolder: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var path: String
    var alias: String = ""
    var interval: ScanInterval = .tenMinutes

    var name: String { URL(fileURLWithPath: path).lastPathComponent }

    /// В окошке показываем псевдоним, если он задан, иначе имя папки.
    var title: String { alias.isEmpty ? name : alias }
}

struct FolderScan: Codable, Equatable, Sendable {
    struct Child: Codable, Equatable, Sendable {
        var name: String
        var size: UInt64
        /// Optional, чтобы кэш, записанный до появления поля, продолжал читаться:
        /// синтезированный декодер не подставляет значения по умолчанию, и одна
        /// новая обязательная переменная обнулила бы весь сохранённый кэш.
        var directory: Bool?

        var isDirectory: Bool { directory ?? true }
    }

    var size: UInt64 = 0
    var children: [Child] = []   // десять самых крупных элементов внутри
    var scannedAt: Date
    var failed = false           // папку не прочитать: удалена или нет доступа
}

// MARK: - Обход дерева

enum FolderScanner {
    /// Один проход по дереву: и полный размер, и вклад каждого элемента первого
    /// уровня — из него берётся десятка самых крупных. В неё идут и папки (со
    /// всем содержимым), и файлы, лежащие прямо в корне: крупный файл рядом с
    /// папками — такая же причина занятого места, прятать его нет смысла.
    /// Размер считается по выделенному на диске месту, как в Finder.
    static func scan(path: String) -> FolderScan {
        let manager = FileManager.default
        let root = URL(fileURLWithPath: path).standardizedFileURL
        var scan = FolderScan(scannedAt: Date())

        guard let entries = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            scan.failed = true
            return scan
        }
        // Тип каждого элемента первого уровня: по нему потом решаем, показывать
        // ли имя со слэшем, и отличаем «свой» элемент от чужого пути.
        var isDirectory: [String: Bool] = [:]
        for entry in entries {
            isDirectory[entry.lastPathComponent] =
                (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        ]
        guard let walker = manager.enumerator(at: root, includingPropertiesForKeys: keys) else {
            scan.failed = true
            return scan
        }

        let rootDepth = root.pathComponents.count
        var perEntry: [String: UInt64] = [:]
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }
            let size = UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            scan.size += size
            // Файл засчитывается в тот элемент первого уровня, внутри которого
            // лежит; файл прямо в корне — сам себе элемент.
            let parts = url.standardizedFileURL.pathComponents
            if parts.count > rootDepth {
                let top = parts[rootDepth]
                if isDirectory[top] != nil {
                    perEntry[top, default: 0] += size
                }
            }
        }

        scan.children = perEntry
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { FolderScan.Child(name: $0.key, size: $0.value, directory: isDirectory[$0.key]) }
        return scan
    }
}

// MARK: - Хранилище

@MainActor
final class FolderTracker: ObservableObject {
    /// История размеров: своё хранилище, потому что у неё своя жизнь на диске
    /// (JSON в Application Support) и свой срок хранения — кэш обхода помнит
    /// только последнее измерение, история помнит все.
    let history = HistoryStore()

    @Published private(set) var folders: [TrackedFolder] = [] {
        didSet {
            saveFolders()
            guard !frozen else { return }
            history.syncTracked(folders)
        }
    }
    @Published private(set) var scans: [String: FolderScan] = [:] { didSet { saveScans() } }
    @Published private(set) var scanning: Set<UUID> = []

    // Обход последователен: параллельные обходы дерева только мешают друг другу
    // на диске, а показания всё равно не срочные.
    private let queue = DispatchQueue(label: "local.syspulse.folders", qos: .utility)
    private var timer: Timer?
    private var frozen = false

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "TrackedFolders"),
           let stored = try? JSONDecoder().decode([TrackedFolder].self, from: data) {
            folders = stored
        }
        if let data = defaults.data(forKey: "FolderScans"),
           let stored = try? JSONDecoder().decode([String: FolderScan].self, from: data) {
            scans = stored
        }
    }

    func scan(for folder: TrackedFolder) -> FolderScan? { scans[folder.id.uuidString] }

    func isScanning(_ folder: TrackedFolder) -> Bool { scanning.contains(folder.id) }

    /// Сумма по всем отслеживаемым папкам — показывается напротив заголовка блока.
    var totalSize: UInt64 {
        folders.reduce(0) { $0 + (scan(for: $1)?.size ?? 0) }
    }

    var isScanningAny: Bool { !scanning.isEmpty }

    func rescanAll() {
        for folder in folders { rescan(folder) }
    }

    // MARK: - Список папок

    /// Путь годится, если он существует и это папка. Возвращает нормализованный
    /// путь (с раскрытой тильдой) — его и храним, чтобы «~/Downloads» и
    /// «/Users/me/Downloads» не жили в списке как две разные записи.
    static func validPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        return expanded
    }

    /// Добавляет или обновляет запись. Ключ — id строки в окне настроек, а не
    /// путь: пока человек правит путь, запись остаётся той же, и накопленный
    /// кэш обхода не теряется.
    func upsert(id: UUID, path: String, alias: String, interval: ScanInterval) {
        if let index = folders.firstIndex(where: { $0.id == id }) {
            let changed = folders[index].path != path
            folders[index].path = path
            folders[index].alias = alias
            folders[index].interval = interval
            if changed {
                scans.removeValue(forKey: id.uuidString)
                rescan(folders[index])
            }
        } else {
            let folder = TrackedFolder(id: id, path: path, alias: alias, interval: interval)
            folders.append(folder)
            rescan(folder)
        }
    }

    func remove(id: UUID) {
        folders.removeAll { $0.id == id }
        scans.removeValue(forKey: id.uuidString)
        // Убрал сам пользователь — историю сносим вместе с записью. Это
        // сознательно отличается от автоматического снятия с наблюдения в
        // pruneMissingFolders: там папка могла всего лишь уехать с
        // отмонтированным томом, и историю ей ещё продолжать.
        history.forget(id: id)
    }

    func setAlias(_ alias: String, for folder: TrackedFolder) {
        update(folder) { $0.alias = alias.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func setInterval(_ interval: ScanInterval, for folder: TrackedFolder) {
        update(folder) { $0.interval = interval }
    }

    private func update(_ folder: TrackedFolder, _ change: (inout TrackedFolder) -> Void) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        change(&folders[index])
    }

    // MARK: - Сканирование

    func start() {
        guard !frozen else { return }
        // Раз в 15 секунд смотрим, у какой папки подошёл срок. Один общий таймер
        // вместо таймера на папку: сроки грубые, от минуты и больше.
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanDueFolders() }
        }
        pruneMissingFolders()
        scanDueFolders()
    }

    /// Папку удалили — убираем её из списка молча. Спрашивать не о чем:
    /// отслеживать несуществующее нечего, а запись с прочерком только мешает.
    private func pruneMissingFolders() {
        let gone = folders.filter { Self.validPath($0.path) == nil }
        guard !gone.isEmpty else { return }
        for folder in gone { scans.removeValue(forKey: folder.id.uuidString) }
        folders.removeAll { folder in gone.contains { $0.id == folder.id } }
    }

    private func scanDueFolders() {
        pruneMissingFolders()
        let now = Date()
        for folder in folders where folder.interval != .never {
            let due = scan(for: folder).map {
                now.timeIntervalSince($0.scannedAt) >= Double(folder.interval.rawValue)
            } ?? true
            if due { rescan(folder) }
        }
    }

    func rescan(_ folder: TrackedFolder) {
        guard !frozen, !scanning.contains(folder.id) else { return }
        scanning.insert(folder.id)
        let id = folder.id
        let path = folder.path
        queue.async { [weak self] in
            let result = FolderScanner.scan(path: path)
            Task { @MainActor in
                guard let self else { return }
                self.scans[id.uuidString] = result
                self.scanning.remove(id)
                // История пополняется на КАЖДОМ успешном обходе — и по
                // расписанию, и по кнопке: это единственное место, куда
                // приходит результат, и оба пути ведут сюда. Неудачный обход не
                // записываем: нулём в графике он читался бы как «папка
                // опустела», а не «папку не удалось прочесть».
                guard !result.failed else { return }
                self.history.record(size: result.size, for: folder, at: result.scannedAt)
            }
        }
    }

    // MARK: - Сохранение

    private func saveFolders() {
        guard !frozen, let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: "TrackedFolders")
    }

    // Кэш обходов переживает перезапуск: размер виден сразу, не дожидаясь
    // нового обхода, а по времени последнего обхода считается следующий срок.
    private func saveScans() {
        guard !frozen, let data = try? JSONEncoder().encode(scans) else { return }
        UserDefaults.standard.set(data, forKey: "FolderScans")
    }

    // Только для оффскрин-рендера скриншотов README.
    func setScreenshotState(folders: [TrackedFolder], scans: [String: FolderScan]) {
        frozen = true
        self.folders = folders
        self.scans = scans
    }
}
