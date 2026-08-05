import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
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
            .contextMenu {
                Button(l10n.t(.metricsSettings)) {
                    (NSApp.delegate as? AppDelegate)?.openMetricsSettings()
                }
                Button(l10n.t(.uiSettings)) {
                    (NSApp.delegate as? AppDelegate)?.openUISettings()
                }
                Divider()
                Toggle(l10n.t(.showCPU), isOn: $monitor.showCPU)
                Toggle(l10n.t(.showCores), isOn: $monitor.showCores)
                Toggle(l10n.t(.showMemory), isOn: $monitor.showMemory)
                Toggle(l10n.t(.showMemoryDetails), isOn: $monitor.showMemoryDetails)
                Toggle(l10n.t(.showDisks), isOn: $monitor.showDisks)
                Divider()
                Toggle(l10n.t(.compactWindow), isOn: $monitor.compact)
                Menu(l10n.t(.alignMenu)) {
                    Toggle(l10n.t(.alignLeft), isOn: Binding(
                        get: { !monitor.alignRight },
                        set: { _ in monitor.alignRight = false }
                    ))
                    Toggle(l10n.t(.alignRight), isOn: Binding(
                        get: { monitor.alignRight },
                        set: { _ in monitor.alignRight = true }
                    ))
                }
                Toggle(l10n.t(.alwaysOnTop), isOn: Binding(
                    get: { (NSApp.delegate as? AppDelegate)?.isPanelOnTop ?? true },
                    set: { (NSApp.delegate as? AppDelegate)?.setPanelOnTop($0) }
                ))
                Button(l10n.t(.hideWindow)) {
                    (NSApp.delegate as? AppDelegate)?.setPanelVisible(false)
                }
                Button(l10n.t(.activityMonitor)) {
                    (NSApp.delegate as? AppDelegate)?.openActivityMonitor()
                }
                Button(l10n.t(.about)) {
                    (NSApp.delegate as? AppDelegate)?.showAbout()
                }
                Divider()
                Button(l10n.t(.quit)) { NSApp.terminate(nil) }
            }
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

    private var trackColor: Color { textColor.opacity(0.18) }

    // MARK: - Размеры

    private var labelWidth: CGFloat { monitor.compact ? 34 : 44 }
    private var barWidth: CGFloat { monitor.compact ? 62 : 84 }
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
            && !(monitor.showDisks && !monitor.visibleVolumes.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: monitor.compact ? 3 : 5) {
            if monitor.showCPU { cpuRow }
            if monitor.showMemory {
                memoryRow
                if monitor.showMemoryDetails { memoryDetails }
            }
            if monitor.showDisks {
                ForEach(monitor.visibleVolumes) { volume in
                    volumeRow(volume)
                }
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
        label: String, dimLabel: Bool = false, value: String, @ViewBuilder bar: () -> Bar
    ) -> some View {
        let labelText = Text(label)
            .font(labelFont)
            .foregroundStyle(textColor.opacity(dimLabel ? 0.75 : 1))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: labelWidth, alignment: monitor.alignRight ? .trailing : .leading)
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

    private var memoryRow: some View {
        let memory = monitor.memory
        let value = "\(Fmt.memNumber(memory.used)) / \(Fmt.mem(memory.total))"
        return row(label: l10n.t(.memory), value: value) { memoryBar }
            .overlay(alignment: monitor.alignRight ? .trailing : .leading) {
                // Точка предупреждения о нехватке памяти: молча, но заметно.
                if memory.pressure != .normal {
                    Circle()
                        .fill(memory.pressure == .critical ? Color.red : Color.orange)
                        .frame(width: 4, height: 4)
                        .offset(x: monitor.alignRight ? 3 : -3)
                }
            }
    }

    private func volumeRow(_ volume: VolumeUsage) -> some View {
        row(
            label: volume.isRoot ? l10n.t(.disk) : volume.name,
            dimLabel: !volume.isRoot,
            value: "\(Fmt.disk(volume.free)) \(l10n.t(.free))"
        ) {
            bar(fraction: volume.usedFraction)
        }
    }

    // MARK: - Полоски

    private func bar(fraction: Double) -> some View {
        let clamped = min(1, max(0, fraction))
        return ZStack(alignment: .leading) {
            Capsule(style: .continuous).fill(trackColor)
            Capsule(style: .continuous)
                .fill(loadColor(clamped))
                .frame(width: max(clamped > 0 ? barHeight : 0, barWidth * clamped))
        }
        .frame(width: barWidth, height: barHeight)
    }

    /// Столбик на каждое логическое ядро; ширина полоски фиксирована,
    /// столбики делят её поровну — окошко не «дышит» при смене числа ядер.
    private var coreStrip: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(Array(monitor.cpu.perCore.enumerated()), id: \.offset) { _, load in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(trackColor)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(loadColor(load))
                        .frame(height: max(1.5, coreHeight * min(1, max(0, load))))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: barWidth, height: coreHeight)
    }

    /// Полоска памяти составная: приложения → wired → сжатая → файловый кэш.
    /// Хвост дорожки — свободная память.
    private var memoryBar: some View {
        let memory = monitor.memory
        let fill = loadColor(memory.usedFraction)
        func width(_ bytes: UInt64) -> CGFloat {
            memory.total > 0 ? barWidth * CGFloat(Double(bytes) / Double(memory.total)) : 0
        }
        return ZStack(alignment: .leading) {
            trackColor
            HStack(spacing: 0) {
                Rectangle().fill(fill).frame(width: width(memory.app))
                Rectangle().fill(fill.opacity(0.72)).frame(width: width(memory.wired))
                Rectangle().fill(fill.opacity(0.48)).frame(width: width(memory.compressed))
                Rectangle().fill(textColor.opacity(0.3)).frame(width: width(memory.cached))
            }
        }
        .frame(width: barWidth, height: barHeight)
        .clipShape(Capsule(style: .continuous))
    }

    // MARK: - Разбивка памяти

    private var memoryDetails: some View {
        let memory = monitor.memory
        var rows: [(String, String)] = [
            (l10n.t(.appMemory), Fmt.mem(memory.app)),
            (l10n.t(.wired), Fmt.mem(memory.wired)),
            (l10n.t(.compressed), Fmt.mem(memory.compressed)),
            (l10n.t(.cached), Fmt.mem(memory.cached)),
            (l10n.t(.freeMemory), Fmt.mem(memory.free)),
        ]
        if memory.swapTotal > 0 {
            rows.append((l10n.t(.swap), Fmt.mem(memory.swapUsed)))
        }
        rows.append((l10n.t(.pressure), pressureTitle))

        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                HStack(spacing: rowSpacing) {
                    if monitor.alignRight {
                        Text(item.1)
                        Spacer(minLength: 4)
                        Text(item.0)
                    } else {
                        Text(item.0)
                        Spacer(minLength: 4)
                        Text(item.1)
                    }
                }
                .font(detailFont)
                .foregroundStyle(textColor.opacity(0.7))
                .lineLimit(1)
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
