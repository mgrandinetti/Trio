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
        TrioWidgetDiagnostics.record(
            .timelineRead, glucoseDate: snapshot?.glucoseDate, iobDate: snapshot?.iobDate,
            cobDate: snapshot?.determinationDate
        )
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
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(entry.glucose)
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                        Text(entry.trend).font(.callout)
                        Text(entry.snapshot?.unit ?? "").font(.caption2).foregroundStyle(.secondary)
                    }
                    freshnessLabel
                }
            default:
                homeWidget
            }
        }
        .minimumScaleFactor(0.65)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "Trio://"))
        .privacySensitive()
    }

    private var homeWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill").foregroundStyle(.blue)
                Text("Trio").fontWeight(.semibold)
                Spacer(minLength: 4)
                readingTime
            }
            .font(.caption2)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    if family == .systemMedium, !entry.isFresh, historicalGlucose != nil {
                        Text("Ultimo valore").font(.caption2).foregroundStyle(.secondary)
                    }
                    glucoseRow
                    if entry.isFresh {
                        Text(entry.snapshot?.delta ?? "").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Label("Dato non aggiornato", systemImage: "clock.badge.exclamationmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if family == .systemMedium, let snapshot = entry.snapshot {
                    glucoseChart(snapshot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)

            Divider()
            HStack(spacing: 12) {
                metric("IOB", value: entry.snapshot?.iob, date: entry.snapshot?.iobDate, unit: "U")
                    .frame(maxWidth: .infinity, alignment: .leading)
                metric("COB", value: entry.snapshot?.cob, date: entry.snapshot?.determinationDate, unit: "g")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var historicalGlucose: String? { entry.snapshot?.historicalGlucose(at: entry.date) }

    private var readingTime: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if historicalGlucose != nil, let date = entry.snapshot?.glucoseDate {
                HStack(spacing: 3) {
                    Text("Lettura")
                    Text(date, style: .time).monospacedDigit()
                }
                if #available(iOS 18.0, *) {
                    HStack(spacing: 3) {
                        Text("Dato di")
                        Text(.currentDate, format: .offset(
                            to: date, allowedFields: [.minute], maxFieldCount: 1, sign: .never
                        ))
                        Text("fa")
                    }
                }
                // Earlier iOS versions retain the absolute reading time, without a seconds counter.
                if entry.date.timeIntervalSince(date) >= 24 * 60 * 60 {
                    Text(date, style: .date)
                }
            } else {
                Text("Lettura non disponibile")
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var glucoseRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(historicalGlucose ?? "--")
                    .font(.system(size: family == .systemMedium ? 40 : 34, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .monospacedDigit()
                Text(entry.trend).font(.title3.weight(.medium))
            }
            .foregroundStyle(entry.isFresh ? Color.blue : Color.secondary)
            Text(entry.snapshot?.unit ?? " ").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var freshnessLabel: some View {
        HStack(spacing: 5) {
            if entry.isFresh {
                Text(entry.snapshot?.delta ?? "").monospacedDigit()
                Text("·")
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
        .lineLimit(1)
        .foregroundStyle(.secondary)
        .accessibilityLabel(entry.isFresh ? "Ultima lettura" : "Dati glicemia non aggiornati")
    }

    private func metric(_ title: String, value: String?, date: Date?, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text("\(TrioWidgetSnapshot.isFresh(date, at: entry.date) ? (value ?? "--") : "--") \(unit)")
                .font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1)
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
