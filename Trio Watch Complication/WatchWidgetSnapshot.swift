import Foundation

/// A compact, read-only copy of the latest CGM state for the Watch complication.
/// The Watch app writes it after receiving a valid phone payload; the complication
/// only renders it and never uses it for treatment decisions.
struct WatchWidgetSnapshot: Codable {
    struct GlucosePoint: Codable {
        let date: Date
        let glucose: Double
    }

    let glucose: String?
    let trend: String?
    let delta: String?
    let glucoseColor: String?
    let glucoseDate: Date?
    let units: String?
    let glucosePoints: [GlucosePoint]

    static let storageKey = "TrioWatchComplication.snapshot"
    static let maxGlucoseAge: TimeInterval = 6 * 60

    func isCurrent(at date: Date) -> Bool {
        guard let glucoseDate else { return false }
        return glucoseDate <= date && date.timeIntervalSince(glucoseDate) < Self.maxGlucoseAge
    }

    static func load(from defaults: UserDefaults?) -> Self? {
        guard let defaults, let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save(to defaults: UserDefaults?) {
        guard let defaults, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func sharedDefaults() -> UserDefaults? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "TrioAppGroup") as? String,
              !group.isEmpty,
              !group.hasPrefix("$(")
        else { return nil }
        return UserDefaults(suiteName: group)
    }
}
