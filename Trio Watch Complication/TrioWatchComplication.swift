import SwiftUI
import WidgetKit

struct TrioWatchComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchWidgetSnapshot?
}

struct TrioWatchComplicationProvider: TimelineProvider {
    func placeholder(in _: Context) -> TrioWatchComplicationEntry {
        .init(date: Date(), snapshot: .init(
            glucose: "112", trend: "Flat", delta: "+1", glucoseColor: "#FFFFFF",
            glucoseDate: Date(), units: "mg/dL", glucosePoints: []
        ))
    }

    func getSnapshot(in _: Context, completion: @escaping (TrioWatchComplicationEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TrioWatchComplicationEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var entries = [current]
        if let expiry = current.snapshot?.glucoseDate?.addingTimeInterval(WatchWidgetSnapshot.maxGlucoseAge), expiry > now {
            // This entry renders the CGM as unavailable at the exact expiry.
            entries.append(entry(at: expiry, snapshot: current.snapshot))
            completion(Timeline(entries: entries, policy: .after(expiry.addingTimeInterval(60))))
        } else {
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60))))
        }
    }

    private func entry(at date: Date = Date(), snapshot: WatchWidgetSnapshot? = nil) -> TrioWatchComplicationEntry {
        .init(date: date, snapshot: snapshot ?? WatchWidgetSnapshot.load(from: WatchWidgetSnapshot.sharedDefaults()))
    }
}

struct TrioWatchComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrioWatchComplicationEntry

    private var snapshot: WatchWidgetSnapshot? { entry.snapshot?.isCurrent(at: entry.date) == true ? entry.snapshot : nil }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: unavailable
        }
    }

    private var circular: some View {
        ZStack {
            Circle().stroke(snapshot == nil ? .secondary.opacity(0.35) : glucoseColor, lineWidth: 3)
            if let snapshot {
                VStack(spacing: 0) {
                    Text(snapshot.glucose ?? "--").font(.system(.title3, design: .rounded).weight(.bold)).minimumScaleFactor(0.6)
                    Text(trendSymbol(snapshot.trend)).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("--").font(.title3).foregroundStyle(.secondary)
            }
        }
        .widgetBackground(backgroundView: Color.clear)
    }

    private var corner: some View {
        Text(snapshot?.glucose ?? "--")
            .widgetCurvesContent()
            .widgetLabel {
                if let snapshot {
                    Text("\(trendSymbol(snapshot.trend)) \(snapshot.delta ?? snapshot.units ?? "")")
                } else {
                    Text("CGM non aggiornato")
                }
            }
            .widgetBackground(backgroundView: Color.clear)
    }

    private var rectangular: some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot?.glucose ?? "--")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(glucoseColor)
                Text(snapshot.map { "\(trendSymbol($0.trend)) \($0.delta ?? $0.units ?? "")" } ?? "CGM non aggiornato")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Sparkline(points: snapshot?.glucosePoints ?? [])
                .stroke(glucoseColor, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .widgetBackground(backgroundView: Color.clear)
    }

    private var inline: some View {
        Text(snapshot.map { "\($0.glucose ?? "--") \(trendSymbol($0.trend))" } ?? "Trio: CGM non aggiornato")
    }

    private var unavailable: some View {
        Image("ComplicationIcon").resizable().widgetAccentable().widgetBackground(backgroundView: Color.clear)
    }

    private var glucoseColor: Color {
        guard let hex = snapshot?.glucoseColor, !hex.isWhite, let color = Color(hex: hex) else {
            return Color(red: 0.22, green: 0.64, blue: 0.95)
        }
        return color
    }

    private func trendSymbol(_ trend: String?) -> String {
        switch trend?.lowercased() {
        case "tripleup", "triple up", "↑↑↑": "↑↑↑"
        case "doubleup", "double up", "⇈": "⇈"
        case "singleup", "single up", "↑": "↑"
        case "fortyfiveup", "forty five up", "↗": "↗"
        case "flat", "→": "→"
        case "fortyfivedown", "forty five down", "↘": "↘"
        case "singledown", "single down", "↓": "↓"
        case "doubledown", "double down", "⇊": "⇊"
        case "tripledown", "triple down", "↓↓↓": "↓↓↓"
        case "none", "not computable", "rate out of range", "?", "↔": "?"
        default: trend?.isEmpty == false ? trend! : "•"
        }
    }
}

private struct Sparkline: Shape {
    let points: [WatchWidgetSnapshot.GlucosePoint]

    func path(in rect: CGRect) -> Path {
        let values = Array(points.sorted { $0.date < $1.date }.suffix(18))
        guard values.count > 1,
              let minimum = values.map(\.glucose).min(),
              let maximum = values.map(\.glucose).max()
        else { return Path() }
        let span = max(maximum - minimum, 1)
        let timeSpan = max(values.last!.date.timeIntervalSince(values.first!.date), 1)
        var path = Path()
        for (index, point) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(point.date.timeIntervalSince(values.first!.date) / timeSpan)
            let y = rect.maxY - rect.height * CGFloat((point.glucose - minimum) / span)
            if index == 0 || point.date.timeIntervalSince(values[index - 1].date) > 10 * 60 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

private extension String {
    var isWhite: Bool {
        let value = trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        return value == "FFF" || value == "FFFFFF"
    }
}

private extension Color {
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

@main struct TrioWatchComplication: Widget {
    let kind = "TrioWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrioWatchComplicationProvider()) { entry in
            TrioWatchComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Trio glicemia")
        .description("Glicemia, andamento e grafico CGM più recente")
        .supportedFamilies([.accessoryInline, .accessoryCorner, .accessoryCircular, .accessoryRectangular])
    }
}

extension View {
    func widgetBackground(backgroundView: some View) -> some View {
        containerBackground(for: .widget) { backgroundView }
    }
}
