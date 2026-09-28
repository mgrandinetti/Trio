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

    static func historicalMetric(_ value: String?, date: Date?, at now: Date) -> String? {
        guard let date, date <= now, let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value != "--" else { return nil }
        return value
    }

    /// Retain the last dated metric when a source is temporarily unavailable; never redate it.
    static func retainedMetric(
        value: String?, date: Date?, previousValue: String?, previousDate: Date?, at now: Date
    ) -> (value: String?, date: Date?) {
        let current = historicalMetric(value, date: date, at: now)
        let previous = historicalMetric(previousValue, date: previousDate, at: now)
        if let previous, let previousDate, current == nil || previousDate > (date ?? .distantPast) {
            return (previous, previousDate)
        }
        return (current, current == nil ? nil : date)
    }

    static func isFresh(_ timestamp: Date?, at date: Date) -> Bool {
        guard let timestamp else { return false }
        let age = date.timeIntervalSince(timestamp)
        return age >= 0 && age < freshnessInterval
    }

    /// Historical display is allowed only when the sensor timestamp is known and not in the future.
    func historicalGlucose(at date: Date) -> String? {
        guard let glucoseDate, glucoseDate <= date, !glucose.isEmpty, glucose != "--" else { return nil }
        return glucose
    }

    /// Match the app's IOB source ordering while retaining the source timestamp.
    static func latestIOB(
        determinationValue: Decimal?, determinationDate: Date?, fileValue: Decimal?, fileDate: Date?
    ) -> (value: Decimal?, date: Date?) {
        if let fileValue, let fileDate {
            if let determinationValue, let determinationDate, determinationDate >= fileDate {
                return (determinationValue, determinationDate)
            }
            return (fileValue, fileDate)
        }
        return (determinationValue, determinationDate)
    }

    func displayValue(_ value: Double) -> Double {
        unit == "mmol/L" ? value * 0.0555 : value
    }
}
