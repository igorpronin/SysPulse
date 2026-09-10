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

/// Манифест: какой файл истории принадлежит какой папке. Записи снятых с
/// наблюдения папок остаются здесь с `tracked: false` — по ним история
/// подхватывается обратно, если ту же папку добавят снова.
struct HistoryIndex: Codable {
    struct Entry: Codable, Equatable {
        var id: String
        var path: String
        var alias: String
        var file: String
        var tracked: Bool
        var lastSeen: Date
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

    /// Точки папки, по возрастанию даты. Файл читается один раз за сеанс.
    func points(for id: UUID) -> [HistoryPoint] {
        let key = id.uuidString
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
        for position in index.folders.indices where index.folders[position].tracked != live.contains(index.folders[position].id) {
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
        } else if let position = index.folders.firstIndex(where: { !$0.tracked && $0.path == folder.path }) {
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
                file: "\(key).json", tracked: true, lastSeen: Date()
            ))
        }
        if save { saveIndex() }
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
