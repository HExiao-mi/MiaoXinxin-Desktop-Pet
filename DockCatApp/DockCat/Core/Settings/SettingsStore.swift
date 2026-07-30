import Foundation

final class SettingsStore {
    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]
    private let key = "DockCat.AppSettings.v1"

    init(defaults: UserDefaults = .standard, preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return AppSettings.defaults(for: AppLanguage.preferred(from: preferredLanguages()))
        }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            DockCatLog.app.error("Failed to decode settings: \(error.localizedDescription)")
            return AppSettings.defaults(for: AppLanguage.preferred(from: preferredLanguages()))
        }
    }

    func save(_ settings: AppSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: key)
        } catch {
            DockCatLog.app.error("Failed to encode settings: \(error.localizedDescription)")
        }
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
