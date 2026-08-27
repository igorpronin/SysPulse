import SwiftUI
import AppKit

struct MemorySegment {
    let name: String
    let bytes: UInt64
    let color: Color
    let help: L10nKey
}

/// Категориальная палитра для видов памяти. Шаги подобраны под две подложки —
/// тёмную (обычный режим) и светлую (Contrast), — и проверены валидатором:
/// худшая соседняя пара по дальтонизму ΔE 24.7 на светлой и 26.0 на тёмной при
/// пороге 8, контраст к подложке ≥ 3:1 в обоих режимах. Менять на глаз нельзя:
/// синий с бирюзовым, например, эту проверку не проходят.
enum Palette {
    static func app(contrast: Bool) -> Color { contrast ? hex(0x2A78D6) : hex(0x3987E5) }
    static func wired(contrast: Bool) -> Color { contrast ? hex(0xEB6834) : hex(0xD95926) }
    static func compressed(contrast: Bool) -> Color { contrast ? hex(0x4A3AA7) : hex(0x9085E9) }

    /// Файловый кэш — не «свой» цвет в шкале, а нейтральный: он сообщает
    /// «это не занятая память». Тон фиксированный, одинаково приглушённый и на
    /// тёмной подложке, и на светлой; привязать его к цвету текста нельзя —
    /// в Contrast он стал бы темнее самих категорий и перетянул бы внимание.
    static let cached = hex(0x8E8E88)

    private static func hex(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var folders: FolderTracker
    @ObservedObject var l10n = L10n.shared

    var body: some View {
        content
            .shadow(color: haloColor, radius: 1)
            .padding(.horizontal, monitor.compact ? 6 : 8)
            .padding(.vertical, monitor.compact ? 4 : 6)
            .background(
                Color(white: monitor.contrast ? 1 : 0).opacity(monitor.opacity),
                in: RoundedRectangle(cornerRadius: monitor.compact ? 7 : 9, style: .continuous)
            )
            // Своего контекстного меню у окошка нет: и левый, и правый клик
            // открывают одно и то же меню из меню-бара (см. FloatingPanel).
    }

    // MARK: - Цвета под прозрачность
    // Один бегунок: фон — чёрный (в Contrast — белый) с альфой 0..1, текст
    // подстраивается, чтобы был виден: на плотном фоне — противоположный фону,
    // на прозрачном — наоборот, всегда с обратной по тону обводкой.

    private var textWhite: Double {
        let ramp = min(1, monitor.opacity / 0.35)
        return monitor.contrast ? 1 - ramp : ramp
    }

    private var textColor: Color {
        Color(white: textWhite)
    }

    private var haloColor: Color {
        Color(white: 1 - textWhite).opacity(0.7)
    }

    /// Цвет заполнения полоски: зелёный до половины, дальше через жёлтый в красный.
    /// В Contrast тон темнее — иначе не читается на светлом фоне.
    private func loadColor(_ fraction: Double) -> Color {
        let ramp = min(1, max(0, (fraction - 0.45) / 0.45))
        return Color(
            hue: 0.33 * (1 - ramp),
            saturation: monitor.contrast ? 0.9 : 0.72,
            brightness: monitor.contrast ? 0.68 : 0.95
        )
    }

    /// Дорожка — это и есть «свободно»: у памяти хвост после сегментов, у дисков
    /// и ЦП — незалитая часть. Поэтому она не фон, а полноценное показание, и
    /// светлее, чем взял бы обычный фон: иначе пустой хвост сливается с панелью
    /// и полоска выглядит короче, чем есть. Обводку по контуру пробовали —
    /// читаемость та же, а вид грязнее; владелец её снял.
    private var trackColor: Color { textColor.opacity(0.26) }

    // MARK: - Размеры

    private var labelWidth: CGFloat { monitor.compact ? 34 : 44 }

    /// Зазор между столбиками ядер. При большом их числе ужимается: на 14 ядрах
    /// полтора пикселя между столбиками съедали бы треть полоски.
    private var coreSpacing: CGFloat { monitor.cpu.perCore.count > 8 ? 1 : 1.5 }

    /// Зазор между группами E- и P-ядер.
    private var coreGroupGap: CGFloat { monitor.cpu.efficiencyCores > 0 ? 4 : 0 }

    /// Полоска шире базовой, если ядер много: иначе на 14 ядрах столбик выходит
    /// в 3 px и превращается в точку. Ширина растёт у ВСЕХ строк сразу, поэтому
    /// колонки остаются выровненными, а панель просто становится шире.
    /// Ширина полоски подбирается так, чтобы на столбик приходилось ЦЕЛОЕ число
    /// полупикселей. Иначе остаток от деления SwiftUI раздаёт паре столбиков, и
    /// они выходят шире соседей на полточки — на retina это лишний пиксель, и
    /// строка выглядит кривой. Считаем от размера столбика, а не наоборот.
    private var barWidth: CGFloat {
        let base: CGFloat = monitor.compact ? 62 : 84
        let cores = monitor.cpu.perCore.count
        guard monitor.showCPU, monitor.showCores, cores > 0 else { return base }
        // Всё, что в полоске занято не столбиками: зазоры и разделитель групп
        // (он добавляет к строке ещё один элемент, а значит и ещё один зазор).
        let nonBar = CGFloat(cores - 1) * coreSpacing
            + (coreGroupGap > 0 ? coreGroupGap + coreSpacing : 0)
        let minBar: CGFloat = monitor.compact ? 4 : 6
        let fitted = floor((base - nonBar) / CGFloat(cores) * 2) / 2
        let each = max(minBar, fitted)
        return min(monitor.compact ? 112 : 148, CGFloat(cores) * each + nonBar)
    }
    private var valueWidth: CGFloat { monitor.compact ? 66 : 86 }
    private var rowSpacing: CGFloat { monitor.compact ? 4 : 6 }
    private var barHeight: CGFloat { monitor.compact ? 6 : 8 }
    private var coreHeight: CGFloat { monitor.compact ? 11 : 15 }
    private var rowWidth: CGFloat { labelWidth + barWidth + valueWidth + rowSpacing * 2 }

    private var labelFont: Font { .system(size: monitor.compact ? 9 : 11, weight: .semibold) }
    private var valueFont: Font {
        .system(size: monitor.compact ? 9 : 10, weight: .medium).monospacedDigit()
    }
    private var detailFont: Font { .system(size: monitor.compact ? 8 : 9).monospacedDigit() }

    // MARK: - Содержимое

    private var isEmpty: Bool {
        !monitor.showCPU && !monitor.showMemory
            && !(monitor.showGPU && monitor.gpu != nil)
            && !(monitor.showDisks && !monitor.visibleVolumes.isEmpty)
            && !(monitor.showFolders && !folders.folders.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: monitor.compact ? 3 : 5) {
            if monitor.showCPU { cpuRow }
            // Строки GPU нет, если система не отдаёт загрузку.
            if monitor.showGPU, monitor.gpu != nil { gpuRow }
            if monitor.showMemory {
                memoryRow
                if monitor.showMemoryDetails { memoryDetails }
            }
            if monitor.showDisks {
                ForEach(monitor.visibleVolumes) { volume in
                    volumeRow(volume)
                }
            }
            if monitor.showFolders, !folders.folders.isEmpty {
                foldersBlock
            }
            // Всё выключено — окошко не должно схлопнуться в точку.
            if isEmpty {
                Text(AppInfo.name)
                    .font(labelFont)
                    .foregroundStyle(textColor.opacity(0.45))
            }
        }
    }

    // MARK: - Строки

    // При правом выравнивании строка зеркалится: метка уезжает вправо, значение влево.
    private func row<Bar: View>(
        label: String, dimLabel: Bool = false, labelTip: String? = nil,
        value: String, @ViewBuilder bar: () -> Bar
    ) -> some View {
        // Подсказка висит на метке, а не на всей строке: у полоски памяти свои
        // подсказки на сегментах, и вложенные области наведения спорили бы.
        let labelText = Text(label)
            .font(labelFont)
            .foregroundStyle(textColor.opacity(dimLabel ? 0.75 : 1))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: labelWidth, alignment: monitor.alignRight ? .trailing : .leading)
            .hoverTip(labelTip)
        let valueText = Text(value)
            .font(valueFont)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .frame(width: valueWidth, alignment: monitor.alignRight ? .leading : .trailing)

        return HStack(spacing: rowSpacing) {
            if monitor.alignRight {
                valueText
                bar()
                labelText
            } else {
                labelText
                bar()
                valueText
            }
        }
    }

    private var cpuRow: some View {
        row(label: l10n.t(.cpu), value: Fmt.percent(monitor.cpu.total)) {
            if monitor.showCores, !monitor.cpu.perCore.isEmpty {
                coreStrip
            } else {
                bar(fraction: monitor.cpu.total)
            }
        }
    }

    private var gpuRow: some View {
        let load = monitor.gpu ?? 0
        return row(label: l10n.t(.gpu), value: Fmt.percent(load)) {
            bar(fraction: load)
        }
    }

    private var memoryRow: some View {
        let memory = monitor.memory
        let value = "\(Fmt.memNumber(memory.used)) / \(Fmt.mem(memory.total))"
        // Нагрузка на память живёт в подсказке метки: отдельная точка сбоку
        // висела вне колонок и читалась как соринка на экране.
        let tip = "\(l10n.t(.pressure)): \(pressureTitle)\n\n\(l10n.t(.helpPressure))"
        return row(label: l10n.t(.memory), labelTip: tip, value: value) { memoryBar }
    }

    private func volumeRow(_ volume: VolumeUsage) -> some View {
        // В строке видно свободное место, поэтому в подсказке — занятое, вместе
        // с полным именем тома: в узкой колонке метка обрезается.
        let tip = """
            \(volume.name)
            \(l10n.t(.used)): \(Fmt.disk(volume.used)) / \(Fmt.disk(volume.total)) \
            (\(Fmt.percent(volume.usedFraction)))
            \(l10n.t(.freeMemory)): \(Fmt.disk(volume.free))
            """
        return row(
            label: volume.isRoot ? l10n.t(.disk) : volume.name,
            dimLabel: !volume.isRoot,
            value: "\(Fmt.disk(volume.free)) \(l10n.t(.free))"
        ) {
            bar(fraction: volume.usedFraction, tip: tip)
        }
    }

    /// Папки — отдельный блок: тонкая черта, заголовок с общей суммой и кнопкой
    /// «обновить все», под ним сами папки более мелким шрифтом, как разбивка
    /// памяти. Полоски у папок нет намеренно: у размера папки нет своего
    /// «всего», а доля от тома почти всегда вырождается в точку.
    private var foldersBlock: some View {
        VStack(alignment: .leading, spacing: monitor.compact ? 2 : 3) {
            Rectangle()
                .fill(textColor.opacity(0.15))
                .frame(width: rowWidth, height: 1)
                .padding(.top, monitor.compact ? 1 : 2)
            foldersHeader
            ForEach(folders.folders) { folder in
                folderRow(folder)
            }
        }
    }

    private var foldersHeader: some View {
        let title = Text(l10n.t(.showFolders))
            .font(labelFont)
            .foregroundStyle(textColor)
        let total = Text(folders.folders.isEmpty ? "—" : Fmt.disk(folders.totalSize))
            .font(valueFont)
            .foregroundStyle(textColor)
        let button = rescanButton(busy: folders.isScanningAny) { folders.rescanAll() }
        return HStack(spacing: rowSpacing) {
            if monitor.alignRight {
                button
                total
                Spacer(minLength: 4)
                title
            } else {
                title
                Spacer(minLength: 4)
                total
                button
            }
        }
        .frame(width: rowWidth)
    }

    /// Строка папки: псевдоним (если задан) или имя, размер и кнопка обхода.
    private func folderRow(_ folder: TrackedFolder) -> some View {
        let scan = folders.scan(for: folder)
        let value: String
        if scan?.failed == true {
            value = "—"
        } else if let scan {
            value = Fmt.disk(scan.size)
        } else {
            value = "…"
        }
        let tip = folderTip(folder, scan)
        let indent: CGFloat = monitor.compact ? 5 : 7
        let name = Text(folder.title)
            .lineLimit(1)
            .truncationMode(.tail)
            .hoverTip(tip)
        let size = Text(value).hoverTip(tip)
        let button = rescanButton(busy: folders.isScanning(folder)) { folders.rescan(folder) }
        return HStack(spacing: rowSpacing) {
            if monitor.alignRight {
                button
                size
                Spacer(minLength: 4)
                name
                Color.clear.frame(width: indent, height: 1)
            } else {
                Color.clear.frame(width: indent, height: 1)
                name
                Spacer(minLength: 4)
                size
                button
            }
        }
        .font(detailFont)
        .foregroundStyle(textColor.opacity(0.7))
        .frame(width: rowWidth)
    }

    /// Пока обход идёт, кнопка гаснет и не нажимается.
    private func rescanButton(busy: Bool, action: @escaping () -> Void) -> some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: monitor.compact ? 8 : 9, weight: .semibold))
            .foregroundStyle(textColor.opacity(busy ? 0.3 : 0.75))
            .frame(width: monitor.compact ? 10 : 12, height: monitor.compact ? 10 : 12)
            .hoverTip(busy ? l10n.t(.scanning) : l10n.t(.rescan))
            .overlay {
                if !busy { PanelButton(action: action) }
            }
    }

    private func folderTip(_ folder: TrackedFolder, _ scan: FolderScan?) -> String {
        var lines = [folder.title]
        if folder.alias.isEmpty == false || folder.title != folder.path {
            lines.append(folder.path)
        }
        lines.append(l10n.t(folder.interval.key))
        if folders.isScanning(folder) {
            lines.append(l10n.t(.scanning))
        }
        if let scan {
            if scan.failed {
                lines.append(l10n.t(.noAccess))
            } else {
                lines.append("\(l10n.t(.lastScan)): \(Self.scanTime.string(from: scan.scannedAt))")
                if !scan.children.isEmpty {
                    lines.append("")
                    lines.append("\(l10n.t(.largestItems)):")
                    for child in scan.children {
                        // Слэш отличает папку от файла, лежащего прямо в корне.
                        let name = child.isDirectory ? child.name + "/" : child.name
                        lines.append("  \(name) — \(Fmt.disk(child.size))")
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static let scanTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Полоски

    private func bar(fraction: Double, tip: String? = nil) -> some View {
        let clamped = min(1, max(0, fraction))
        return ZStack(alignment: .leading) {
            Capsule(style: .continuous).fill(trackColor)
            Capsule(style: .continuous)
                .fill(loadColor(clamped))
                .frame(width: max(clamped > 0 ? barHeight : 0, barWidth * clamped))
        }
        .frame(width: barWidth, height: barHeight)
        .hoverTip(tip)
    }

    /// Столбик на каждое логическое ядро; ширина полоски фиксирована,
    /// столбики делят её поровну — окошко не «дышит» при смене числа ядер.
    private var coreStrip: some View {
        let cpu = monitor.cpu
        let radius: CGFloat = cpu.perCore.count > 8 ? 1 : 1.5
        return HStack(alignment: .bottom, spacing: coreSpacing) {
            ForEach(Array(cpu.perCore.enumerated()), id: \.offset) { index, load in
                // Экономичные ядра идут первыми, производительные следом.
                // Разделитель — отдельный элемент, а НЕ padding на столбике:
                // столбики тянутся по maxWidth: .infinity, и отступ отъел бы
                // ширину у самого столбика, сделав его уже соседей.
                if index == cpu.efficiencyCores, cpu.efficiencyCores > 0 {
                    Color.clear.frame(width: coreGroupGap, height: 1)
                }
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(trackColor)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(loadColor(load))
                        .frame(height: max(1.5, coreHeight * min(1, max(0, load))))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: barWidth, height: coreHeight)
        .hoverTip(coreTip)
    }

    private var coreTip: String? {
        let cpu = monitor.cpu
        guard cpu.efficiencyCores > 0 else { return nil }
        return "\(l10n.t(.efficiencyCores)): \(cpu.efficiencyCores)"
            + "\n\(l10n.t(.performanceCores)): \(cpu.performanceCores)"
    }

    /// Виды памяти в порядке укладки в полоску. Цвет здесь кодирует «что это»,
    /// а не «сколько», поэтому шкала категориальная (три разных тона), в отличие
    /// от ЦП и дисков, где цвет — это величина и уместен градиент.
    /// Файловый кэш намеренно нейтрально-серый: это не занятая память, система
    /// отдаёт его по первому требованию.
    private var memorySegments: [MemorySegment] {
        let memory = monitor.memory
        return [
            MemorySegment(name: l10n.t(.appMemory), bytes: memory.app,
                          color: Palette.app(contrast: monitor.contrast), help: .helpApp),
            MemorySegment(name: l10n.t(.wired), bytes: memory.wired,
                          color: Palette.wired(contrast: monitor.contrast), help: .helpWired),
            MemorySegment(name: l10n.t(.compressed), bytes: memory.compressed,
                          color: Palette.compressed(contrast: monitor.contrast), help: .helpCompressed),
            MemorySegment(name: l10n.t(.cached), bytes: memory.cached,
                          color: Palette.cached, help: .helpCached),
        ]
    }

    /// Полоска памяти составная: приложения → резидентная → сжатая → файловый
    /// кэш, хвост дорожки — свободная память. Сегменты стоят по своим долям, а
    /// зазор между ними вырезается из ширины сегмента, а не добавляется к ней:
    /// иначе полоска врала бы о том, сколько осталось свободного.
    private var memoryBar: some View {
        let gap: CGFloat = monitor.compact ? 1.5 : 2
        let total = Double(max(1, monitor.memory.total))
        // Сегменты расставлены настоящей раскладкой, а не .offset: тот сдвигает
        // только отрисовку, и области наведения остались бы лежать друг на друге
        // у левого края. Зазор идёт отдельной прозрачной вставкой внутри доли
        // сегмента, поэтому границы стоят точно по долям и хвост дорожки честно
        // показывает, сколько памяти свободно.
        return ZStack(alignment: .leading) {
            Capsule(style: .continuous).fill(trackColor)
            HStack(spacing: 0) {
                ForEach(Array(memorySegments.enumerated()), id: \.offset) { _, segment in
                    let share = barWidth * CGFloat(Double(segment.bytes) / total)
                    if share > gap {
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: share - gap)
                        Color.clear.frame(width: gap)
                    } else {
                        Color.clear.frame(width: share)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: barWidth, height: barHeight)
        .clipShape(Capsule(style: .continuous))
        // Одна область наведения на всю полоску, сегмент вычисляется по доле
        // координаты курсора — накладка при этом снаружи обрезки капсулой.
        .hoverTip(at: memoryTip(atFraction:))
    }

    /// Что показать при наведении на долю `fraction` полоски памяти.
    /// Хвост после сегментов — свободная память.
    private func memoryTip(atFraction fraction: Double) -> String? {
        let total = Double(max(1, monitor.memory.total))
        var start = 0.0
        for segment in memorySegments {
            let share = Double(segment.bytes) / total
            if fraction < start + share {
                return "\(segment.name) — \(Fmt.mem(segment.bytes))\n\n\(l10n.t(segment.help))"
            }
            start += share
        }
        return "\(l10n.t(.freeMemory)) — \(Fmt.mem(monitor.memory.free))\n\n\(l10n.t(.helpFree))"
    }

    // MARK: - Разбивка памяти

    private var memoryDetails: some View {
        let memory = monitor.memory
        // Кружок цвета — та же метка, что и в полоске: связывает строку с сегментом.
        var rows: [(label: String, value: String, help: L10nKey, dot: Color?)] =
            memorySegments.map { ($0.name, Fmt.mem($0.bytes), $0.help, $0.color) }
        rows.append((l10n.t(.freeMemory), Fmt.mem(memory.free), .helpFree, trackColor))
        if memory.swapTotal > 0 {
            rows.append((l10n.t(.swap), Fmt.mem(memory.swapUsed), .helpSwap, nil))
        }
        rows.append((l10n.t(.pressure), pressureTitle, .helpPressure, nil))

        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                let label = HStack(spacing: 3) {
                    // Место под кружок занято всегда, иначе подписи разъезжаются.
                    Circle()
                        .fill(item.dot ?? .clear)
                        .frame(width: 5, height: 5)
                    Text(item.label)
                }
                HStack(spacing: rowSpacing) {
                    if monitor.alignRight {
                        Text(item.value)
                        Spacer(minLength: 4)
                        label
                    } else {
                        label
                        Spacer(minLength: 4)
                        Text(item.value)
                    }
                }
                .font(detailFont)
                .foregroundStyle(textColor.opacity(0.7))
                .lineLimit(1)
                // Наведение на строку — что это за память и зачем она нужна.
                .hoverTip(l10n.t(item.help))
            }
        }
        .frame(width: rowWidth)
    }

    private var pressureTitle: String {
        switch monitor.memory.pressure {
        case .normal: return l10n.t(.pressureNormal)
        case .warning: return l10n.t(.pressureWarning)
        case .critical: return l10n.t(.pressureCritical)
        }
    }
}
