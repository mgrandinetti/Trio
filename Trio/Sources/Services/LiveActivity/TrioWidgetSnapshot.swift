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

/// Local timing metadata only. Separate keys prevent the app and extension overwriting each other.
enum TrioWidgetDiagnostics {
    enum Event: String, CaseIterable {
        case glucoseObserved, glucoseLoaded, glucoseLoadFailed
        case determinationLoaded, determinationLoadFailed
        case appActive, appBackground, snapshotSaved, reloadRequested, timelineRead
    }

    static func record(
        _ event: Event, glucoseDate: Date? = nil, iobDate: Date? = nil, cobDate: Date? = nil,
        at date: Date = Date(), defaults: UserDefaults? = TrioWidgetSnapshot.defaults
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var fields = ["event": formatter.string(from: date)]
        for (key, timestamp) in [("glucose", glucoseDate), ("iob", iobDate), ("cob", cobDate)] {
            fields[key] = timestamp.map { formatter.string(from: $0) } ?? "missing"
        }
        defaults?.set(fields, forKey: "TrioWidgetDiagnostics.v1." + event.rawValue)
    }

    static func report(defaults: UserDefaults? = TrioWidgetSnapshot.defaults) -> String {
        guard let defaults else { return "Widget diagnostics: App Group unavailable" }
        var lines = ["Widget diagnostics v1 (UTC)", "Latest event of each kind; source timestamps, no measurement values."]
        for event in Event.allCases {
            guard let fields = defaults.dictionary(forKey: "TrioWidgetDiagnostics.v1." + event.rawValue)
                as? [String: String] else {
                lines.append(event.rawValue + ": not recorded")
                continue
            }
            lines.append(event.rawValue + ": " + (fields["event"] ?? "missing"))
            for key in ["glucose", "iob", "cob"] where fields[key] != "missing" {
                lines.append("  " + key + ": " + (fields[key] ?? "missing"))
            }
        }
        return lines.joined(separator: "\n")
    }
}
