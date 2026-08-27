import AppKit
import Combine

// Проверка новой версии на GitHub — единственное место в приложении, которое
// ходит в сеть. Запрос анонимный, без токена, раз в сутки: наружу не уходит
// ничего, кроме самого факта запроса (GitHub видит IP и User-Agent).
// Скачиванием и самоподменой не занимаемся намеренно: приложение не нотаризовано,
// и самозамена упёрлась бы в Gatekeeper. Нашли новую версию — открываем
// страницу релиза в браузере, дальше человек решает сам.

@MainActor
final class UpdateChecker: ObservableObject {
    struct Release: Equatable {
        let version: String   // «0.4.0», без ведущей v
        let page: URL
    }

    /// Известная свежая версия, если она новее текущей. Хранится между
    /// запусками: иначе после перезапуска пункт меню пропадал бы до следующей
    /// суточной проверки.
    @Published private(set) var available: Release?
    @Published private(set) var checking = false

    @Published var autoCheck: Bool {
        didSet {
            UserDefaults.standard.set(autoCheck, forKey: "CheckForUpdates")
            if autoCheck { checkIfDue() }
        }
    }

    private static let endpoint = URL(
        string: "https://api.github.com/repos/igorpronin/SysPulse/releases/latest"
    )!
    private static let interval: TimeInterval = 24 * 60 * 60

    private var timer: Timer?

    init() {
        let defaults = UserDefaults.standard
        autoCheck = defaults.object(forKey: "CheckForUpdates") as? Bool ?? true
        if let version = defaults.string(forKey: "LatestKnownVersion"),
           let page = defaults.string(forKey: "LatestKnownPage").flatMap(URL.init(string:)),
           Self.isNewer(version, than: AppInfo.version) {
            available = Release(version: version, page: page)
        }
    }

    func start() {
        // Раз в час смотрим, не подошли ли сутки. Сам запрос от этого не
        // учащается: его сдерживает отметка времени последней проверки.
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        checkIfDue()
    }

    private func checkIfDue() {
        guard autoCheck else { return }
        let last = UserDefaults.standard.object(forKey: "LastUpdateCheck") as? Date
        if let last, Date().timeIntervalSince(last) < Self.interval { return }
        check()
    }

    /// - Parameter report: показать результат человеку — для ручной проверки из
    ///   меню. Автоматическая проверка молчит: не ответил GitHub, и ладно.
    func check(report: Bool = false) {
        guard !checking else { return }
        checking = true

        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        // GitHub требует User-Agent и отказывает запросам без него.
        request.setValue("SysPulse/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let release = data.flatMap { Self.parse($0) }
            Task { @MainActor in
                self.finish(release: code == 200 ? release : nil, report: report)
            }
        }.resume()
    }

    private func finish(release: Release?, report: Bool) {
        checking = false
        guard let release else {
            if report { alert(L10n.shared.t(.checkFailed)) }
            return
        }
        UserDefaults.standard.set(Date(), forKey: "LastUpdateCheck")
        UserDefaults.standard.set(release.version, forKey: "LatestKnownVersion")
        UserDefaults.standard.set(release.page.absoluteString, forKey: "LatestKnownPage")

        let newer = Self.isNewer(release.version, than: AppInfo.version)
        available = newer ? release : nil
        if report {
            alert(newer
                ? "\(L10n.shared.t(.updateAvailable)) \(release.version)"
                : L10n.shared.t(.upToDate))
        }
    }

    private func alert(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = AppInfo.name
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        if available != nil {
            alert.addButton(withTitle: L10n.shared.t(.openRelease))
            if alert.runModal() == .alertSecondButtonReturn { openReleasePage() }
        } else {
            alert.runModal()
        }
    }

    func openReleasePage() {
        NSWorkspace.shared.open(available?.page ?? Self.fallbackPage)
    }

    private static let fallbackPage = URL(
        string: "https://github.com/igorpronin/SysPulse/releases/latest"
    )!

    // MARK: - Разбор ответа и сравнение версий

    nonisolated static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { return nil }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page)
    }

    /// Сравнение по semver почастям, а не строк: «0.10.0» больше «0.9.0»,
    /// хотя как строка меньше. Недостающие части считаем нулями.
    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ value: String) -> [Int] {
            value.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let left = parts(remote)
        let right = parts(local)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
