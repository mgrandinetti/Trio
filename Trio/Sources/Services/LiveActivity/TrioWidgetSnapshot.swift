import Foundation

/// Read-only presentation data. Glucose timestamps always come from the sensor sample.
struct TrioWidgetSnapshot: Codable, Equatable {
    struct Reading: Codable, Equatable {
        let date: Date
        let value: Double // mg/dL, as stored by Trio
    }

    static let storageKey = "TrioWidgetSnapshot.v1"
    static let freshnessInterval: TimeInterval = 6 * 60
    let glucose: String
    let glucoseDate: Date?
    let trend: String?
    let delta: String?
    let unit: String
    let readings: [Reading]
    let low: Double
    let high: Double
    let iob: String?
    let iobDate: Date?
    let cob: String?
    let determinationDate: Date?

    static var defaults: UserDefaults? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "TrioAppGroup") as? String,
              !group.isEmpty, !group.contains("$(") else { return nil }
        return UserDefaults(suiteName: group)
    }

    static func load() -> Self? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    @discardableResult func save() -> Bool {
        guard self != Self.load(), let defaults = Self.defaults,
              let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }

    static func isFresh(_ timestamp: Date?, at date: Date) -> Bool {
        guard let timestamp else { return false }
        let age = date.timeIntervalSince(timestamp)
        return age >= 0 && age < freshnessInterval
    }

    func displayValue(_ value: Double) -> Double {
        unit == "mmol/L" ? value * 0.0555 : value
    }
}
