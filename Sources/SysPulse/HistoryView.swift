import AppKit
import SwiftUI

// Окно графика: как менялся размер одной папки. Одна серия во времени — значит
// линия, и легенда не нужна: серию называет заголовок окна.
//
// Ось размеров нарочно НЕ начинается с нуля, и потому под линией нет заливки.
// Папка на 300 ГБ, выросшая за ночь на 40, при нулевой оси дала бы почти
// горизонтальную черту — ровно то изменение, ради которого график и строится,
// стало бы невидимым. У линии смещённое начало оси законно (в отличие от
// столбиков), но заливка от него читалась бы как «объём», поэтому её нет:
// закрашенная площадь врала бы о величине.

/// Окно показывает историю чего угодно, у чего есть ключ: папки или тома.
/// Своего типа для этого не заводим — окну нужны ровно заголовок, подпись и
/// ключ, а знать, папка перед ним или диск, ему незачем.
struct HistoryChartView: View {
    let title: String
    let subtitle: String
    let key: String
    @ObservedObject var history: HistoryStore
    @ObservedObject var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var range: HistoryRange
    @State private var hovered: HistoryPoint?

    init(title: String, subtitle: String, key: String, history: HistoryStore) {
        self.title = title
        self.subtitle = subtitle
        self.key = key
        self.history = history
        // Диапазон берём запомненный для этого же ключа: у одной папки смотрят
        // суточную рябь, у другой — квартальный тренд, и сбрасывать выбор на
        // сутки при каждом открытии значит переключать его заново каждый раз.
        _range = State(initialValue: history.range(for: key))
    }

    private var all: [HistoryPoint] { history.points(for: key) }

    /// Шаг палитры под подложку окна: те же два цвета, что у памяти в панели,
    /// оба проверены валидатором на контраст к светлой и тёмной подложке.
    private var lineColor: Color { Palette.app(contrast: colorScheme == .light) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ranges
            if all.isEmpty {
                empty
            } else {
                readout
                plot
            }
        }
        .padding(16)
        .frame(width: 560)
        // Запомненный диапазон мог стать недоступным: историю подрезали, или
        // выбор остался от папки с куда более долгой историей. Тогда берём
        // самый длинный из доступных — но не сбрасываем на сутки, это потеряло
        // бы намерение пользователя целиком.
        .onAppear {
            guard !isAvailable(range) else { return }
            range = HistoryRange.allCases.last { isAvailable($0) } ?? .day
        }
        .onChange(of: range) { history.setRange($0, for: key) }
    }

    // MARK: - Части

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var ranges: some View {
        HStack(spacing: 6) {
            ForEach(HistoryRange.allCases) { option in
                rangeButton(option)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func rangeButton(_ option: HistoryRange) -> some View {
        let enabled = isAvailable(option)
        // Погашенная кнопка без объяснения — загадка; подсказка говорит, чего
        // именно не хватает. На доступной кнопке подсказки нет вовсе: пустая
        // строка в .help() всё равно оставляет пустое облачко.
        if enabled {
            rangePill(option, enabled: true)
        } else {
            rangePill(option, enabled: false).help(l10n.t(.historyNotEnough))
        }
    }

    private func rangePill(_ option: HistoryRange, enabled: Bool) -> some View {
        let selected = option == range
        return Button {
            range = option
            hovered = nil
        } label: {
            Text(l10n.t(option.key))
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(selected ? lineColor.opacity(0.85) : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(selected ? Color.white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    /// Диапазон предлагаем, только если данные уходят глубже предыдущего,
    /// более короткого: иначе он показал бы то же самое плюс пустоту.
    private func isAvailable(_ option: HistoryRange) -> Bool {
        guard let oldest = all.first?.date else { return option == .day }
        guard option.unlockAfterDays > 0 else { return true }
        return Date().timeIntervalSince(oldest) >= option.unlockAfterDays * 86_400
    }

    private var empty: some View {
        Text(l10n.t(.historyEmpty))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(width: 528, height: Self.plotHeight, alignment: .center)
            .multilineTextAlignment(.center)
    }

    /// Строка над графиком: либо точка под курсором, либо итог по диапазону.
    private var readout: some View {
        let visible = visiblePoints
        let text: String
        if let hovered {
            text = "\(Self.stamp.string(from: hovered.date))   \(Fmt.disk(hovered.size))"
        } else if let first = visible.first, let last = visible.last {
            let delta = Int64(bitPattern: last.size) - Int64(bitPattern: first.size)
            let sign = delta > 0 ? "+" : delta < 0 ? "−" : "±"
            text = "\(Fmt.disk(last.size))   ·   \(l10n.t(.historyChange)) \(sign)\(Fmt.disk(UInt64(abs(delta))))"
        } else {
            text = "—"
        }
        return Text(text)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var plot: some View {
        let visible = visiblePoints
        let scale = Scale(points: visible, range: range)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                axisLabels(scale)
                GeometryReader { geometry in
                    canvas(visible: visible, scale: scale, size: geometry.size)
                }
                .frame(height: Self.plotHeight)
            }
            timeLabels(scale)
        }
    }

    /// Подписи оси ставим теми же долями, что и линии сетки, и поднимаем на
    /// половину строки: иначе подпись оказывается ниже своей линии, и на
    /// нижней, у самой кромки, это особенно заметно.
    private func axisLabels(_ scale: Scale) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach([0.0, 0.5, 1.0], id: \.self) { fraction in
                Text(Fmt.disk(scale.value(atFraction: fraction)))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .offset(y: Self.plotHeight * CGFloat(1 - fraction) - 6)
            }
        }
        .frame(width: 62, height: Self.plotHeight, alignment: .topTrailing)
    }

    private func timeLabels(_ scale: Scale) -> some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 68)
            ForEach(0..<4, id: \.self) { step in
                Text(scale.timeLabel(atFraction: Double(step) / 3, range: range))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: step == 0 ? .leading : (step == 3 ? .trailing : .center))
            }
        }
    }

    private func canvas(visible: [HistoryPoint], scale: Scale, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // Сетка приглушена намеренно: она помогает считать значения и не
            // должна спорить с линией за внимание.
            ForEach([0.0, 0.5, 1.0], id: \.self) { fraction in
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 1)
                    .offset(y: size.height * CGFloat(1 - fraction))
            }

            if visible.count > 1 {
                Path { path in
                    for (index, point) in visible.enumerated() {
                        let position = scale.position(point, in: size)
                        index == 0 ? path.move(to: position) : path.addLine(to: position)
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            // Последнее измерение помечаем точкой: без неё не видно, кончается
            // ли линия сейчас или данные оборвались раньше правого края.
            if let last = visible.last {
                marker(at: scale.position(last, in: size), filled: true)
            }

            if let hovered, let index = visible.firstIndex(of: hovered) {
                let position = scale.position(visible[index], in: size)
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 1, height: size.height)
                    .offset(x: position.x)
                marker(at: position, filled: false)
            }
        }
        .frame(height: Self.plotHeight)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hovered = scale.nearest(to: location.x, in: size, among: visible)
            case .ended:
                hovered = nil
            }
        }
    }

    /// Маркер 8 pt — меньше на графике не читается, а обводка подложкой
    /// отделяет его от линии, на которой он лежит.
    private func marker(at position: CGPoint, filled: Bool) -> some View {
        Circle()
            .fill(filled ? lineColor : Color(nsColor: .windowBackgroundColor))
            .overlay(Circle().stroke(lineColor, lineWidth: 2))
            .frame(width: 8, height: 8)
            .offset(x: position.x - 4, y: position.y - 4)
    }

    private var visiblePoints: [HistoryPoint] {
        let from = Date().addingTimeInterval(-range.days * 86_400)
        return all.filter { $0.date >= from }
    }

    /// Высота поля графика. Одна константа на все места, где она нужна:
    /// подписи оси выравниваются по ней же.
    static let plotHeight: CGFloat = 180

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Пересчёт координат

/// Ось времени — это ВЫБРАННОЕ окно, а не размах данных: «за неделю» должно
/// показывать неделю, иначе двухчасовой хвост растянулся бы на всю ширину и
/// выглядел бы как неделя наблюдений.
private struct Scale {
    let from: Date
    let to: Date
    let low: Double
    let high: Double

    init(points: [HistoryPoint], range: HistoryRange) {
        to = Date()
        from = to.addingTimeInterval(-range.days * 86_400)
        let sizes = points.map { Double($0.size) }
        let minimum = sizes.min() ?? 0
        let maximum = sizes.max() ?? 0
        // Ровная линия (размер не менялся) не должна лежать на самой кромке:
        // поле сверху и снизу делает её видимой и говорит, что данные есть.
        let padding = max((maximum - minimum) * 0.1, max(maximum * 0.01, 1))
        low = minimum - padding
        high = maximum + padding
    }

    func position(_ point: HistoryPoint, in size: CGSize) -> CGPoint {
        let span = max(to.timeIntervalSince(from), 1)
        let x = point.date.timeIntervalSince(from) / span
        let y = (Double(point.size) - low) / max(high - low, 1)
        return CGPoint(x: size.width * CGFloat(min(1, max(0, x))),
                       y: size.height * CGFloat(1 - min(1, max(0, y))))
    }

    func value(atFraction fraction: Double) -> UInt64 {
        UInt64(max(0, low + (high - low) * fraction))
    }

    func timeLabel(atFraction fraction: Double, range: HistoryRange) -> String {
        let moment = from.addingTimeInterval(to.timeIntervalSince(from) * fraction)
        let formatter = DateFormatter()
        formatter.locale = .current
        // Подпись держим короткой, но однозначной: за сутки время, дальше дата.
        formatter.setLocalizedDateFormatFromTemplate(range == .day ? "j:mm" : "d MMM")
        return formatter.string(from: moment)
    }

    func nearest(to x: CGFloat, in size: CGSize, among points: [HistoryPoint]) -> HistoryPoint? {
        guard !points.isEmpty, size.width > 0 else { return nil }
        let fraction = min(1, max(0, x / size.width))
        let target = from.addingTimeInterval(to.timeIntervalSince(from) * Double(fraction))
        return points.min {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        }
    }
}
