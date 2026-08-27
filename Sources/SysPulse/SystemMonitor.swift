import AppKit
import Combine
import Darwin

// MARK: - Снимки метрик

struct CPULoad: Equatable, Sendable {
    var perCore: [Double] = []  // 0…1 по каждому логическому ядру
    var total: Double = 0       // средняя загрузка по всем ядрам
}

enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4
}

// Разбивка «всех видов» памяти в терминах Мониторинга системы:
// использовано = приложения + wired + сжатая; файловый кэш и свободная — отдельно.
struct MemoryUsage: Equatable, Sendable {
    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var free: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressureRaw: Int = MemoryPressure.normal.rawValue

    var pressure: MemoryPressure { MemoryPressure(rawValue: pressureRaw) ?? .normal }
    var used: UInt64 { app + wired + compressed }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct VolumeUsage: Identifiable, Equatable, Sendable {
    let id: String      // путь монтирования — стабильный ключ для настроек
    let name: String
    let isRoot: Bool    // загрузочный том: показываем под общей меткой «Диск»
    let total: UInt64
    let free: UInt64

    var used: UInt64 { total > free ? total - free : 0 }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

// MARK: - Форматирование

enum Fmt {
    /// ОЗУ macOS считает в двоичных гигабайтах (16 GB = 16 ГиБ).
    static func memNumber(_ bytes: UInt64) -> String {
        number(Double(bytes) / 1_073_741_824)
    }

    static func mem(_ bytes: UInt64) -> String { memNumber(bytes) + " GB" }

    /// Объём дисков macOS (Finder, «Об этом Mac») считает в десятичных гигабайтах.
    /// Мелкие значения переводим в МБ и КБ: у папок и подпапок «0 GB» сообщает
    /// куда меньше, чем «34 MB».
    static func disk(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1000 { return number(gb / 1000) + " TB" }
        if gb >= 1 { return number(gb) + " GB" }
        let mb = Double(bytes) / 1_000_000
        return mb >= 1 ? number(mb) + " MB" : number(Double(bytes) / 1000) + " KB"
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", min(1, max(0, fraction)) * 100)
    }

    /// То же, но с ведущими пробелами до трёх знаков: вместе с моноширинными
    /// цифрами это держит ширину значка в меню-баре постоянной, иначе соседние
    /// значки дёргаются на каждом обновлении.
    static func percentPadded(_ fraction: Double) -> String {
        String(format: "%3.0f%%", min(1, max(0, fraction)) * 100)
    }

    // Один знак после запятой до сотни, дальше целые; хвостовой «.0» не пишем —
    // «16 GB» вместо «16.0 GB».
    private static func number(_ value: Double) -> String {
        let text = String(format: value >= 100 ? "%.0f" : "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

// MARK: - Замеры

// Тики процессора кумулятивны — загрузка считается по разнице двух снимков,
// поэтому первый снимок после старта только запоминается (базовый).
private struct CPUSampler {
    private var previous: [UInt32] = []

    mutating func sample() -> CPULoad? {
        var cores: natural_t = 0
        var infoPtr: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cores, &infoPtr, &infoCount
        )
        guard result == KERN_SUCCESS, let infoPtr else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: infoPtr),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let ticks = (0..<Int(infoCount)).map { UInt32(bitPattern: infoPtr[$0]) }
        let states = Int(CPU_STATE_MAX)
        defer { previous = ticks }
        guard previous.count == ticks.count else { return nil }

        var perCore: [Double] = []
        perCore.reserveCapacity(Int(cores))
        for core in 0..<Int(cores) {
            let base = core * states
            guard base + states <= ticks.count else { break }
            // Счётчики 32-битные и переполняются — вычитаем с переносом (&-).
            func delta(_ state: Int32) -> Double {
                Double(ticks[base + Int(state)] &- previous[base + Int(state)])
            }
            let busy = delta(CPU_STATE_USER) + delta(CPU_STATE_SYSTEM) + delta(CPU_STATE_NICE)
            let total = busy + delta(CPU_STATE_IDLE)
            perCore.append(total > 0 ? min(1, busy / total) : 0)
        }
        guard !perCore.isEmpty else { return nil }
        return CPULoad(
            perCore: perCore,
            total: perCore.reduce(0, +) / Double(perCore.count)
        )
    }
}

private enum MemorySampler {
    static func sample() -> MemoryUsage {
        var usage = MemoryUsage(total: ProcessInfo.processInfo.physicalMemory)

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            func bytes(_ pages: UInt32) -> UInt64 { UInt64(pages) * page }
            // Память приложений = вся анонимная за вычетом purgeable (её ядро
            // может выбросить в любой момент, Мониторинг системы её не считает).
            let purgeable = bytes(stats.purgeable_count)
            usage.app = bytes(stats.internal_page_count) > purgeable
                ? bytes(stats.internal_page_count) - purgeable
                : 0
            usage.wired = bytes(stats.wire_count)
            usage.compressed = bytes(stats.compressor_page_count)
            usage.cached = bytes(stats.external_page_count) + purgeable
            usage.free = bytes(stats.free_count) > bytes(stats.speculative_count)
                ? bytes(stats.free_count) - bytes(stats.speculative_count)
                : 0
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            usage.swapUsed = swap.xsu_used
            usage.swapTotal = swap.xsu_total
        }

        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.stride
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0 {
            usage.pressureRaw = Int(level)
        }

        return usage
    }
}

private enum DiskSampler {
    // Только смонтированные локальные тома, видимые пользователю. Свободное место —
    // volumeAvailableCapacityForImportantUsage: это то же число, что показывает Finder
    // (на APFS в него входит освобождаемое место снапшотов).
    static func sample() -> [VolumeUsage] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsBrowsableKey, .volumeIsLocalKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) ?? []

        var result: [VolumeUsage] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable == true,
                  values.volumeIsLocal == true,
                  let total = values.volumeTotalCapacity, total > 0
            else { continue }
            let free = values.volumeAvailableCapacityForImportantUsage ?? 0
            result.append(VolumeUsage(
                id: url.path,
                name: values.volumeName ?? url.lastPathComponent,
                isRoot: url.path == "/",
                total: UInt64(total),
                free: UInt64(max(0, free))
            ))
        }
        // Загрузочный том всегда первым, остальные по имени — порядок не должен
        // прыгать между опросами, иначе строки в окошке меняются местами.
        return result.sorted {
            $0.isRoot != $1.isRoot ? $0.isRoot : $0.name < $1.name
        }
    }
}

// MARK: - Монитор

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpu = CPULoad()
    @Published private(set) var memory = MemoryUsage()
    @Published private(set) var volumes: [VolumeUsage] = []

    // MARK: - Состав окошка (всё переживает перезапуск)

    @Published var showCPU: Bool { didSet { store(showCPU, "ShowCPU") } }
    @Published var showCores: Bool { didSet { store(showCores, "ShowCores") } }
    @Published var showMemory: Bool { didSet { store(showMemory, "ShowMemory") } }
    @Published var showMemoryDetails: Bool { didSet { store(showMemoryDetails, "ShowMemoryDetails") } }
    @Published var showDisks: Bool { didSet { store(showDisks, "ShowDisks") } }
    @Published var showFolders: Bool { didSet { store(showFolders, "ShowFolders") } }

    // Тома, спрятанные пользователем; ключ — путь монтирования.
    @Published private(set) var hiddenVolumes: Set<String> {
        didSet { store(Array(hiddenVolumes), "HiddenVolumes") }
    }

    // Что дублируется в меню-баре.
    @Published var menuBarCPU: Bool { didSet { store(menuBarCPU, "MenuBarCPU") } }
    @Published var menuBarMemory: Bool { didSet { store(menuBarMemory, "MenuBarMemory") } }
    @Published var menuBarDisk: Bool { didSet { store(menuBarDisk, "MenuBarDisk") } }

    // Период опроса CPU и памяти в секундах (диски опрашиваются медленно и отдельно).
    @Published var interval: Double {
        didSet {
            store(interval, "UpdateInterval")
            if started { restartTimers() }
        }
    }

    // MARK: - Настройки вида (как в DeskMap)

    @Published var compact: Bool { didSet { store(compact, "CompactMode") } }
    @Published var alignRight: Bool { didSet { store(alignRight, "AlignRight") } }

    // 0 — полностью прозрачный фон, 1 — полностью чёрный (в режиме Contrast — белый).
    @Published var opacity: Double { didSet { store(opacity, "PanelOpacity") } }

    // Contrast: обратная гамма — фон от прозрачного к белому, шрифт в противофазе.
    @Published var contrast: Bool { didSet { store(contrast, "ContrastMode") } }

    static let intervals: [Double] = [0.5, 1, 2, 5]

    private var cpuSampler = CPUSampler()
    private var timer: Timer?
    private var diskTimer: Timer?
    private var started = false
    private var screenshotMode = false

    init() {
        let ud = UserDefaults.standard
        func flag(_ key: String, default value: Bool) -> Bool {
            ud.object(forKey: key) as? Bool ?? value
        }
        showCPU = flag("ShowCPU", default: true)
        showCores = flag("ShowCores", default: true)
        showMemory = flag("ShowMemory", default: true)
        showMemoryDetails = flag("ShowMemoryDetails", default: false)
        showDisks = flag("ShowDisks", default: true)
        showFolders = flag("ShowFolders", default: true)
        hiddenVolumes = Set(ud.stringArray(forKey: "HiddenVolumes") ?? [])
        // В меню-баре по умолчанию только процессор: строка с тремя метриками
        // широкая, и на забитом меню-баре macOS просто прячет значок.
        menuBarCPU = flag("MenuBarCPU", default: true)
        menuBarMemory = flag("MenuBarMemory", default: false)
        menuBarDisk = flag("MenuBarDisk", default: false)
        interval = ud.object(forKey: "UpdateInterval") as? Double ?? 1
        compact = ud.bool(forKey: "CompactMode")
        alignRight = ud.bool(forKey: "AlignRight")
        opacity = ud.object(forKey: "PanelOpacity") as? Double ?? 0.35
        contrast = ud.bool(forKey: "ContrastMode")
    }

    private func store(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Тома, которые сейчас видны в окошке.
    var visibleVolumes: [VolumeUsage] {
        volumes.filter { !hiddenVolumes.contains($0.id) }
    }

    func setVolume(_ id: String, visible: Bool) {
        if visible {
            hiddenVolumes.remove(id)
        } else {
            hiddenVolumes.insert(id)
        }
    }

    // MARK: - Опрос

    func start() {
        guard !started else { return }
        started = true
        _ = cpuSampler.sample()  // базовый снимок тиков, без него первая загрузка неизвестна
        memory = MemorySampler.sample()
        refreshVolumes()
        restartTimers()
    }

    private func restartTimers() {
        timer?.invalidate()
        diskTimer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Свободное место меняется медленно, а опрос томов заметно дороже
        // (может ходить на диск) — отдельный редкий таймер.
        diskTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshVolumes() }
        }
    }

    private func tick() {
        guard !screenshotMode else { return }
        if let load = cpuSampler.sample(), load != cpu {
            cpu = load
        }
        let usage = MemorySampler.sample()
        if usage != memory {
            memory = usage
        }
    }

    private func refreshVolumes() {
        guard !screenshotMode else { return }
        Task.detached(priority: .utility) { [weak self] in
            let sampled = DiskSampler.sample()
            guard let monitor = self else { return }
            await MainActor.run {
                guard monitor.volumes != sampled else { return }
                monitor.volumes = sampled
            }
        }
    }

    // Только для оффскрин-рендера скриншотов README (scripts/make-screenshots.sh):
    // подставляет фейковое состояние, реальные данные не участвуют.
    func setScreenshotState(cpu: CPULoad, memory: MemoryUsage, volumes: [VolumeUsage]) {
        screenshotMode = true
        self.cpu = cpu
        self.memory = memory
        self.volumes = volumes
    }
}
