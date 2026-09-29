import SwiftUI

// Detailed Home style (`HomeChartStyle.detailed`): a large glucose value, loop and pump cards,
// a row with IOB / COB / basal / eventual glucose, then the detailed chart stack. Kept apart
// from the stock header so the `.trio` layout stays as upstream ships it. Presentation only.

enum DetailedHomeLayout {
    /// glucose row + loop / pump cards
    static let headerHeight: CGFloat = 178
    static let glucoseRowHeight: CGFloat = 62
    static let cardHeight: CGFloat = 100
    static let horizontalPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 10
}

/// Bolus and carbs entered at a selected chart point.
struct ChartSelectionTreatments {
    let bolus: Decimal?
    let carbs: Decimal?
}

extension ChartSelectionLookup {
    /// Sums the boluses and carb entries inside the selection window, so each entry belongs
    /// to exactly one 5-minute scrub step.
    static func treatments(
        at date: Date,
        insulin: [PumpEventStored],
        carbs: [CarbEntryStored]
    ) -> ChartSelectionTreatments {
        let lower = date.addingTimeInterval(-window)
        let upper = date.addingTimeInterval(window)
        func inWindow(_ entryDate: Date?) -> Bool {
            guard let entryDate else { return false }
            return entryDate >= lower && entryDate < upper
        }

        let boluses = insulin
            .filter { inWindow($0.timestamp) }
            .compactMap { ($0.bolus?.amount).map { $0.decimalValue } }
            .filter { $0 != 0 }
        let carbAmounts = carbs
            .filter { inWindow($0.date) && $0.carbs > 0 }
            .map { Decimal($0.carbs) }

        return ChartSelectionTreatments(
            bolus: boluses.isEmpty ? nil : boluses.reduce(0, +),
            carbs: carbAmounts.isEmpty ? nil : carbAmounts.reduce(0, +)
        )
    }
}

extension Home.RootView {
    @ViewBuilder func detailedDashboardContent(_ geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Group {
                if let apsManager = state.apsManager, let bluetoothManager = apsManager.bluetoothManager,
                   bluetoothManager.bluetoothAuthorization != .authorized
                {
                    BluetoothRequiredView()
                } else {
                    detailedHeader(width: geo.size.width)
                }
            }
            .frame(height: DetailedHomeLayout.headerHeight)

            detailedMealPanel()
                .frame(height: HomeLayout.mealSlotHeight)
                .animation(ChartSelectionLookup.readoutFade, value: isChartReadoutVisible)
                .task(id: chartSelection) { await updateChartReadout() }

            detailedMainChart(geo: geo)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func detailedMainChart(geo: GeometryProxy) -> some View {
        let chartHeight = max(
            geo.size.height - DetailedHomeLayout.headerHeight - HomeLayout.mealSlotHeight - HomeLayout.bottomZoneHeight,
            HomeLayout.chartMinHeight
        )
        MainChartView(
            geo: geo,
            chartHeight: chartHeight,
            units: state.units,
            highGlucose: state.highGlucose,
            lowGlucose: state.lowGlucose,
            currentGlucoseTarget: state.currentGlucoseTarget,
            glucoseColorScheme: state.glucoseColorScheme,
            displayXgridLines: state.displayXgridLines,
            displayYgridLines: state.displayYgridLines,
            thresholdLines: state.thresholdLines,
            state: state,
            chartStyle: .detailed,
            selection: $chartSelection
        )
        .frame(height: chartHeight)
    }

    // MARK: - Header

    @ViewBuilder private func detailedHeader(width: CGFloat) -> some View {
        let inner = width - 2 * DetailedHomeLayout.horizontalPadding - DetailedHomeLayout.cardSpacing
        VStack(spacing: 8) {
            detailedGlucoseRow
                .frame(height: DetailedHomeLayout.glucoseRowHeight)

            HStack(spacing: DetailedHomeLayout.cardSpacing) {
                detailedLoopCard
                    .frame(width: max(inner / 3, 0))
                detailedPumpCard
                    .frame(maxWidth: .infinity)
            }
            .frame(height: DetailedHomeLayout.cardHeight)
        }
        .padding(.horizontal, DetailedHomeLayout.horizontalPadding)
    }

    private var detailedGlucoseRow: some View {
        DetailedGlucoseRow(
            units: state.units,
            cgmAvailable: state.cgmAvailable,
            glucose: state.latestTwoGlucoseValues,
            cgmStatus: state.cgmDisplayState,
            highGlucose: state.highGlucose,
            lowGlucose: state.lowGlucose,
            currentGlucoseTarget: state.currentGlucoseTarget,
            glucoseColorScheme: state.glucoseColorScheme,
            timerDate: state.timerDate
        )
        // same gestures as the stock glucose bobble
        .contentShape(Rectangle())
        .onTapGesture {
            if !state.cgmAvailable {
                showCGMSelection.toggle()
            } else {
                state.shouldDisplayCGMSetupSheet.toggle()
            }
        }
        .onLongPressGesture {
            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
            impactHeavy.impactOccurred()
            showSnoozeSheet = true
        }
        .accessibilityAction {
            if !state.cgmAvailable {
                showCGMSelection.toggle()
            } else {
                state.shouldDisplayCGMSetupSheet.toggle()
            }
        }
        .accessibilityAction(named: Text("Snooze alerts")) {
            showSnoozeSheet = true
        }
    }

    private var detailedLoopCard: some View {
        DetailedLoopCard(
            dosingMode: state.dosingMode,
            timerDate: state.timerDate,
            isLooping: state.isLooping,
            lastLoopDate: state.lastLoopDate,
            manualTempBasal: state.manualTempBasal,
            hasDeviceIssue: state.hasDeviceIssue,
            determination: state.determinationsFromPersistence
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.isLoopStatusPresented = true
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(String(localized: "Opens loop status", comment: "Accessibility hint")))
        .accessibilityAction { state.isLoopStatusPresented = true }
    }

    private var detailedPumpCard: some View {
        DetailedPumpCard(
            reservoir: state.reservoir,
            name: state.pumpName,
            expiresAtDate: state.pumpExpiresAtDate,
            activatedAtDate: state.pumpActivatedAtDate,
            timerDate: state.timerDate,
            pumpStatusHighlightMessage: state.pumpStatusHighlightMessage,
            battery: state.batteryFromPersistence,
            lastCommsDate: state.lastPumpCommsDate
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if state.pumpDisplayState == nil {
                showPumpSelection.toggle()
            } else {
                state.shouldDisplayPumpSetupSheet.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(
            state.pumpDisplayState == nil
                ? String(localized: "Opens pump setup", comment: "Accessibility hint")
                : String(localized: "Opens pump settings", comment: "Accessibility hint")
        ))
        .accessibilityAction {
            if state.pumpDisplayState == nil {
                showPumpSelection.toggle()
            } else {
                state.shouldDisplayPumpSetupSheet.toggle()
            }
        }
    }

    // MARK: - Stats row (meal slot)

    /// IOB / COB / basal / eventual glucose, with the chart readout cross-fading over it while
    /// the chart is scrubbed (same mechanism as the stock meal panel).
    @ViewBuilder private func detailedMealPanel() -> some View {
        ZStack {
            detailedStatsRow
                .opacity(isChartReadoutVisible ? 0 : 1)

            if let readoutDate = chartReadoutDate,
               let selectedGlucose = ChartSelectionLookup.glucose(at: readoutDate, in: state.glucoseFromPersistence)
            {
                ChartSelectionRow(
                    selectedGlucose: selectedGlucose,
                    determination: nil,
                    units: state.units,
                    highGlucose: state.highGlucose,
                    lowGlucose: state.lowGlucose,
                    currentGlucoseTarget: state.currentGlucoseTarget,
                    glucoseColorScheme: state.glucoseColorScheme,
                    isSmoothingEnabled: state.settingsManager.settings.smoothGlucose,
                    treatments: ChartSelectionLookup.treatments(
                        at: readoutDate,
                        insulin: state.insulinFromPersistence,
                        carbs: state.carbsFromPersistence
                    )
                )
                .padding(.horizontal)
                .opacity(isChartReadoutVisible ? 1 : 0)
                .allowsHitTesting(isChartReadoutVisible)
            }
        }
    }

    private var detailedStatsRow: some View {
        let determination = state.enactedAndNonEnactedDeterminations.first
        let iob = (Formatter.decimalFormatterWithTwoFractionDigits.string(from: state.currentIOB as NSNumber) ?? "0")
            + String(localized: " U", comment: "Insulin unit")
        let cob = (Formatter.integerFormatter.string(from: NSNumber(value: determination?.cob ?? 0)) ?? "0")
            + String(localized: " g", comment: "gram of carbs")
        let basal = (state.tempBasals.last?.tempBasal?.rate).map {
            (Formatter.decimalFormatterWithTwoFractionDigits.string(from: $0) ?? "\($0)")
                + String(localized: " U/hr", comment: "Unit per hour with space")
        }
        let eventual = (determination?.eventualBG).map {
            state.units == .mgdL ? ($0 as Decimal).description : ($0 as Decimal).formattedAsMmolL
        }

        return HStack(alignment: .center, spacing: 8) {
            statColumn(title: String(localized: "IOB"), value: iob)
            statColumn(title: String(localized: "COB"), value: cob)
            if let basal {
                statColumn(title: String(localized: "Current basal", comment: "Detailed Home stats row title"), value: basal)
            }
            if let eventual {
                statColumn(title: String(localized: "Eventual", comment: "Detailed Home stats row title"), value: eventual)
            }
            alarmsPill
        }
        .padding(.horizontal, DetailedHomeLayout.horizontalPadding)
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Glucose row

struct DetailedGlucoseRow: View {
    let units: GlucoseUnits
    let cgmAvailable: Bool
    /// last two readings, oldest first
    let glucose: [GlucoseStored]
    let cgmStatus: CgmDisplayState?
    let highGlucose: Decimal
    let lowGlucose: Decimal
    let currentGlucoseTarget: Decimal
    let glucoseColorScheme: GlucoseColorScheme
    /// ticks the minutes-ago caption
    let timerDate: Date

    /// Same freshness gate as the stock bobble: older readings are masked.
    private var freshReading: GlucoseStored? {
        guard let last = glucose.last, let date = last.date, timerDate.timeIntervalSince(date) < 12 * 60 else {
            return nil
        }
        return last
    }

    private var deltaString: String? {
        guard glucose.count >= 2, let last = glucose.last, let first = glucose.first else { return nil }
        var delta = Decimal(last.glucose) - Decimal(first.glucose)
        if units == .mmolL { delta = delta.asMmolL }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = units == .mmolL ? 1 : 0
        formatter.maximumFractionDigits = units == .mmolL ? 1 : 0
        formatter.positivePrefix = "+"
        return formatter.string(from: delta as NSNumber)
    }

    /// Trend arrow symbol and how many times to repeat it (double/triple arrows).
    private var trendArrow: (symbol: String, count: Int)? {
        switch freshReading?.directionEnum {
        case .tripleUp: return ("arrow.up", 3)
        case .doubleUp: return ("arrow.up", 2)
        case .singleUp: return ("arrow.up", 1)
        case .fortyFiveUp: return ("arrow.up.right", 1)
        case .flat: return ("arrow.right", 1)
        case .fortyFiveDown: return ("arrow.down.right", 1)
        case .singleDown: return ("arrow.down", 1)
        case .doubleDown: return ("arrow.down", 2)
        case .tripleDown: return ("arrow.down", 3)
        default: return nil
        }
    }

    var body: some View {
        if !cgmAvailable {
            HStack(spacing: 10) {
                Image(systemName: "sensor.tag.radiowaves.forward.fill").font(.title2)
                Text("Add CGM").font(.headline)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        } else if let reading = freshReading {
            let color = selectionMarkColor(
                for: reading,
                highGlucose: highGlucose,
                lowGlucose: lowGlucose,
                currentGlucoseTarget: currentGlucoseTarget,
                glucoseColorScheme: glucoseColorScheme
            )
            let value = reading.glucose == 400
                ? "HIGH"
                : (units == .mgdL ? Decimal(reading.glucose).description : Decimal(reading.glucose).formattedAsMmolL)

            HStack(alignment: .center, spacing: 10) {
                Text(value)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let arrow = trendArrow {
                    HStack(spacing: -6) {
                        ForEach(0 ..< arrow.count, id: \.self) { _ in
                            Image(systemName: arrow.symbol)
                        }
                    }
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 0) {
                    if let deltaString {
                        Text(deltaString)
                            .font(.title3).fontWeight(.bold).fontDesign(.rounded)
                    }
                    Text(units.rawValue)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(TimeAgoFormatter.minutesAgo(from: reading.date))
                    .font(.callout).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(
                [
                    String(localized: "Glucose", comment: "Accessibility: glucose label") + " \(value) \(units.rawValue)",
                    deltaString.map { String(localized: "delta", comment: "Accessibility: glucose delta") + " \($0)" },
                    TimeAgoFormatter.minutesAgoAccessible(from: reading.date)
                ].compactMap { $0 }.joined(separator: ", ")
            ))
        } else {
            HStack(spacing: 10) {
                Text(verbatim: "--")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                if let status = cgmStatus, !status.localizedMessage.isEmpty {
                    Text(status.localizedMessage.replacingOccurrences(of: "\n", with: " "))
                        .font(.callout).fontWeight(.semibold)
                        .foregroundStyle(status.status == .critical ? Color.loopRed : Color.orange)
                        .lineLimit(2)
                }
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(String(localized: "Glucose unavailable", comment: "Accessibility: no fresh glucose")))
        }
    }
}

// MARK: - Loop card

/// Loop state card: ring colored like `LoopView` (same rules, reused), minutes since the last
/// loop in the middle, dosing mode and last-loop caption below.
struct DetailedLoopCard: View {
    let dosingMode: DosingMode
    let timerDate: Date
    let isLooping: Bool
    let lastLoopDate: Date
    let manualTempBasal: Bool
    let hasDeviceIssue: Bool
    let determination: [OrefDetermination]

    private var color: Color {
        LoopView.ringColor(
            automation: dosingMode.automation,
            manualTempBasal: manualTempBasal,
            hasDeviceIssue: hasDeviceIssue,
            hasEnactedDetermination: determination.first?.timestamp != nil,
            secondsSinceLastLoop: timerDate.timeIntervalSince(lastLoopDate)
        )
    }

    private var ringGap: CGFloat {
        LoopView.ringGap(automation: dosingMode.automation, manualTempBasal: manualTempBasal)
    }

    /// Minutes since the last loop, nil when unknown or older than a day.
    private var minutesSinceLoop: Int? {
        guard determination.first?.deliverAt != nil else { return nil }
        let minutes = Int(timerDate.timeIntervalSince(lastLoopDate) / 60)
        return (0 ... 1440).contains(minutes) ? minutes : nil
    }

    private var caption: String {
        if isLooping { return String(localized: "looping") }
        if manualTempBasal { return String(localized: "Manual") }
        guard minutesSinceLoop != nil else { return "--" }
        return String(
            format: String(localized: "last %@ ago", comment: "Detailed Home loop card: time since last loop"),
            TimeAgoFormatter.minutesAgo(from: lastLoopDate)
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if ringGap == 0 {
                    Circle().stroke(color, lineWidth: 4)
                } else {
                    Circle()
                        .trim(from: ringGap / 2, to: 0.5 - ringGap / 2)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    Circle()
                        .trim(from: 0.5 + ringGap / 2, to: 1 - ringGap / 2)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                if isLooping {
                    ProgressView()
                } else if !manualTempBasal, let symbol = LoopView.centerSymbol(automation: dosingMode.automation) {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color)
                } else if let minutesSinceLoop {
                    Text(verbatim: "\(minutesSinceLoop)'")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 40, height: 40)

            Text(dosingMode.displayName)
                .font(.footnote).fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel(tint: color, tintOpacity: 0.10, strokeOpacity: 0.25)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([dosingMode.displayName, caption].joined(separator: ", ")))
    }
}
