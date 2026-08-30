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
            Toggle(l10n.t(.showGPU), isOn: $monitor.showGPU)
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

// Окно «Folders»: список отслеживаемых папок.
//
// Строки здесь — черновики, а не сам список трекера. «Добавить папку» создаёт
// пустую строку, и запись попадает в сохранённый список только когда путь
// проверен: существует и это папка. Пока путь пуст или неверен, поле обведено
// красным, а в настройках ничего нет — закрыли окно, и черновик просто исчез.
struct FoldersSettingsView: View {
    @ObservedObject var folders: FolderTracker
    @ObservedObject var l10n = L10n.shared

    struct Row: Identifiable {
        let id: UUID
        var path: String
        var alias: String
        var interval: ScanInterval
    }

    @State private var rows: [Row] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach($rows) { $row in
                        rowView($row)
                    }
                }
                .padding(.trailing, 4)
            }
            Divider()
            Button(l10n.t(.addFolder)) {
                rows.append(Row(id: UUID(), path: "", alias: "", interval: .tenMinutes))
            }
        }
        .padding(16)
        .frame(width: 600, height: 360)
        .onAppear(perform: reload)
        // Папку могли удалить с диска — трекер выкидывает её сам, и список
        // в открытом окне должен это отразить.
        .onChange(of: folders.folders.count) { _ in reload() }
    }

    private func reload() {
        let saved = folders.folders.map {
            Row(id: $0.id, path: $0.path, alias: $0.alias, interval: $0.interval)
        }
        // Черновики, которые человек ещё не довёл до ума, не трогаем.
        let drafts = rows.filter { row in
            !saved.contains { $0.id == row.id } && FolderTracker.validPath(row.path) == nil
        }
        rows = saved + drafts
    }

    @ViewBuilder
    private func rowView(_ row: Binding<Row>) -> some View {
        let valid = FolderTracker.validPath(row.wrappedValue.path) != nil
        let empty = row.wrappedValue.path.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField(l10n.t(.folderPath), text: row.path)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 370)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.red, lineWidth: empty || valid ? 0 : 1.5)
                    )
                    .onChange(of: row.wrappedValue.path) { _ in commit(row.wrappedValue) }

                Button { choose(row) } label: { Image(systemName: "folder") }
                    .help(l10n.t(.chooseFolder))

                Spacer()

                Button {
                    if let folder = folders.folders.first(where: { $0.id == row.wrappedValue.id }) {
                        folders.rescan(folder)
                    }
                } label: { Image(systemName: "arrow.clockwise") }
                    .help(l10n.t(.rescan))
                    .disabled(!valid)

                Button {
                    folders.remove(id: row.wrappedValue.id)
                    rows.removeAll { $0.id == row.wrappedValue.id }
                } label: { Image(systemName: "minus") }
                    .help(l10n.t(.remove))
            }

            HStack(spacing: 6) {
                TextField(placeholder(for: row.wrappedValue), text: row.alias)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                    .help(l10n.t(.alias))
                    .onChange(of: row.wrappedValue.alias) { _ in commit(row.wrappedValue) }

                Picker("", selection: row.interval) {
                    ForEach(ScanInterval.allCases, id: \.rawValue) { interval in
                        Text(l10n.t(interval.key)).tag(interval)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: row.wrappedValue.interval) { _ in commit(row.wrappedValue) }

                Text(status(row.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!valid)
        }
    }

    /// Плейсхолдер псевдонима — имя папки: видно, что подставится, если не задать.
    private func placeholder(for row: Row) -> String {
        let name = URL(fileURLWithPath: row.path).lastPathComponent
        return name.isEmpty ? l10n.t(.alias) : name
    }

    /// Переносит строку в сохранённый список, если путь годится, и убирает
    /// оттуда, если перестал годиться.
    private func commit(_ row: Row) {
        guard let path = FolderTracker.validPath(row.path) else {
            folders.remove(id: row.id)
            return
        }
        folders.upsert(id: row.id, path: path, alias: row.alias, interval: row.interval)
    }

    private func status(_ row: Row) -> String {
        guard let folder = folders.folders.first(where: { $0.id == row.id }) else { return "" }
        if folders.isScanning(folder) { return l10n.t(.scanning) }
        guard let scan = folders.scan(for: folder) else { return "—" }
        return scan.failed ? l10n.t(.noAccess) : Fmt.disk(scan.size)
    }

    private func choose(_ row: Binding<Row>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let current = FolderTracker.validPath(row.wrappedValue.path) {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        row.wrappedValue.path = url.path
        commit(row.wrappedValue)
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
