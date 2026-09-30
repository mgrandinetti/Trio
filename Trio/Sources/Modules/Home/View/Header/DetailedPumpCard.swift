import SwiftUI

/// Pump card of the detailed Home style. For an Omnipod with a known expiration it draws a
/// pod glyph plus reservoir and pod-life bars; for any other pump, or when that data is
/// missing, it hosts the stock `PumpView`. Thresholds replicate `PumpView` (`reservoirColor`,
/// `timerColor`) exactly, without changing the original; the colors are the detailed palette's.
struct DetailedPumpCard: View {
    let reservoir: Decimal?
    let name: String
    let expiresAtDate: Date?
    let activatedAtDate: Date?
    let timerDate: Date
    let pumpStatusHighlightMessage: String?
    let battery: [OpenAPS_Battery]
    let lastCommsDate: Date?

    @Environment(\.colorScheme) var colorScheme

    private var palette: DetailedPalette { DetailedPalette(colorScheme) }

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
                // the stock column is taller than this compact card
                .scaleEffect(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .detailedCard(palette, cornerRadius: 17)
    }

    private func podContent(expiresAt: Date) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                podGlyph
                Text(verbatim: name.localizedCaseInsensitiveContains("dash") ? "DASH" : "POD")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.muted)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

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
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(white: 0.95))
            .frame(width: 28, height: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(white: 0.72), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.88))
                    .frame(width: 16, height: 9)
                    .padding(.top, 5)
            }
            .overlay(alignment: .bottom) {
                Circle()
                    .fill(Color(red: 0.15, green: 0.56, blue: 0.94))
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.carbs)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if let lastCommsDate {
            HStack(spacing: 6) {
                Circle()
                    .fill(palette.glucose)
                    .frame(width: 4, height: 4)
                Text(String(
                    format: String(localized: "Communication %@ ago", comment: "Detailed Home pump card: last pump communication"),
                    TimeAgoFormatter.minutesAgo(from: lastCommsDate)
                ))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
    }

    /// Title and value on one row, the level bar below.
    private func bar(title: String, value: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.rail)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 3)
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

    /// `PumpView.reservoirColor` thresholds.
    private var reservoirColor: Color {
        guard let reservoir = reservoir else {
            return palette.muted
        }

        switch reservoir {
        case ...10:
            return palette.low
        case ...30:
            return palette.carbs
        default:
            return palette.insulin
        }
    }

    // MARK: - Pod life

    /// `PumpView.timerColor` thresholds.
    private var timerColor: Color {
        if let activatedAt = activatedAtDate {
            return abs(activatedAt.timeIntervalSinceNow) > NORMAL_PATCH_AGE ? palette.high : palette.glucose
        }

        guard let expiresAt = expiresAtDate else {
            return palette.muted
        }

        let time = expiresAt.timeIntervalSince(timerDate)

        switch time {
        case ...8.hours.timeInterval:
            return palette.low
        case ...1.days.timeInterval:
            return palette.carbs
        default:
            return palette.glucose
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
