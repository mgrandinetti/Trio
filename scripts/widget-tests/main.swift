import Foundation

let now = Date(timeIntervalSince1970: 1_800_000_000)
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
check(!TrioWidgetSnapshot.isFresh(nil, at: now), "Missing data must not look fresh")
check(TrioWidgetSnapshot.isFresh(now.addingTimeInterval(-359), at: now), "Fresh sensor timestamp")
check(!TrioWidgetSnapshot.isFresh(now.addingTimeInterval(-360), at: now), "Expiry boundary")
check(!TrioWidgetSnapshot.isFresh(now.addingTimeInterval(1), at: now), "Future timestamps must not look fresh")
let sample = TrioWidgetSnapshot(
    glucose: "5,6", glucoseDate: now, trend: "→", delta: nil, unit: "mmol/L",
    readings: [.init(date: now, value: 100)], low: 70, high: 180,
    iob: nil, iobDate: nil, cob: nil, determinationDate: nil
)
check(abs(sample.displayValue(100) - 5.55) < 0.0001, "Use Trio conversion without parsing localized display strings")
let restored = try JSONDecoder().decode(TrioWidgetSnapshot.self, from: JSONEncoder().encode(sample))
check(restored == sample, "App Group snapshot round trip")
check(restored.iob == nil && restored.cob == nil, "Missing therapy metrics stay unknown")
print("Widget snapshot checks passed")

let watch = WatchWidgetSnapshot(glucose: "5,6", trend: "→", delta: nil, glucoseColor: nil,
                                glucoseDate: now, units: "mmol/L", glucosePoints: [])
check(watch.isCurrent(at: now.addingTimeInterval(359)), "Watch fresh data")
check(!watch.isCurrent(at: now.addingTimeInterval(360)), "Watch expiration at timeline entry date")
check(!watch.isCurrent(at: now.addingTimeInterval(-1)), "Watch rejects future timestamps")
print("Watch snapshot checks passed")

check(sample.historicalGlucose(at: now) == "5,6", "Keep localized glucose intact")
check(sample.historicalGlucose(at: now.addingTimeInterval(360)) == "5,6", "Expired glucose remains historical")
check(!TrioWidgetSnapshot.isFresh(sample.glucoseDate, at: now.addingTimeInterval(360)), "Historical glucose must remain stale")
check(sample.historicalGlucose(at: now.addingTimeInterval(-1)) == nil, "Do not display future historical readings")
var missingTimestamp = sample
let encoded = try JSONEncoder().encode(sample)
var fields = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
fields.removeValue(forKey: "glucoseDate")
missingTimestamp = try JSONDecoder().decode(TrioWidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: fields))
check(missingTimestamp.historicalGlucose(at: now) == nil, "Undated glucose must not be displayed as history")
print("Historical glucose display checks passed")

let newerFile = TrioWidgetSnapshot.latestIOB(determinationValue: 1, determinationDate: now.addingTimeInterval(-400), fileValue: 2, fileDate: now)
check(newerFile.value == 2 && newerFile.date == now, "Widget must use newer file IOB with its original timestamp")
let newerDetermination = TrioWidgetSnapshot.latestIOB(determinationValue: 1, determinationDate: now, fileValue: 2, fileDate: now.addingTimeInterval(-400))
check(newerDetermination.value == 1 && newerDetermination.date == now, "Newer determination wins")
let undatedFile = TrioWidgetSnapshot.latestIOB(determinationValue: 1, determinationDate: now.addingTimeInterval(-400), fileValue: 2, fileDate: nil)
check(undatedFile.value == 1 && !TrioWidgetSnapshot.isFresh(undatedFile.date, at: now), "Do not refresh timestamp or use undated file IOB")
print("Widget IOB source selection checks passed")

let diagnosticSuite = "TrioWidgetDiagnosticsTests." + UUID().uuidString
let diagnosticDefaults = UserDefaults(suiteName: diagnosticSuite)!
defer { diagnosticDefaults.removePersistentDomain(forName: diagnosticSuite) }
let sourceDate = now.addingTimeInterval(-400)
TrioWidgetDiagnostics.record(.snapshotSaved, glucoseDate: sourceDate, at: now, defaults: diagnosticDefaults)
TrioWidgetDiagnostics.record(.timelineRead, glucoseDate: sourceDate, at: now.addingTimeInterval(30), defaults: diagnosticDefaults)
let savedEvent = diagnosticDefaults.dictionary(forKey: "TrioWidgetDiagnostics.v1.snapshotSaved") as! [String: String]
let readEvent = diagnosticDefaults.dictionary(forKey: "TrioWidgetDiagnostics.v1.timelineRead") as! [String: String]
check(savedEvent["glucose"] == readEvent["glucose"], "Diagnostic events must preserve stale source time")
check(savedEvent["event"] != readEvent["event"], "App and extension events must remain independently readable")
check(diagnosticDefaults.data(forKey: TrioWidgetSnapshot.storageKey) == nil, "Diagnostics must not alter clinical snapshot storage")
check(TrioWidgetDiagnostics.report(defaults: diagnosticDefaults).contains("reloadRequested: not recorded"), "Missing events must remain distinguishable")
check(TrioWidgetDiagnostics.report(defaults: nil).contains("unavailable"), "Missing App Group must be reported")
print("Widget diagnostic isolation checks passed")
