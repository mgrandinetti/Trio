import Charts
import SwiftUI
import WidgetKit

struct TrioStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: TrioWidgetSnapshot?

    var isFresh: Bool { TrioWidgetSnapshot.isFresh(snapshot?.glucoseDate, at: date) }
    var glucose: String { isFresh ? (snapshot?.glucose ?? "--") : "--" }
    var trend: String { isFresh ? (snapshot?.trend ?? "") : "" }
}

struct TrioStatusProvider: TimelineProvider {
    func placeholder(in _: Context) -> TrioStatusEntry {
        TrioStatusEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in _: Context, completion: @escaping (TrioStatusEntry) -> Void) {
        completion(TrioStatusEntry(date: Date(), snapshot: TrioWidgetSnapshot.load()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TrioStatusEntry>) -> Void) {
        let now = Date()
        let snapshot = TrioWidgetSnapshot.load()
        var dates = [now]
        // Expire each metric even when the phone stops delivering updates.
        for timestamp in [snapshot?.glucoseDate, snapshot?.iobDate, snapshot?.determinationDate].compactMap({ $0 }) {
            let expiry = timestamp.addingTimeInterval(TrioWidgetSnapshot.freshnessInterval)
            if expiry > now { dates.append(expiry) }
        }
        let entries = Array(Set(dates)).sorted().map { TrioStatusEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

struct TrioStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrioStatusEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("Trio \(entry.glucose) \(entry.trend) \(entry.snapshot?.unit ?? "")")
            case .accessoryCircular:
                VStack(spacing: 1) {
                    Text(entry.glucose).font(.system(.title2, design: .rounded, weight: .semibold))
                    Text(entry.isFresh ? entry.trend : "Trio").font(.caption2)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    glucoseRow
                    freshnessLabel
                }
            default:
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Image(systemName: "drop.circle").foregroundStyle(.blue)
                            Text("Trio").font(.caption.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        glucoseRow
                        freshnessLabel
                        HStack(spacing: 12) {
                            metric("IOB", value: entry.snapshot?.iob, date: entry.snapshot?.iobDate, unit: "U")
                            metric("COB", value: entry.snapshot?.cob, date: entry.snapshot?.determinationDate, unit: "g")
                        }
                    }
                    if family == .systemMedium, let snapshot = entry.snapshot {
                        glucoseChart(snapshot)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .minimumScaleFactor(0.65)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "Trio://"))
        .privacySensitive()
    }

    private var glucoseRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.glucose)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(entry.trend).font(.title3)
            }
            .foregroundStyle(entry.isFresh ? Color.blue : Color.secondary)
            Text(entry.snapshot?.unit ?? " ").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var freshnessLabel: some View {
        HStack(spacing: 3) {
            if entry.isFresh {
                Text(entry.snapshot?.delta ?? "").monospacedDigit()
            } else {
                Image(systemName: "clock.badge.exclamationmark")
            }
            if let date = entry.snapshot?.glucoseDate {
                Text(date, style: .time)
            } else {
                Text("Apri Trio")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityLabel(entry.isFresh ? "Ultima lettura" : "Dati glicemia non aggiornati")
    }

    private func metric(_ title: String, value: String?, date: Date?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text("\(TrioWidgetSnapshot.isFresh(date, at: entry.date) ? (value ?? "--") : "--") \(unit)")
                .font(.caption.weight(.medium)).monospacedDigit().lineLimit(1)
        }
    }

    private func glucoseChart(_ snapshot: TrioWidgetSnapshot) -> some View {
        let start = entry.date.addingTimeInterval(-3 * 60 * 60)
        let readings = snapshot.readings.filter { $0.date >= start && $0.date <= entry.date }
        return Chart {
            RectangleMark(
                xStart: .value("Inizio", start), xEnd: .value("Fine", entry.date),
                yStart: .value("Basso", snapshot.displayValue(snapshot.low)),
                yEnd: .value("Alto", snapshot.displayValue(snapshot.high))
            ).foregroundStyle(.blue.opacity(0.08))
            ForEach(readings, id: \.date) { reading in
                PointMark(x: .value("Ora", reading.date), y: .value("Glicemia", snapshot.displayValue(reading.value)))
                    .symbolSize(9)
                    .foregroundStyle(entry.isFresh ? Color.blue : Color.secondary)
            }
        }
        .chartXScale(domain: start ... entry.date)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour)) {
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel()
            }
        }
        .accessibilityLabel("Glicemia delle ultime tre ore, \(snapshot.unit)")
    }
}

struct TrioStatusWidget: Widget {
    let kind = "TrioStatusWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrioStatusProvider()) { entry in
            TrioStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Trio: glicemia e stato")
        .description("Glicemia, trend, insulina e carboidrati attivi da Trio.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
