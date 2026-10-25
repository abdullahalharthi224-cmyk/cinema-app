import Foundation

/// Gives every profile its own look and settings: theme and colour, language,
/// app icon, Home layout, playback and subtitles, private viewing and recent
/// searches. Switching profile puts the current values away under the old
/// profile and brings back the new one's. A profile that has never been used
/// starts with the current values.
@MainActor
enum ProfileSettings {
    /// The settings that belong to a profile (UserDefaults key prefixes).
    static let prefixes = ["appearance.", "playback.", "home.", "privacy.", "search.", AppLanguage.storageKey]

    private static func storageKey(_ profileID: UUID) -> String { "profileSettings." + profileID.uuidString }

    /// Puts away `from`'s settings and brings back `to`'s.
    static func switchProfile(from oldID: UUID?, to newID: UUID) {
        guard oldID != newID else { return }
        if let oldID { save(for: oldID) }
        load(for: newID)
    }

    static func save(for profileID: UUID) {
        let defaults = UserDefaults.standard
        var snapshot: [String: CinemaBackup.Setting] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where belongs(key) {
            if let setting = CinemaBackup.Setting(value) { snapshot[key] = setting }
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey(profileID))
        }
    }

    static func load(for profileID: UUID) {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: storageKey(profileID)),
              let snapshot = try? JSONDecoder().decode([String: CinemaBackup.Setting].self, from: data)
        else { return }   // Never used: keeps the current settings.
        for key in defaults.dictionaryRepresentation().keys where belongs(key) && snapshot[key] == nil {
            defaults.removeObject(forKey: key)
        }
        for (key, setting) in snapshot {
            setting.write(to: defaults, key: key)
        }
        applyToApp()
    }

    static func forget(_ profileID: UUID) {
        UserDefaults.standard.removeObject(forKey: storageKey(profileID))
    }

    /// Makes every screen pick up the settings now in UserDefaults.
    static func applyToApp() {
        Appearance.shared.reload()
        HomeLayoutStore.shared.reload()
        HomeCustomization.shared.reload()
        PlaybackSettings.shared.reload()
        PrivacySettings.shared.reload()
        Task { await AppIconStore.applySaved() }
    }

    private static func belongs(_ key: String) -> Bool {
        prefixes.contains { key.hasPrefix($0) }
    }
}

extension CinemaBackup.Setting {
    init?(_ value: Any) {
        switch value {
        case let number as NSNumber:
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        case let string as String:
            self = .string(string)
        case let data as Data:
            self = .data(data)
        case let strings as [String]:
            self = .strings(strings)
        default:
            return nil
        }
    }

    func write(to defaults: UserDefaults, key: String) {
        switch self {
        case .bool(let value): defaults.set(value, forKey: key)
        case .number(let value): defaults.set(value, forKey: key)
        case .string(let value): defaults.set(value, forKey: key)
        case .data(let value): defaults.set(value, forKey: key)
        case .strings(let value): defaults.set(value, forKey: key)
        }
    }
}
