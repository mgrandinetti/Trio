import SwiftUI

/// Pump card of the detailed Home style. For an Omnipod with a known expiration it draws a
/// pod glyph plus reservoir and pod-life bars; for any other pump, or when that data is
/// missing, it hosts the stock `PumpView`. Colors and thresholds replicate `PumpView`
/// (`reservoirColor`, `timerColor`) exactly, without changing the original.
struct DetailedPumpCard: View {
    let reservoir: Decimal?
    let name: String
    let expiresAtDate: Date?
    let activatedAtDate: Date?
    let timerDate: Date
    let pumpStatusHighlightMessage: String?
    let battery: [OpenAPS_Battery]
    let lastCommsDate: Date?

    /// Same constant as `PumpView`.
    private let NORMAL_PATCH_AGE = TimeInterval.hours(80)
    /// Omnipod pod life (72 h) that the pod bar is measured against.
    private let podLifetime: TimeInterval = 72 * 3600
    /// Omnipod reports the reservoir level only below 50 U; the bar spans that range.
    private let reservoirScale: Decimal = 50
    /// Sentinel the pump manager uses for "50+ U".
    private let reservoirAboveReportingLimit: Decimal = 0xDEAD_BEEF

    private var isOmnipod: Bool {
        name.localizedCaseInsensitiveContains("omnipod") && expiresAtDate != nil
    }

    var body: some View {
        Group {
            if isOmnipod, let expiresAtDate {
                podContent(expiresAt: expiresAtDate)
            } else {
                PumpView(
                    reservoir: reservoir,
                    name: name,
                    expiresAtDate: expiresAtDate,
                    activatedAtDate: activatedAtDate,
                    timerDate: timerDate,
                    pumpStatusHighlightMessage: pumpStatusHighlightMessage,
                    battery: battery
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel(tintOpacity: 0.06, strokeOpacity: 0.2)
    }

    private func podContent(expiresAt: Date) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                podGlyph
                Text(verbatim: name.localizedCaseInsensitiveContains("dash") ? "DASH" : "POD")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                bar(
                    title: String(localized: "Insulin reservoir", comment: "Detailed Home pump card"),
                    value: reservoirText,
                    fraction: reservoirFraction,
                    color: reservoirColor
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Reservoir"))
                .accessibilityValue(Text(reservoirText))

                let remaining = expiresAt.timeIntervalSince(timerDate)
                bar(
                    title: String(localized: "Pod", comment: "Detailed Home pump card"),
                    value: remainingTimeString(time: remaining),
                    fraction: max(0, min(remaining / podLifetime, 1)),
                    color: timerColor
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Pod expiration"))
                .accessibilityValue(Text(remainingTimeString(time: remaining)))

                statusLine
            }
        }
    }

    private var podGlyph: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(Color.primary.opacity(0.85))
            .frame(width: 30, height: 42)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 18, height: 12)
                    .padding(.top, 5)
            }
            .overlay(alignment: .bottom) {
                Circle()
                    .fill(Color.insulin)
                    .frame(width: 8, height: 8)
                    .padding(.bottom, 6)
            }
            .accessibilityHidden(true)
    }

    /// Pump alert when there is one (same message the stock header shows instead of the
    /// pump info), otherwise the time since the last pump communication.
    @ViewBuilder private var statusLine: some View {
        if let pumpStatusHighlightMessage {
            Label(pumpStatusHighlightMessage.replacingOccurrences(of: "\n", with: " "), systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).fontWeight(.bold)
                .foregroundStyle(Color.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if let lastCommsDate {
            Text(String(
                format: String(localized: "Communication %@ ago", comment: "Detailed Home pump card: last pump communication"),
                TimeAgoFormatter.minutesAgo(from: lastCommsDate)
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private func bar(title: String, value: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(value)
                    .font(.caption).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Reservoir

    private var reservoirText: String {
        guard let reservoir else { return "--" }
        if reservoir == reservoirAboveReportingLimit {
            return "50+ " + String(localized: "U", comment: "Insulin unit")
        }
        return (Formatter.integerFormatter.string(from: reservoir as NSNumber) ?? "0")
            + String(localized: " U", comment: "Insulin unit")
    }

    private var reservoirFraction: Double {
        guard let reservoir else { return 0 }
        if reservoir == reservoirAboveReportingLimit { return 1 }
        let fraction = ((reservoir / reservoirScale) as NSDecimalNumber).doubleValue
        return max(0, min(fraction, 1))
    }

    /// Copy of `PumpView.reservoirColor`.
    private var reservoirColor: Color {
        guard let reservoir = reservoir else {
            return .gray
        }

        switch reservoir {
        case ...10:
            return Color.loopRed
        case ...30:
            return Color.orange
        default:
            return Color.insulin
        }
    }

    // MARK: - Pod life

    /// Copy of `PumpView.timerColor`.
    private var timerColor: Color {
        if let activatedAt = activatedAtDate {
            return abs(activatedAt.timeIntervalSinceNow) > NORMAL_PATCH_AGE ? Color.yellow : Color.loopGreen
        }

        guard let expiresAt = expiresAtDate else {
            return .gray
        }

        let time = expiresAt.timeIntervalSince(timerDate)

        switch time {
        case ...8.hours.timeInterval:
            return Color.loopRed
        case ...1.days.timeInterval:
            return Color.orange
        default:
            return Color.loopGreen
        }
    }

    /// Copy of `PumpView.remainingTimeString`.
    private func remainingTimeString(time: TimeInterval) -> String {
        guard time > 0 else {
            return String(localized: "Replace pod", comment: "View/Header when pod expired")
        }

        var time = time
        let days = Int(time / 1.days.timeInterval)
        time -= days.days.timeInterval
        let hours = Int(time / 1.hours.timeInterval)
        time -= hours.hours.timeInterval
        let minutes = Int(time / 1.minutes.timeInterval)

        if days >= 1 {
            return "\(days)" + String(localized: "d", comment: "abbreviation for days") + " \(hours)" +
                String(localized: "h", comment: "abbreviation for hours")
        }

        if hours >= 1 {
            var remainingHoursString = "\(hours)" + String(localized: "h", comment: "abbreviation for hours")
            if hours < 12 {
                remainingHoursString += " " + "\(minutes)" +
                    String(localized: "m", comment: "abbreviation for minutes")
            }
            return remainingHoursString
        }

        return "\(minutes)" + String(localized: "m", comment: "abbreviation for minutes")
    }
}
