import Combine
import Foundation

// История размеров отслеживаемых папок. Обход дерева уже происходит по
// расписанию — раньше каждый его результат перетирал предыдущий, и вопрос
// «папка растёт или это всегда так было?» оставался без ответа. Здесь каждое
// измерение остаётся на диске, и по нему рисуется график.
//
// Формат нарочно простой: JSON, без SQLite. Общий index.json — это манифест,
// связывающий папку (идентификатор, путь, псевдоним) с её файлом истории; сама
// история лежит отдельным файлом на папку и состоит из пар «дата — размер».
// Файлы читаемы глазами и правятся руками, что для домашней утилиты важнее
// скорости запроса: точек тут тысячи, не миллионы.

struct HistoryPoint: Codable, Equatable, Sendable {
    var date: Date
    var size: UInt64

    // Короткие ключи: точек в файле тысячи, и «t»/«s» вместо полных имён
    // экономят треть объёма при том же содержании.
    enum CodingKeys: String, CodingKey {
        case date = "t"
        case size = "s"
    }
}

/// Манифест: какой файл истории кому принадлежит. Записи снятых с наблюдения
/// папок остаются здесь с `tracked: false` — по ним история подхватывается
/// обратно, если ту же папку добавят снова.
struct HistoryIndex: Codable {
    struct Entry: Codable, Equatable {
        var id: String
        var path: String
        var alias: String
        var file: String
        var tracked: Bool
        var lastSeen: Date
        /// «folder» или «volume». Optional, чтобы манифесты, записанные до
        /// появления томов, продолжали читаться: синтезированный декодер не
        /// подставляет значения по умолчанию, и одно новое обязательное поле
        /// обнулило бы всю накопленную историю.
        var kind: String?

        var isVolume: Bool { kind == "volume" }
    }

    var version = 1
    var updatedAt = Date()
    var folders: [Entry] = []
}

/// Диапазоны графика. Порог разблокировки — это глубина предыдущего, более
/// короткого диапазона: предлагать «за месяц», когда данных всего за три дня,
/// незачем — такой график ничем не отличался бы от недельного, только пустотой
/// на три четверти ширины.
enum HistoryRange: Int, CaseIterable, Identifiable, Sendable {
    case day, week, month, quarter

    var id: Int { rawValue }

    var days: Double {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .quarter: return 92
        }
    }

    var unlockAfterDays: Double {
        switch self {
        case .day: return 0
        case .week: return 1
        case .month: return 7
        case .quarter: return 30
        }
    }

    var key: L10nKey {
        switch self {
        case .day: return .historyDay
        case .week: return .historyWeek
        case .month: return .historyMonth
        case .quarter: return .historyQuarter
        }
    }
}

// Кодировщики создаются на месте, а не живут одним экземпляром: запись идёт с
// фоновой очереди, чтение — с главной, а JSONEncoder не Sendable, и общий на
// двоих он был бы гонкой, которую компилятор не даст даже собрать. Создание
// стоит микросекунды против записи файла.
private func makeHistoryEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    // Даты в ISO 8601, а не числом: файл должен читаться человеком, который
    // заглянул в него без приложения.
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

private func makeHistoryDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

@MainActor
final class HistoryStore: ObservableObject {
    /// Счётчик изменений: открытое окно графика перерисовывается, когда
    /// подоспело новое измерение. Публиковать сами точки незачем — они лежат в
    /// кэше и достаются по идентификатору папки.
    @Published private(set) var revision = 0

    private var index = HistoryIndex()
    private var cache: [String: [HistoryPoint]] = [:]
    private let directory: URL?
    private let io = DispatchQueue(label: "local.syspulse.history", qos: .utility)
    private var frozen = false

    /// `directory` подменяется только в проверочных прогонах. Через переменную
    /// HOME это сделать нельзя: `NSHomeDirectory()` у неизолированного процесса
    /// берёт домашний каталог из записи пользователя и на HOME не смотрит —
    /// проверено ценой записи в настоящую историю владельца.
    init(directory override: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        directory = override ?? support?.appendingPathComponent("SysPulse/history", isDirectory: true)
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("index.json")),
           let stored = try? makeHistoryDecoder().decode(HistoryIndex.self, from: data) {
            index = stored
        }
    }

    // MARK: - Чтение

    func points(for id: UUID) -> [HistoryPoint] { points(for: id.uuidString) }

    /// Точки по ключу, по возрастанию даты. Файл читается один раз за сеанс.
    /// Ключ у папки — её UUID, у тома — UUID файловой системы.
    func points(for key: String) -> [HistoryPoint] {
        if let cached = cache[key] { return cached }
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              let stored = try? makeHistoryDecoder().decode([HistoryPoint].self, from: data)
        else {
            cache[key] = []
            return []
        }
        let sorted = stored.sorted { $0.date < $1.date }
        cache[key] = sorted
        return sorted
    }

    // MARK: - Выбранный диапазон

    /// Диапазон запоминается для каждой папки и тома отдельно: у одной папки
    /// интересна суточная рябь, у другой — квартальный тренд, и сбрасывать
    /// выбор на сутки при каждом открытии значит заставлять переключать заново.
    /// Хранится в UserDefaults, а не в самом файле истории: это настройка
    /// показа, а не измерение, и в файле с данными ей не место.
    func range(for key: String) -> HistoryRange {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.rangesKey)?[key] as? Int,
              let stored = HistoryRange(rawValue: raw)
        else { return .day }
        return stored
    }

    func setRange(_ range: HistoryRange, for key: String) {
        var stored = UserDefaults.standard.dictionary(forKey: Self.rangesKey) ?? [:]
        stored[key] = range.rawValue
        UserDefaults.standard.set(stored, forKey: Self.rangesKey)
    }

    private static let rangesKey = "HistoryRanges"

    // MARK: - Запись

    /// Одно измерение. Вызывается на каждое завершённое обновление размера —
    /// и по расписанию, и по кнопке ручного обхода.
    func record(size: UInt64, for folder: TrackedFolder, at date: Date) {
        guard !frozen else { return }
        let key = folder.id.uuidString
        var points = points(for: folder.id)
        points.append(HistoryPoint(date: date, size: size))
        points = Self.compact(points, now: date)
        cache[key] = points
        revision &+= 1

        // Манифест обновляем здесь же: путь или псевдоним могли поменяться, а
        // файл истории должен оставаться привязанным к той же папке.
        touchIndex(folder)
        write(points, for: key)
    }

    /// Занятое место на ПОСТОЯННОМ томе, не чаще раза в час. Частоту не
    /// выносим в настройки: свободное место меняется медленно, и точки чаще
    /// часа не добавили бы к ответу «когда диск начал заполняться» ничего,
    /// кроме веса файла. Час отмеряется от последней записанной точки, а не от
    /// круглого часа: после перезапуска посреди часа история не прерывается.
    ///
    /// Подключаемые тома не пишем вовсе. У флешки, которую воткнули на час,
    /// история — это набор разрозненных клякс, и отличить «диск заполнялся» от
    /// «диск просто не был подключён» по ней нельзя.
    func recordVolume(_ volume: VolumeUsage, at date: Date) {
        guard !frozen, !volume.isExternal else { return }
        let key = volume.historyKey
        var points = points(for: key)
        if let last = points.last, date.timeIntervalSince(last.date) < 3600 { return }

        points.append(HistoryPoint(date: date, size: volume.used))
        points = Self.compact(points, now: date)
        cache[key] = points
        revision &+= 1
        touchVolume(volume)
        write(points, for: key)
    }

    /// Папку убрал сам пользователь — историю удаляем вместе с ней. Отличать
    /// это от автоматического снятия с наблюдения важно: `pruneMissingFolders`
    /// срабатывает и на папке отмонтированного тома, и терять её историю из-за
    /// вынутой флешки нельзя.
    func forget(id: UUID) {
        let key = id.uuidString
        cache.removeValue(forKey: key)
        let url = fileURL(for: key)
        index.folders.removeAll { $0.id == key }
        saveIndex()
        io.async { if let url { try? FileManager.default.removeItem(at: url) } }
    }

    /// Отмечает в манифесте, какие папки под наблюдением сейчас. Записи
    /// остальных остаются — по ним история подхватится, если папку вернут.
    func syncTracked(_ folders: [TrackedFolder]) {
        let live = Set(folders.map(\.id.uuidString))
        var changed = false
        // Записи томов пропускаем: их «под наблюдением» решает не список папок,
        // а то, смонтирован ли том, и снимать с них флаг здесь было бы враньём.
        for position in index.folders.indices where !index.folders[position].isVolume
            && index.folders[position].tracked != live.contains(index.folders[position].id) {
            index.folders[position].tracked = live.contains(index.folders[position].id)
            changed = true
        }
        for folder in folders where !index.folders.contains(where: { $0.id == folder.id.uuidString }) {
            touchIndex(folder, save: false)
            changed = true
        }
        if changed { saveIndex() }
    }

    // MARK: - Внутреннее

    private func touchIndex(_ folder: TrackedFolder, save: Bool = true) {
        let key = folder.id.uuidString
        if let position = index.folders.firstIndex(where: { $0.id == key }) {
            index.folders[position].path = folder.path
            index.folders[position].alias = folder.alias
            index.folders[position].tracked = true
            index.folders[position].lastSeen = Date()
        } else if let position = index.folders.firstIndex(where: { !$0.isVolume && !$0.tracked && $0.path == folder.path }) {
            // Ту же папку добавили заново — забираем её прежний файл под новый
            // идентификатор, чтобы график продолжился, а не начался с нуля.
            index.folders[position].id = key
            index.folders[position].alias = folder.alias
            index.folders[position].tracked = true
            index.folders[position].lastSeen = Date()
            cache.removeValue(forKey: key)
        } else {
            index.folders.append(HistoryIndex.Entry(
                id: key, path: folder.path, alias: folder.alias,
                file: "\(key).json", tracked: true, lastSeen: Date(), kind: "folder"
            ))
        }
        if save { saveIndex() }
    }

    /// Запись тома в манифесте. Имя тома меняется (его переименовали), путь
    /// монтирования меняется тоже, а ключ — нет, поэтому история продолжается.
    private func touchVolume(_ volume: VolumeUsage) {
        let key = volume.historyKey
        if let position = index.folders.firstIndex(where: { $0.id == key }) {
            index.folders[position].path = volume.id
            index.folders[position].alias = volume.name
            index.folders[position].tracked = true
            index.folders[position].lastSeen = Date()
        } else {
            index.folders.append(HistoryIndex.Entry(
                id: key, path: volume.id, alias: volume.name,
                file: "volume-\(Self.safeName(key)).json",
                tracked: true, lastSeen: Date(), kind: "volume"
            ))
        }
        saveIndex()
    }

    /// В имя файла ключ попадает как есть только когда он UUID. Если файловая
    /// система UUID не ведёт, ключом становится путь монтирования, а слэш в
    /// имени файла — это уже другой каталог.
    private static func safeName(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(key.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private func fileURL(for key: String) -> URL? {
        guard let directory else { return nil }
        let name = index.folders.first { $0.id == key }?.file ?? "\(key).json"
        return directory.appendingPathComponent(name)
    }

    /// Только для оффскрин-рендера и проверки вида: точки подставляются в
    /// память, диск при этом не читается и не пишется — настоящая история
    /// пользователя от таких прогонов не страдает.
    func setScreenshotState(points: [HistoryPoint], for id: UUID) {
        frozen = true
        cache[id.uuidString] = points.sorted { $0.date < $1.date }
    }

    private func write(_ points: [HistoryPoint], for key: String) {
        guard !frozen, let url = fileURL(for: key) else { return }
        io.async {
            guard let data = try? makeHistoryEncoder().encode(points) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func saveIndex() {
        guard !frozen, let directory else { return }
        index.updatedAt = Date()
        let url = directory.appendingPathComponent("index.json")
        let snapshot = index
        io.async {
            guard let data = try? makeHistoryEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Свежие сутки храним как измеряли, глубже — по одной точке на час, дальше
    /// квартала не храним вовсе. Без этого файл растёт без предела: при обходе
    /// раз в минуту за квартал накопилось бы 130 тысяч точек и мегабайты JSON,
    /// притом что даже квартальный график шире тысячи точек не покажет.
    static func compact(_ points: [HistoryPoint], now: Date) -> [HistoryPoint] {
        let horizon = now.addingTimeInterval(-100 * 86_400)
        let detailed = now.addingTimeInterval(-2 * 86_400)
        let sorted = points.filter { $0.date >= horizon }.sorted { $0.date < $1.date }

        var thinned: [HistoryPoint] = []
        var currentHour: Date?
        for point in sorted where point.date < detailed {
            let hour = Date(timeIntervalSince1970: (point.date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
            if hour == currentHour {
                thinned[thinned.count - 1] = point   // в часе остаётся последняя
            } else {
                thinned.append(point)
                currentHour = hour
            }
        }
        return thinned + sorted.filter { $0.date >= detailed }
    }
}
