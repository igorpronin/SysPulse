// Единственный источник версии приложения.
// build-app.sh извлекает её отсюда в Info.plist; About показывает её же.
// Каждое изменение функционала сопровождается повышением версии здесь.
enum AppInfo {
    static let name = "SysPulse"
    static let version = "0.10.0"
}
