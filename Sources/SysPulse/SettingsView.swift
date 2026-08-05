import SwiftUI

// Окно «Metrics settings»: что показывать в окошке и в меню-баре,
// как часто опрашивать систему и какие тома выводить.
struct MetricsSettingsView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(l10n.t(.showCPU), isOn: $monitor.showCPU)
            Toggle(l10n.t(.showCores), isOn: $monitor.showCores)
                .disabled(!monitor.showCPU)
                .padding(.leading, 18)
            Toggle(l10n.t(.showMemory), isOn: $monitor.showMemory)
            Toggle(l10n.t(.showMemoryDetails), isOn: $monitor.showMemoryDetails)
                .disabled(!monitor.showMemory)
                .padding(.leading, 18)
            Toggle(l10n.t(.showDisks), isOn: $monitor.showDisks)

            Divider()

            HStack(spacing: 8) {
                Text(l10n.t(.updateInterval))
                Picker("", selection: $monitor.interval) {
                    ForEach(SystemMonitor.intervals, id: \.self) { value in
                        Text(intervalTitle(value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
            }

            Divider()

            Text(l10n.t(.menuBarMenu))
                .font(.system(.body).weight(.semibold))
            Toggle(l10n.t(.cpu), isOn: $monitor.menuBarCPU)
            Toggle(l10n.t(.memory), isOn: $monitor.menuBarMemory)
            Toggle(l10n.t(.disk), isOn: $monitor.menuBarDisk)

            Divider()

            Text(l10n.t(.volumesSection))
                .font(.system(.body).weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(monitor.volumes) { volume in
                        Toggle(isOn: Binding(
                            get: { !monitor.hiddenVolumes.contains(volume.id) },
                            set: { monitor.setVolume(volume.id, visible: $0) }
                        )) {
                            Text("\(volume.name) — \(Fmt.disk(volume.free)) \(l10n.t(.free))")
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxHeight: 96)
        }
        .padding(16)
        .frame(width: 340)
    }

    // 0.5 s / 1 s / 2 s / 5 s — целые без лишнего нуля.
    private func intervalTitle(_ value: Double) -> String {
        String(format: value < 1 ? "%.1f s" : "%.0f s", value)
    }
}

// Окно «UI settings»: внешний вид окошка — непрозрачность и контраст.
struct UISettingsView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(l10n.t(.opacity))
                Slider(value: $monitor.opacity, in: 0...1)
            }
            Toggle(l10n.t(.contrast), isOn: $monitor.contrast)
        }
        .padding(16)
        .frame(width: 320)
    }
}
