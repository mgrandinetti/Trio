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

let expiredMetricDate = now.addingTimeInterval(-600)
check(TrioWidgetSnapshot.historicalMetric("0", date: expiredMetricDate, at: now) == "0", "Dated historical zero is a real value")
check(TrioWidgetSnapshot.historicalMetric("2.3", date: nil, at: now) == nil, "Undated metrics must remain unknown")
check(TrioWidgetSnapshot.historicalMetric("2.3", date: now.addingTimeInterval(1), at: now) == nil, "Future metrics must remain unknown")
check(TrioWidgetSnapshot.historicalMetric("--", date: now, at: now) == nil, "Placeholder must not become historical data")
let retained = TrioWidgetSnapshot.retainedMetric(value: nil, date: nil, previousValue: "2.3", previousDate: expiredMetricDate, at: now)
check(retained.value == "2.3" && retained.date == expiredMetricDate, "Missing sources retain value and original age")
check(!TrioWidgetSnapshot.isFresh(retained.date, at: now), "Retaining history must not make a stale metric fresh")
let updated = TrioWidgetSnapshot.retainedMetric(value: "0", date: now, previousValue: "2.3", previousDate: expiredMetricDate, at: now)
check(updated.value == "0" && updated.date == now, "New real zero replaces history")
let older = TrioWidgetSnapshot.retainedMetric(value: "4", date: expiredMetricDate, previousValue: "2", previousDate: now, at: now)
check(older.value == "2" && older.date == now, "Older source must not replace newer history")
print("Historical metric checks passed")
