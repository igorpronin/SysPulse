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
            Toggle(l10n.t(.showFolders), isOn: $monitor.showFolders)

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

// Окно «Folders»: список отслеживаемых папок. У каждой — псевдоним (если задан,
// в панели показывается он), частота обхода и кнопка ручного пересканирования.
struct FoldersSettingsView: View {
    @ObservedObject var folders: FolderTracker
    @ObservedObject var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(folders.folders) { folder in
                        row(folder)
                    }
                }
                .padding(.trailing, 4)
            }
            Divider()
            Button(l10n.t(.addFolder)) { pickFolder() }
        }
        .padding(16)
        .frame(width: 580, height: 340)
    }

    @ViewBuilder
    private func row(_ folder: TrackedFolder) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(folder.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 150, alignment: .leading)

                // Плейсхолдер — имя папки: видно, что подставится, если не задать.
                TextField(folder.name, text: Binding(
                    get: { folder.alias },
                    set: { folders.setAlias($0, for: folder) }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                .help(l10n.t(.alias))

                Picker("", selection: Binding(
                    get: { folder.interval },
                    set: { folders.setInterval($0, for: folder) }
                )) {
                    ForEach(ScanInterval.allCases, id: \.rawValue) { interval in
                        Text(l10n.t(interval.key)).tag(interval)
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                Button {
                    folders.rescan(folder)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(l10n.t(.rescan))
                .disabled(folders.isScanning(folder))

                Button {
                    folders.remove(folder)
                } label: {
                    Image(systemName: "minus")
                }
                .help(l10n.t(.remove))
            }
            HStack(spacing: 6) {
                Text(folder.path)
                    .lineLimit(1)
                    .truncationMode(.head)
                Text("·")
                Text(status(folder))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func status(_ folder: TrackedFolder) -> String {
        if folders.isScanning(folder) { return l10n.t(.scanning) }
        guard let scan = folders.scan(for: folder) else { return "—" }
        return scan.failed ? l10n.t(.noAccess) : Fmt.disk(scan.size)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = l10n.t(.addFolder).replacingOccurrences(of: "…", with: "")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            folders.add(path: url.path)
        }
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
